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
}
