import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/quiz_deck.dart';
import '../models/quiz_question.dart';
import 'audio_storage_service.dart';
import 'json_import_service.dart';

class ZipImportService {
  ZipImportService({
    JsonImportService? jsonImportService,
    AudioStorageService? audioStorageService,
  })  : _jsonImportService = jsonImportService ?? JsonImportService(),
        _audioStorageService =
            audioStorageService ?? AudioStorageService.instance;

  final JsonImportService _jsonImportService;
  final AudioStorageService _audioStorageService;

  Future<QuizDeck> importDeck(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(
      zipBytes,
      verify: true,
    );

    final files = <String, Uint8List>{};

    for (var index = 0; index < archive.length; index++) {
      final entry = archive[index];

      if (!entry.isFile) {
        continue;
      }

      final path = _normalizePath(entry.name);

      if (path.isEmpty || path.startsWith('__MACOSX/')) {
        continue;
      }

      files[path] = archive.fileData(index);
    }

    final deckPaths = files.keys.where((path) {
      final lowerPath = path.toLowerCase();

      return lowerPath == 'deck.json' || lowerPath.endsWith('/deck.json');
    }).toList();

    if (deckPaths.isEmpty) {
      throw const FormatException(
        'ZIP内に deck.json が見つかりません。',
      );
    }

    if (deckPaths.length > 1) {
      throw const FormatException(
        'ZIP内の deck.json は1つだけにしてください。',
      );
    }

    final deckPath = deckPaths.single;
    final deckBytes = files[deckPath]!;

    var jsonSource = utf8.decode(deckBytes);

    if (jsonSource.startsWith('\uFEFF')) {
      jsonSource = jsonSource.substring(1);
    }

    final deck = _jsonImportService.parseDeck(jsonSource);

    final storedReferences = <int, String>{};
    final filesToSave = <_AudioFileToSave>[];

    for (var index = 0; index < deck.questions.length; index++) {
      final question = deck.questions[index];
      final audioPath = question.audio;

      if (audioPath == null) {
        continue;
      }

      if (_isNetworkAudio(audioPath) ||
          _audioStorageService.isStoredAudioReference(audioPath)) {
        continue;
      }

      final resolvedPath = _resolveAudioPath(
        deckPath: deckPath,
        audioPath: audioPath,
      );

      final audioBytes = files[resolvedPath];

      if (audioBytes == null) {
        throw FormatException(
          '問題 ${question.id} の音声ファイルが'
          'ZIP内に見つかりません: $audioPath',
        );
      }

      if (audioBytes.isEmpty) {
        throw FormatException(
          '問題 ${question.id} の音声ファイルが空です: '
          '$audioPath',
        );
      }

      final storageKey = '${deck.id}/$resolvedPath';
      final reference = _audioStorageService.createReference(storageKey);

      filesToSave.add(
        _AudioFileToSave(
          storageKey: storageKey,
          bytes: audioBytes,
        ),
      );

      storedReferences[index] = reference;
    }

    final savedKeys = <String>[];

    try {
      for (final file in filesToSave) {
        await _audioStorageService.saveAudio(
          storageKey: file.storageKey,
          bytes: file.bytes,
        );

        savedKeys.add(file.storageKey);
      }
    } catch (_) {
      for (final storageKey in savedKeys) {
        try {
          await _audioStorageService.deleteAudio(storageKey);
        } catch (_) {
          // 取り込み失敗時の後片付けなので、
          // 削除エラーは元のエラーより優先しない。
        }
      }

      rethrow;
    }

    final updatedQuestions = <QuizQuestion>[];

    for (var index = 0; index < deck.questions.length; index++) {
      final question = deck.questions[index];
      final storedReference = storedReferences[index];

      if (storedReference == null) {
        updatedQuestions.add(question);
        continue;
      }

      final questionJson = Map<String, dynamic>.from(question.toJson());

      questionJson['audio'] = storedReference;

      updatedQuestions.add(
        QuizQuestion.fromJson(questionJson),
      );
    }

    return deck.copyWith(
      questions: updatedQuestions,
      updatedAt: DateTime.now(),
    );
  }

  bool _isNetworkAudio(String path) {
    final uri = Uri.tryParse(path);

    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _resolveAudioPath({
    required String deckPath,
    required String audioPath,
  }) {
    final normalizedAudioPath = audioPath.replaceAll('\\', '/');

    if (normalizedAudioPath.startsWith('/')) {
      return _normalizePath(normalizedAudioPath);
    }

    final separatorIndex = deckPath.lastIndexOf('/');

    final deckDirectory =
        separatorIndex == -1 ? '' : deckPath.substring(0, separatorIndex);

    if (deckDirectory.isEmpty) {
      return _normalizePath(normalizedAudioPath);
    }

    return _normalizePath(
      '$deckDirectory/$normalizedAudioPath',
    );
  }

  String _normalizePath(String value) {
    var path = value.replaceAll('\\', '/');

    while (path.startsWith('./')) {
      path = path.substring(2);
    }

    while (path.startsWith('/')) {
      path = path.substring(1);
    }

    final normalizedParts = <String>[];

    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }

      if (part == '..') {
        throw const FormatException(
          'ZIP内のファイルパスに「..」は使用できません。',
        );
      }

      normalizedParts.add(part);
    }

    return normalizedParts.join('/');
  }
}

class _AudioFileToSave {
  const _AudioFileToSave({
    required this.storageKey,
    required this.bytes,
  });

  final String storageKey;
  final Uint8List bytes;
}
