import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:personal_quiz_study/models/question_progress.dart';
import 'package:personal_quiz_study/models/quiz_deck.dart';
import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/models/quiz_question.dart';
import 'package:personal_quiz_study/screens/deck_settings_screen.dart';
import 'package:personal_quiz_study/screens/quiz_screen.dart';
import 'package:personal_quiz_study/state/app_state.dart';
import 'package:personal_quiz_study/state/quiz_session_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('未回答・間違い・未習得で絞り込み、対象問題だけを開始する', (tester) async {
    final deck = _createDeck(<QuizQuestion>[
      _question('question-1'),
      _question('question-2'),
      _question('question-3'),
    ]);
    final appState = await _createAppStateWithProgress();

    await tester.pumpWidget(_buildApp(appState, deck));

    expect(find.text('テスト / 対象3問'), findsOneWidget);

    await _selectProgressFilter(tester, '未回答');
    expect(find.text('テスト / 対象1問'), findsOneWidget);

    await _selectProgressFilter(tester, '間違えた問題');
    expect(find.text('テスト / 対象1問'), findsOneWidget);

    await _selectProgressFilter(tester, '未習得');
    expect(find.text('テスト / 対象2問'), findsOneWidget);

    await tester.tap(find.text('開始'));
    await tester.pumpAndSettle();

    expect(find.byType(QuizScreen), findsOneWidget);

    final quizContext = tester.element(find.byType(QuizScreen));
    final session = Provider.of<QuizSessionState>(
      quizContext,
      listen: false,
    );
    final questionIds =
        session.questions.map((item) => item.question.id).toSet();

    expect(questionIds, <String>{'question-1', 'question-3'});
  });

  testWidgets('問題IDが重複する場合は進捗絞り込みだけを無効化する', (tester) async {
    final duplicatedQuestion = _question('question-1');
    final deck = _createDeck(<QuizQuestion>[
      duplicatedQuestion,
      duplicatedQuestion,
    ]);
    final appState = await _createAppStateWithProgress();

    await tester.pumpWidget(_buildApp(appState, deck));

    final dropdown =
        tester.widget<DropdownButtonFormField<QuestionProgressFilter>>(
      find.byKey(const ValueKey('question-progress-filter')),
    );

    expect(dropdown.onChanged, isNull);
    expect(
      find.textContaining('問題IDが重複しているため'),
      findsOneWidget,
    );

    await tester.tap(find.text('開始'));
    await tester.pumpAndSettle();

    expect(find.byType(QuizScreen), findsOneWidget);
  });

  testWidgets('結果画面から渡された問題IDだけの再挑戦を維持する', (tester) async {
    final deck = _createDeck(<QuizQuestion>[
      _question('question-1'),
      _question('question-2'),
      _question('question-3'),
    ]);
    final appState = await _createAppStateWithProgress();

    await tester.pumpWidget(
      _buildApp(
        appState,
        deck,
        onlyQuestionIds: const <String>['question-2'],
      ),
    );

    expect(find.text('間違えた問題だけ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('question-progress-filter')),
      findsNothing,
    );
    expect(find.text('テスト / 対象1問'), findsOneWidget);

    await tester.tap(find.text('開始'));
    await tester.pumpAndSettle();

    final quizContext = tester.element(find.byType(QuizScreen));
    final session = Provider.of<QuizSessionState>(
      quizContext,
      listen: false,
    );

    expect(session.questions.single.question.id, 'question-2');
  });
}

Future<AppState> _createAppStateWithProgress() async {
  final appState = AppState();

  await appState.load();
  await appState.recordQuestionResult(
    'deck-1',
    QuestionResult(
      questionId: 'question-2',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    ),
  );
  await appState.recordQuestionResult(
    'deck-1',
    QuestionResult(
      questionId: 'question-3',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 11),
    ),
  );

  return appState;
}

Widget _buildApp(
  AppState appState,
  QuizDeck deck, {
  List<String>? onlyQuestionIds,
}) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      home: DeckSettingsScreen(
        deck: deck,
        onlyQuestionIds: onlyQuestionIds,
        initialShuffle: false,
      ),
    ),
  );
}

Future<void> _selectProgressFilter(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(
    find.byKey(const ValueKey('question-progress-filter')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

QuizDeck _createDeck(List<QuizQuestion> questions) {
  return QuizDeck(
    id: 'deck-1',
    subject: 'テスト',
    title: 'テストデッキ',
    version: '1.4',
    questions: questions,
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15),
  );
}

QuizQuestion _question(String id) {
  return QuizQuestion(
    id: id,
    type: QuestionType.textInput,
    question: '$id の問題',
    answers: const <String>['正解'],
    explanation: '',
    tags: const <String>[],
    difficulty: Difficulty.normal,
  );
}
