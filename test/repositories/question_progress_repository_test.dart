import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:personal_quiz_study/models/question_progress.dart';
import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/repositories/question_progress_repository.dart';
import 'package:personal_quiz_study/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('新しいキーへ保存し、既存履歴キーを変更しない', () async {
    const existingHistories = '[{"id":"existing-history"}]';
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageService.historiesKey: existingHistories,
    });
    final repository = QuestionProgressRepository(StorageService());
    final progress = QuestionProgress.unanswered(
      deckId: 'deck-1',
      questionId: 'question-1',
    ).recordAnswer(
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );
    final snapshot = QuestionProgressSnapshot(
      schemaVersion: QuestionProgressSnapshot.currentSchemaVersion,
      items: <QuestionProgress>[progress],
    );

    await repository.saveProgress(snapshot);

    final loaded = await repository.loadProgress();
    final preferences = await SharedPreferences.getInstance();
    final savedRaw = preferences.getString(StorageService.questionProgressKey);

    expect(loaded, isNotNull);
    expect(
        loaded!.schemaVersion, QuestionProgressSnapshot.currentSchemaVersion);
    expect(loaded.items.single.answerCount, 1);
    expect(loaded.items.single.latestIsCorrect, isTrue);
    expect(
        preferences.getString(StorageService.historiesKey), existingHistories);
    expect(jsonDecode(savedRaw!)['schemaVersion'], 1);
  });

  test('同一履歴IDは最後のスナップショットだけを移行する', () {
    final firstSnapshot = _history(
      id: 'session-1',
      results: <QuestionResult>[
        _result('question-1', false, 9),
      ],
    );
    final latestSnapshot = _history(
      id: 'session-1',
      results: <QuestionResult>[
        _result('question-1', false, 9),
        _result('question-1', true, 10),
      ],
    );
    final nextHistory = _history(
      id: 'session-2',
      results: <QuestionResult>[
        _result('question-1', true, 11),
        _result('question-2', false, 12),
      ],
    );
    final repository = QuestionProgressRepository(StorageService());

    final snapshot = repository.migrateFromHistories(
      <QuizHistory>[nextHistory, firstSnapshot, latestSnapshot],
    );
    final firstProgress = snapshot.items.firstWhere(
      (item) => item.questionId == 'question-1',
    );
    final secondProgress = snapshot.items.firstWhere(
      (item) => item.questionId == 'question-2',
    );

    expect(firstProgress.answerCount, 3);
    expect(firstProgress.correctCount, 2);
    expect(firstProgress.incorrectCount, 1);
    expect(firstProgress.consecutiveCorrectCount, 2);
    expect(firstProgress.status, QuestionProgressStatus.correct);
    expect(firstProgress.lastAnsweredAt, DateTime.utc(2026, 7, 15, 11));
    expect(secondProgress.answerCount, 1);
    expect(secondProgress.status, QuestionProgressStatus.needsReview);
  });
}

QuizHistory _history({
  required String id,
  required List<QuestionResult> results,
}) {
  final correctCount = results.where((result) => result.isCorrect).length;

  return QuizHistory(
    id: id,
    deckId: 'deck-1',
    playedAt: results.last.answeredAt,
    totalAnswered: results.length,
    correctCount: correctCount,
    incorrectCount: results.length - correctCount,
    completed: true,
    results: results,
  );
}

QuestionResult _result(String questionId, bool isCorrect, int hour) {
  return QuestionResult(
    questionId: questionId,
    isCorrect: isCorrect,
    answeredAt: DateTime.utc(2026, 7, 15, hour),
  );
}
