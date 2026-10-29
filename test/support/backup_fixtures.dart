import 'dart:convert';
import 'dart:typed_data';

import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/models/quiz_deck.dart';
import 'package:personal_quiz_study/services/backup_service.dart';

/// Synthetic data only. No personal backup files belong in this repository.
BackupSnapshot backupFixture({bool withAudio = false}) {
  final deck = <String, dynamic>{
    'deckId': 'fixture-deck',
    'subject': 'テスト科目',
    'title': '架空の検証デッキ',
    'version': '1.5',
    'createdAt': '2026-01-02T03:04:05.000Z',
    'updatedAt': '2026-02-03T04:05:06.000Z',
    'unknownFutureField': {'keep': true},
    'questions': [
      {
        'id': 'q1',
        'type': 'multiple_choice',
        'question': '1＋1は？',
        'choices': ['2', '3', '4', '5'],
        'answer': 0,
        'explanation': '検証用の解説',
        'difficulty': 'easy',
        'tags': ['単語'],
        if (withAudio) 'audio': 'stored-audio:fixture-deck/audio/q1.mp3'
      },
      {
        'id': 'q2',
        'type': 'text_input',
        'question': '検証用の記述式',
        'answers': ['你好', 'こんにちは'],
        'explanation': '架空の問題',
        'difficulty': 'normal',
        'tags': []
      },
      {
        'id': 'q3',
        'type': 'flashcard',
        'question': '**確認**\n==強調==',
        'answers': ['模範解答\n改行'],
        'explanation': '__補足__',
        'difficulty': 'hard',
        'tags': ['その他']
      },
    ],
  };
  final signature = QuizDeck.fromJson(deck).contentSignature;
  const at = '2026-02-04T05:06:07.000Z';
  final history = {
    'id': 'fixture-history',
    'deckId': 'fixture-deck',
    'playedAt': at,
    'totalAnswered': 3,
    'correctCount': 2,
    'incorrectCount': 1,
    'completed': true,
    'results': [
      {
        'questionId': 'q1',
        'selectedAnswer': 0,
        'correctAnswer': 0,
        'isCorrect': true,
        'answeredAt': at
      },
      {
        'questionId': 'q2',
        'textAnswer': '誤答',
        'correctTextAnswer': '你好',
        'isCorrect': false,
        'answeredAt': at
      },
      {
        'questionId': 'q3',
        'flashcardRating': 'remembered',
        'isCorrect': true,
        'answeredAt': at
      },
    ],
  };
  final progress = {
    'schemaVersion': 1,
    'items': [
      {
        'deckId': 'fixture-deck',
        'questionId': 'q1',
        'answerCount': 1,
        'correctCount': 1,
        'incorrectCount': 0,
        'consecutiveCorrectCount': 1,
        'latestIsCorrect': true,
        'lastAnsweredAt': at
      },
      {
        'deckId': 'fixture-deck',
        'questionId': 'q2',
        'answerCount': 1,
        'correctCount': 0,
        'incorrectCount': 1,
        'consecutiveCorrectCount': 0,
        'latestIsCorrect': false,
        'lastAnsweredAt': at
      },
    ],
  };
  final cycles = {
    'schemaVersion': 1,
    'items': [
      {
        'cycleId': 'fixture-cycle',
        'deckId': 'fixture-deck',
        'deckSignature': signature,
        'orderedQuestionIds': ['q1', 'q2', 'q3'],
        'nextIndex': 1,
        'batchSize': 10,
        'startedAt': at,
        'updatedAt': at,
        'answeredEvents': [
          {'questionId': 'q1', 'isCorrect': true, 'answeredAt': at}
        ]
      },
    ],
  };
  return BackupSnapshot(
      preferences: {
        '${backupPreferencePrefix}decks': jsonEncode(
            '${const JsonEncoder.withIndent('  ').convert([deck])}\r\n'),
        '${backupPreferencePrefix}histories': wrapPreference([history]),
        '${backupPreferencePrefix}deck_stats': wrapPreference([
          {
            'deckId': 'fixture-deck',
            'attemptCount': 1,
            'totalAnswered': 3,
            'totalCorrect': 2,
            'lastPlayedAt': at,
            'incorrectQuestionIds': ['q2']
          },
        ]),
        '${backupPreferencePrefix}question_progress': wrapPreference(progress),
        '${backupPreferencePrefix}study_cycles': wrapPreference(cycles),
      },
      audioDatabaseVersion: withAudio ? 1 : null,
      audio: withAudio
          ? {
              'fixture-deck/audio/q1.mp3': Uint8List.fromList([0, 1, 128, 255])
            }
          : {});
}

String wrapPreference(Object value) => jsonEncode(jsonEncode(value));

BackupSnapshot replacePreference(
        BackupSnapshot snapshot, String suffix, String? raw) =>
    BackupSnapshot(
        preferences: {
          ...snapshot.preferences,
          '$backupPreferencePrefix$suffix': raw
        },
        audio: snapshot.audio,
        audioDatabaseVersion: snapshot.audioDatabaseVersion);

QuizBackup fixtureDocument(BackupSnapshot snapshot) => QuizBackup.create(
      origin: 'https://example.invalid',
      deviceLabel: '架空のテスト端末',
      snapshot: snapshot,
      createdAt: DateTime.utc(2026, 2, 5),
    );

class FixtureBackupSource implements BackupSource {
  FixtureBackupSource(this.snapshot);
  BackupSnapshot snapshot;
  int readCount = 0;
  BackupSnapshot? subsequent;
  Object? failure;

  @override
  String get origin => 'https://example.invalid';

  @override
  Future<BackupSnapshot> read() async {
    readCount++;
    if (failure != null) throw failure!;
    return readCount > 1 ? subsequent ?? snapshot : snapshot;
  }
}
