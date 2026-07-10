import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/deck_stats.dart';
import '../models/quiz_deck.dart';
import '../models/quiz_history.dart';
import '../repositories/deck_repository.dart';
import '../repositories/history_repository.dart';
import '../services/audio_storage_service.dart';
import '../services/json_import_service.dart';
import '../services/storage_service.dart';
import '../services/zip_import_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    StorageService? storageService,
    JsonImportService? jsonImportService,
    ZipImportService? zipImportService,
  })  : _storageService = storageService ?? StorageService(),
        _jsonImportService = jsonImportService ?? JsonImportService(),
        _zipImportService = zipImportService ?? ZipImportService() {
    _deckRepository = DeckRepository(_storageService);
    _historyRepository = HistoryRepository(_storageService);
  }

  final StorageService _storageService;
  final JsonImportService _jsonImportService;
  final ZipImportService _zipImportService;

  late final DeckRepository _deckRepository;
  late final HistoryRepository _historyRepository;

  List<QuizDeck> _decks = <QuizDeck>[];
  List<QuizHistory> _histories = <QuizHistory>[];
  Map<String, DeckStats> _stats = <String, DeckStats>{};

  bool _isLoading = false;
  String? _message;

  List<QuizDeck> get decks => List.unmodifiable(_decks);
  bool get isLoading => _isLoading;
  String? get message => _message;

  DeckStats statsFor(String deckId) {
    return _stats[deckId] ?? DeckStats.empty(deckId);
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _decks = await _deckRepository.loadDecks();
      _histories = await _historyRepository.loadHistories();
      _stats = await _historyRepository.loadStats();
      _message = null;
    } catch (error) {
      _message = '保存データの読み込みに失敗しました: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importDeckFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'json',
          'zip',
        ],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null) {
        throw const FormatException(
          'ファイルを読み込めませんでした。',
        );
      }

      final extension = _getFileExtension(file);

      final QuizDeck deck;

      if (extension == 'json') {
        final source = utf8.decode(bytes);
        deck = _jsonImportService.parseDeck(source);
      } else if (extension == 'zip') {
        deck = await _zipImportService.importDeck(bytes);
      } else {
        throw const FormatException(
          'JSONまたはZIPファイルを選択してください。',
        );
      }

      await _saveImportedDeck(deck);
    } catch (error) {
      _message = 'デッキの追加に失敗しました: $error';
      notifyListeners();
    }
  }

  Future<void> importDeckFromBytes(
    Uint8List bytes,
  ) async {
    final source = utf8.decode(bytes);
    final deck = _jsonImportService.parseDeck(source);

    await _saveImportedDeck(deck);
  }

  Future<void> _saveImportedDeck(
    QuizDeck deck,
  ) async {
    _decks = <QuizDeck>[
      ..._decks.where(
        (item) => item.id != deck.id,
      ),
      deck,
    ];

    _stats.putIfAbsent(
      deck.id,
      () => DeckStats.empty(deck.id),
    );

    await _deckRepository.saveDecks(_decks);
    await _historyRepository.saveStats(_stats);

    _message = '「${deck.title}」を追加しました。';
    notifyListeners();
  }

  String _getFileExtension(
    PlatformFile file,
  ) {
    final extension = file.extension?.trim().toLowerCase();

    if (extension != null && extension.isNotEmpty) {
      return extension;
    }

    final dotIndex = file.name.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == file.name.length - 1) {
      return '';
    }

    return file.name.substring(dotIndex + 1).toLowerCase();
  }

  Future<void> deleteDeck(String deckId) async {
    QuizDeck? deckToDelete;

    for (final deck in _decks) {
      if (deck.id == deckId) {
        deckToDelete = deck;
        break;
      }
    }

    if (deckToDelete != null) {
      final audioStorageService = AudioStorageService.instance;

      for (final question in deckToDelete.questions) {
        final audio = question.audio;

        if (audio == null ||
            !audioStorageService.isStoredAudioReference(audio)) {
          continue;
        }

        final storageKey =
            audioStorageService.getStorageKeyFromReference(audio);

        try {
          await audioStorageService.deleteAudio(
            storageKey,
          );
        } catch (_) {
          // 音声の削除に失敗しても、
          // デッキ本体の削除は続行する。
        }
      }
    }

    _decks = _decks.where((deck) => deck.id != deckId).toList();

    _histories =
        _histories.where((history) => history.deckId != deckId).toList();

    _stats.remove(deckId);

    await _deckRepository.saveDecks(_decks);
    await _historyRepository.saveHistories(
      _histories,
    );
    await _historyRepository.saveStats(_stats);

    _message = 'デッキを削除しました。';
    notifyListeners();
  }

  Future<void> recordHistory(
    QuizHistory history,
  ) async {
    _histories = <QuizHistory>[
      ..._histories,
      history,
    ];

    final previous = _stats[history.deckId] ?? DeckStats.empty(history.deckId);

    final incorrectIds = Set<String>.from(
      previous.incorrectQuestionIds,
    );

    for (final result in history.results) {
      if (result.isCorrect) {
        incorrectIds.remove(result.questionId);
      } else {
        incorrectIds.add(result.questionId);
      }
    }

    _stats[history.deckId] = previous.copyWith(
      attemptCount: previous.attemptCount + 1,
      totalAnswered: previous.totalAnswered + history.totalAnswered,
      totalCorrect: previous.totalCorrect + history.correctCount,
      lastPlayedAt: history.playedAt,
      incorrectQuestionIds: incorrectIds,
    );

    await _historyRepository.saveHistories(
      _histories,
    );
    await _historyRepository.saveStats(_stats);

    notifyListeners();
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }
}
