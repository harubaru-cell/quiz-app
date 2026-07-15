import 'package:flutter_test/flutter_test.dart';

import 'package:personal_quiz_study/models/question_progress.dart';

void main() {
  test('未回答から最新回答の状態と連続正解数を更新する', () {
    var progress = QuestionProgress.unanswered(
      deckId: 'deck-1',
      questionId: 'question-1',
    );

    expect(progress.status, QuestionProgressStatus.unanswered);
    expect(progress.answerCount, 0);
    expect(progress.consecutiveCorrectCount, 0);

    progress = progress.recordAnswer(
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );

    expect(progress.status, QuestionProgressStatus.needsReview);
    expect(progress.answerCount, 1);
    expect(progress.correctCount, 0);
    expect(progress.incorrectCount, 1);
    expect(progress.consecutiveCorrectCount, 0);

    progress = progress.recordAnswer(
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 11),
    );
    progress = progress.recordAnswer(
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 12),
    );

    expect(progress.status, QuestionProgressStatus.correct);
    expect(progress.answerCount, 3);
    expect(progress.correctCount, 2);
    expect(progress.incorrectCount, 1);
    expect(progress.consecutiveCorrectCount, 2);

    final restored = QuestionProgress.fromJson(progress.toJson());

    expect(restored.deckId, progress.deckId);
    expect(restored.questionId, progress.questionId);
    expect(restored.status, QuestionProgressStatus.correct);
    expect(restored.answerCount, 3);
    expect(restored.consecutiveCorrectCount, 2);
    expect(restored.lastAnsweredAt, DateTime.utc(2026, 7, 15, 12));
  });

  test('不正解で連続正解数を0に戻す', () {
    var progress = QuestionProgress.unanswered(
      deckId: 'deck-1',
      questionId: 'question-1',
    );

    progress = progress.recordAnswer(
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );
    progress = progress.recordAnswer(
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 11),
    );

    expect(progress.status, QuestionProgressStatus.needsReview);
    expect(progress.consecutiveCorrectCount, 0);
    expect(progress.latestIsCorrect, isFalse);
  });

  test('学習範囲フィルターが3つの進捗状態を正しく分類する', () {
    expect(
      QuestionProgressFilter.unanswered.includes(
        QuestionProgressStatus.unanswered,
      ),
      isTrue,
    );
    expect(
      QuestionProgressFilter.unanswered.includes(
        QuestionProgressStatus.needsReview,
      ),
      isFalse,
    );
    expect(
      QuestionProgressFilter.incorrect.includes(
        QuestionProgressStatus.needsReview,
      ),
      isTrue,
    );
    expect(
      QuestionProgressFilter.incorrect.includes(
        QuestionProgressStatus.unanswered,
      ),
      isFalse,
    );
    expect(
      QuestionProgressFilter.unmastered.includes(
        QuestionProgressStatus.unanswered,
      ),
      isTrue,
    );
    expect(
      QuestionProgressFilter.unmastered.includes(
        QuestionProgressStatus.needsReview,
      ),
      isTrue,
    );
    expect(
      QuestionProgressFilter.unmastered.includes(
        QuestionProgressStatus.correct,
      ),
      isFalse,
    );
  });

  test('回答済みで最新の正誤が欠けたデータは要復習として扱う', () {
    final progress = QuestionProgress(
      deckId: 'deck-1',
      questionId: 'question-1',
      answerCount: 1,
      correctCount: 0,
      incorrectCount: 1,
      consecutiveCorrectCount: 0,
      latestIsCorrect: null,
      lastAnsweredAt: DateTime.utc(2026, 7, 15),
    );

    expect(progress.status, QuestionProgressStatus.needsReview);
    expect(
      QuestionProgressFilter.unanswered.includes(progress.status),
      isFalse,
    );
    expect(
      QuestionProgressFilter.unmastered.includes(progress.status),
      isTrue,
    );
  });
}
