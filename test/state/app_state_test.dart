import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:personal_quiz_study/models/question_progress.dart';
import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/services/storage_service.dart';
import 'package:personal_quiz_study/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('旧履歴を残したまま問題別進捗を初回生成する', () async {
    final history = QuizHistory(
      id: 'history-1',
      deckId: 'deck-1',
      playedAt: DateTime.utc(2026, 7, 15, 10),
      totalAnswered: 1,
      correctCount: 0,
      incorrectCount: 1,
      completed: true,
      results: <QuestionResult>[
        QuestionResult(
          questionId: 'question-1',
          isCorrect: false,
          answeredAt: DateTime.utc(2026, 7, 15, 10),
        ),
      ],
    );
    final historiesRaw = jsonEncode(<Map<String, dynamic>>[
      history.toJson(),
    ]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageService.historiesKey: historiesRaw,
    });
    final appState = AppState();

    await appState.load();

    final progress = appState.questionProgressFor('deck-1', 'question-1');
    final unanswered = appState.questionProgressFor('deck-1', 'question-2');
    final preferences = await SharedPreferences.getInstance();

    expect(appState.message, isNull);
    expect(progress.answerCount, 1);
    expect(progress.status, QuestionProgressStatus.needsReview);
    expect(unanswered.status, QuestionProgressStatus.unanswered);
    expect(preferences.getString(StorageService.historiesKey), historiesRaw);
    expect(
      preferences.getString(StorageService.questionProgressKey),
      isNotNull,
    );
  });

  test('回答直後に進捗だけを保存し、履歴と集計を二重加算しない', () async {
    final appState = AppState();
    final result = QuestionResult(
      questionId: 'question-1',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );

    await appState.load();
    await appState.recordQuestionResult('deck-1', result);

    final preferences = await SharedPreferences.getInstance();
    final savedProgressRaw = preferences.getString(
      StorageService.questionProgressKey,
    );

    expect(savedProgressRaw, isNotNull);
    expect(appState.questionProgressFor('deck-1', 'question-1').answerCount, 1);
    expect(appState.statsFor('deck-1').attemptCount, 0);
    expect(appState.statsFor('deck-1').totalAnswered, 0);
    expect(preferences.getString(StorageService.historiesKey), isNull);

    final reloadedAppState = AppState();
    await reloadedAppState.load();

    expect(
      reloadedAppState.questionProgressFor('deck-1', 'question-1').answerCount,
      1,
    );

    final history = QuizHistory(
      id: 'history-1',
      deckId: 'deck-1',
      playedAt: DateTime.utc(2026, 7, 15, 10),
      totalAnswered: 1,
      correctCount: 0,
      incorrectCount: 1,
      completed: true,
      results: <QuestionResult>[result],
    );

    await appState.recordHistory(history);

    expect(appState.statsFor('deck-1').attemptCount, 1);
    expect(appState.statsFor('deck-1').totalAnswered, 1);
    expect(appState.questionProgressFor('deck-1', 'question-1').answerCount, 1);
    expect(
      (jsonDecode(preferences.getString(StorageService.historiesKey)!) as List)
          .length,
      1,
    );
  });

  test('問題別進捗の保存に失敗しても呼び出しを完了する', () async {
    final storageService = _FailingStorageService();
    final appState = AppState(storageService: storageService);
    final result = QuestionResult(
      questionId: 'question-1',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );

    await appState.load();
    storageService.failQuestionProgressWrites = true;

    await appState.recordQuestionResult('deck-1', result);

    expect(appState.message, contains('問題別進捗の保存に失敗しました'));
    expect(appState.questionProgressFor('deck-1', 'question-1').answerCount, 1);
  });
}

class _FailingStorageService extends StorageService {
  bool failQuestionProgressWrites = false;

  @override
  Future<void> writeString(String key, String value) {
    if (failQuestionProgressWrites &&
        key == StorageService.questionProgressKey) {
      return Future<void>.error(StateError('保存失敗'));
    }

    return super.writeString(key, value);
  }
}
