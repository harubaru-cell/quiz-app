import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/deck_stats.dart';
import '../models/question_progress.dart';
import '../models/quiz_deck.dart';
import '../models/quiz_history.dart';
import '../models/study_cycle.dart';
import '../repositories/deck_repository.dart';
import '../repositories/history_repository.dart';
import '../repositories/question_progress_repository.dart';
import '../repositories/study_cycle_repository.dart';
import '../services/audio_storage_service.dart';
import '../services/json_import_service.dart';
import '../services/storage_service.dart';
import '../services/zip_import_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    StorageService? storageService,
    JsonImportService? jsonImportService,
    ZipImportService? zipImportService,
    Uuid? uuid,
  })  : _storageService = storageService ?? StorageService(),
        _jsonImportService = jsonImportService ?? JsonImportService(),
        _zipImportService = zipImportService ?? ZipImportService(),
        _uuid = uuid ?? const Uuid() {
    _deckRepository = DeckRepository(_storageService);
    _historyRepository = HistoryRepository(_storageService);
    _questionProgressRepository = QuestionProgressRepository(_storageService);
    _studyCycleRepository = StudyCycleRepository(_storageService);
  }

  final StorageService _storageService;
  final JsonImportService _jsonImportService;
  final ZipImportService _zipImportService;
  final Uuid _uuid;

  late final DeckRepository _deckRepository;
  late final HistoryRepository _historyRepository;
  late final QuestionProgressRepository _questionProgressRepository;
  late final StudyCycleRepository _studyCycleRepository;

  List<QuizDeck> _decks = <QuizDeck>[];
  List<QuizHistory> _histories = <QuizHistory>[];
  Map<String, DeckStats> _stats = <String, DeckStats>{};
  Map<String, Map<String, QuestionProgress>> _questionProgress =
      <String, Map<String, QuestionProgress>>{};
  Map<String, StudyCycle> _studyCycles = <String, StudyCycle>{};

  bool _isLoading = false;
  String? _message;

  List<QuizDeck> get decks => List.unmodifiable(_decks);
  bool get isLoading => _isLoading;
  String? get message => _message;

  DeckStats statsFor(String deckId) {
    return _stats[deckId] ?? DeckStats.empty(deckId);
  }

  QuestionProgress questionProgressFor(
    String deckId,
    String questionId,
  ) {
    return _questionProgress[deckId]?[questionId] ??
        QuestionProgress.unanswered(
          deckId: deckId,
          questionId: questionId,
        );
  }

  List<QuestionProgress> questionProgressForDeck(String deckId) {
    return List<QuestionProgress>.unmodifiable(
      _questionProgress[deckId]?.values ?? const <QuestionProgress>[],
    );
  }

  StudyCycle? studyCycleFor(String deckId) => _studyCycles[deckId];

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _decks = await _deckRepository.loadDecks();
      _histories = await _historyRepository.loadHistories();
      _stats = await _historyRepository.loadStats();

      var progressSnapshot = await _questionProgressRepository.loadProgress();

      if (progressSnapshot == null) {
        progressSnapshot = _questionProgressRepository.migrateFromHistories(
          _histories,
        );
        await _questionProgressRepository.saveProgress(progressSnapshot);
      }

      _replaceQuestionProgress(progressSnapshot.items);

      final studyCycleSnapshot = await _studyCycleRepository.loadCycles();
      _replaceStudyCycles(studyCycleSnapshot.items);

      if (_reconcileStudyCycleAnswers()) {
        await _questionProgressRepository.saveProgress(
          _createQuestionProgressSnapshot(),
        );
      }
      _message = null;
    } catch (error) {
      _message = '保存データの読み込みに失敗しました: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _replaceQuestionProgress(List<QuestionProgress> progressItems) {
    final progressByDeck = <String, Map<String, QuestionProgress>>{};

    for (final progress in progressItems) {
      progressByDeck
          .putIfAbsent(
            progress.deckId,
            () => <String, QuestionProgress>{},
          )
          .putIfAbsent(progress.questionId, () => progress);
    }

    _questionProgress = progressByDeck;
  }

  void _replaceStudyCycles(List<StudyCycle> cycles) {
    _studyCycles = <String, StudyCycle>{
      for (final cycle in cycles) cycle.deckId: cycle,
    };
  }

  bool _reconcileStudyCycleAnswers() {
    var changed = false;

    for (final cycle in _studyCycles.values) {
      for (final answer in cycle.answeredEvents) {
        final current = questionProgressFor(
          cycle.deckId,
          answer.questionId,
        );
        final lastAnsweredAt = current.lastAnsweredAt;

        if (lastAnsweredAt != null &&
            !lastAnsweredAt.isBefore(answer.answeredAt)) {
          continue;
        }

        _questionProgress.putIfAbsent(
          cycle.deckId,
          () => <String, QuestionProgress>{},
        )[answer.questionId] = current.recordAnswer(
          isCorrect: answer.isCorrect,
          answeredAt: answer.answeredAt,
        );
        changed = true;
      }
    }

    return changed;
  }

  Future<void> recordQuestionResult(
    String deckId,
    QuestionResult result,
  ) async {
    _applyQuestionResult(deckId, result);

    try {
      await _questionProgressRepository.saveProgress(
        _createQuestionProgressSnapshot(),
      );
    } catch (error) {
      _message = '問題別進捗の保存に失敗しました: $error';
    }

    notifyListeners();
  }

  Future<StudyCycle?> startStudyCycle({
    required String deckId,
    required String deckSignature,
    required List<String> orderedQuestionIds,
    required int batchSize,
  }) async {
    final now = DateTime.now();
    final previousCycle = _studyCycles[deckId];

    if (previousCycle != null && previousCycle.answeredEvents.isNotEmpty) {
      try {
        await _questionProgressRepository.saveProgress(
          _createQuestionProgressSnapshot(),
        );
      } catch (error) {
        _message = '問題別進捗を保存できないため、新しい一周を開始できませんでした: $error';
        notifyListeners();
        return null;
      }
    }

    final cycle = StudyCycle.start(
      cycleId: _uuid.v4(),
      deckId: deckId,
      deckSignature: deckSignature,
      orderedQuestionIds: orderedQuestionIds,
      batchSize: batchSize,
      startedAt: now,
    );

    _studyCycles[deckId] = cycle;

    try {
      await _studyCycleRepository.saveCycles(
        _createStudyCycleSnapshot(),
      );
    } catch (error) {
      if (previousCycle == null) {
        _studyCycles.remove(deckId);
      } else {
        _studyCycles[deckId] = previousCycle;
      }
      _message = '一周学習の保存に失敗しました: $error';
      notifyListeners();
      return null;
    }

    notifyListeners();
    return cycle;
  }

  Future<void> recordStudyCycleQuestionResult({
    required String deckId,
    required String cycleId,
    required QuestionResult result,
  }) async {
    final currentCycle = _studyCycles[deckId];

    if (currentCycle == null || currentCycle.cycleId != cycleId) {
      _message = '一周学習の状態が更新されているため、この回答を保存できませんでした。';
      notifyListeners();
      throw StateError(_message!);
    }
    if (currentCycle.nextQuestionId != result.questionId) {
      _message = '一周学習で予定されている問題と回答が一致しないため、保存できませんでした。';
      notifyListeners();
      throw StateError(_message!);
    }

    late final StudyCycle nextCycle;

    try {
      nextCycle = currentCycle.recordAnswer(
        questionId: result.questionId,
        isCorrect: result.isCorrect,
        answeredAt: result.answeredAt,
      );
    } catch (error) {
      _message = '一周学習の位置を更新できませんでした: $error';
      notifyListeners();
      throw StateError(_message!);
    }

    _studyCycles[deckId] = nextCycle;

    try {
      await _studyCycleRepository.saveCycles(
        _createStudyCycleSnapshot(),
      );
    } catch (error) {
      _studyCycles[deckId] = currentCycle;
      _message = '一周学習の回答位置を保存できませんでした: $error';
      notifyListeners();
      throw StateError(_message!);
    }

    _applyQuestionResult(deckId, result);

    try {
      await _questionProgressRepository.saveProgress(
        _createQuestionProgressSnapshot(),
      );
    } catch (error) {
      _message = '問題別進捗の保存に失敗しました。次回起動時に一周学習の記録から復旧します: $error';
    }

    notifyListeners();
  }

  void _applyQuestionResult(
    String deckId,
    QuestionResult result,
  ) {
    final progressByQuestion = _questionProgress.putIfAbsent(
      deckId,
      () => <String, QuestionProgress>{},
    );
    final current = progressByQuestion[result.questionId] ??
        QuestionProgress.unanswered(
          deckId: deckId,
          questionId: result.questionId,
        );

    progressByQuestion[result.questionId] = current.recordAnswer(
      isCorrect: result.isCorrect,
      answeredAt: result.answeredAt,
    );
  }

  QuestionProgressSnapshot _createQuestionProgressSnapshot() {
    final items = _questionProgress.values
        .expand((progressByQuestion) => progressByQuestion.values)
        .toList()
      ..sort((left, right) {
        final deckComparison = left.deckId.compareTo(right.deckId);

        if (deckComparison != 0) {
          return deckComparison;
        }

        return left.questionId.compareTo(right.questionId);
      });

    return QuestionProgressSnapshot(
      schemaVersion: QuestionProgressSnapshot.currentSchemaVersion,
      items: items,
    );
  }

  StudyCycleSnapshot _createStudyCycleSnapshot() {
    final items = _studyCycles.values.toList()
      ..sort((left, right) => left.deckId.compareTo(right.deckId));

    return StudyCycleSnapshot(
      schemaVersion: StudyCycleSnapshot.currentSchemaVersion,
      items: items,
    );
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
    final alreadyRecorded = _histories.any(
      (item) => item.id == history.id,
    );

    if (!alreadyRecorded) {
      _histories = <QuizHistory>[
        ..._histories,
        history,
      ];

      final previous =
          _stats[history.deckId] ?? DeckStats.empty(history.deckId);

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
    }

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
