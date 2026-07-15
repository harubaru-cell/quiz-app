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

    await tester.tap(find.text('一周学習を開始'));
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
    expect(
      appState.studyCycleFor(deck.id)!.orderedQuestionIds.toSet(),
      <String>{'question-1', 'question-3'},
    );
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
    expect(appState.studyCycleFor(deck.id), isNull);
  });

  testWidgets('結果画面から渡された問題IDだけの再挑戦を維持する', (tester) async {
    final deck = _createDeck(<QuizQuestion>[
      _question('question-1'),
      _question('question-2'),
      _question('question-3'),
    ]);
    final appState = await _createAppStateWithProgress();
    final activeCycle = await appState.startStudyCycle(
      deckId: deck.id,
      deckSignature: deck.contentSignature,
      orderedQuestionIds:
          deck.questions.map((question) => question.id).toList(),
      batchSize: 10,
    );

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

    await session.answerText('正解');

    expect(activeCycle, isNotNull);
    expect(appState.studyCycleFor(deck.id)!.completedCount, 0);
  });

  testWidgets('一周学習を開始すると固定順の最初の10問だけを出題する', (tester) async {
    final deck = _createDeck(
      List<QuizQuestion>.generate(
        23,
        (index) => _question('question-${index + 1}'),
      ),
    );
    final appState = AppState();
    await appState.load();

    await tester.pumpWidget(_buildApp(appState, deck));
    await tester.tap(find.text('一周学習を開始'));
    await tester.pumpAndSettle();

    final quizContext = tester.element(find.byType(QuizScreen));
    final session = Provider.of<QuizSessionState>(
      quizContext,
      listen: false,
    );
    final questionIds = session.questions
        .map((item) => item.question.id)
        .toList(growable: false);
    final cycle = appState.studyCycleFor('deck-1');

    expect(
      questionIds,
      List<String>.generate(10, (index) => 'question-${index + 1}'),
    );
    expect(cycle, isNotNull);
    expect(cycle!.orderedQuestionIds.length, 23);
    expect(cycle.completedCount, 0);
  });

  testWidgets('4問回答後は同じ10問区切りの残り6問から再開する', (tester) async {
    final deck = _createDeck(
      List<QuizQuestion>.generate(
        12,
        (index) => _question('question-${index + 1}'),
      ),
    );
    final appState = AppState();
    await appState.load();
    final cycle = await appState.startStudyCycle(
      deckId: deck.id,
      deckSignature: deck.contentSignature,
      orderedQuestionIds:
          deck.questions.map((question) => question.id).toList(),
      batchSize: 10,
    );

    for (var index = 0; index < 4; index++) {
      await appState.recordStudyCycleQuestionResult(
        deckId: deck.id,
        cycleId: cycle!.cycleId,
        result: QuestionResult(
          questionId: 'question-${index + 1}',
          isCorrect: true,
          answeredAt: DateTime.utc(2026, 7, 15, 10, index),
        ),
      );
    }

    await tester.pumpWidget(_buildApp(appState, deck));

    expect(find.text('4 / 12問 完了'), findsOneWidget);
    expect(find.text('続きから学習（6問）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('continue-study-cycle')));
    await tester.pumpAndSettle();

    final quizContext = tester.element(find.byType(QuizScreen));
    final session = Provider.of<QuizSessionState>(
      quizContext,
      listen: false,
    );

    expect(
      session.questions.map((item) => item.question.id),
      List<String>.generate(6, (index) => 'question-${index + 5}'),
    );

    await session.answerText('正解');

    expect(appState.studyCycleFor(deck.id)!.completedCount, 5);
  });

  testWidgets('全問題への回答後は一周完了を保持して自動で先頭へ戻らない', (tester) async {
    final deck = _createDeck(<QuizQuestion>[
      _question('question-1'),
      _question('question-2'),
    ]);
    final appState = AppState();
    await appState.load();
    final cycle = await appState.startStudyCycle(
      deckId: deck.id,
      deckSignature: deck.contentSignature,
      orderedQuestionIds:
          deck.questions.map((question) => question.id).toList(),
      batchSize: 10,
    );

    for (var index = 0; index < 2; index++) {
      await appState.recordStudyCycleQuestionResult(
        deckId: deck.id,
        cycleId: cycle!.cycleId,
        result: QuestionResult(
          questionId: 'question-${index + 1}',
          isCorrect: true,
          answeredAt: DateTime.utc(2026, 7, 15, 10, index),
        ),
      );
    }

    await tester.pumpWidget(_buildApp(appState, deck));

    expect(find.text('一周完了'), findsOneWidget);
    expect(find.text('2 / 2問 完了'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('continue-study-cycle')),
      findsNothing,
    );
    expect(find.text('新しい一周を開始'), findsOneWidget);
  });

  testWidgets('同じ問題IDでもデッキ内容が変わった一周は再開させない', (tester) async {
    final originalDeck = _createDeck(<QuizQuestion>[
      _question('question-1', questionText: '変更前の問題文'),
    ]);
    final updatedDeck = _createDeck(<QuizQuestion>[
      _question('question-1', questionText: '変更後の問題文'),
    ]);
    final appState = AppState();
    await appState.load();
    await appState.startStudyCycle(
      deckId: originalDeck.id,
      deckSignature: originalDeck.contentSignature,
      orderedQuestionIds: const <String>['question-1'],
      batchSize: 10,
    );

    await tester.pumpWidget(_buildApp(appState, updatedDeck));

    expect(
      find.textContaining('デッキ内容が変更されているため'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('continue-study-cycle')),
      findsNothing,
    );
  });

  testWidgets('新しい一周の確認をキャンセルすると現在位置を維持する', (tester) async {
    final deck = _createDeck(<QuizQuestion>[
      _question('question-1'),
      _question('question-2'),
    ]);
    final appState = AppState();
    await appState.load();
    final activeCycle = await appState.startStudyCycle(
      deckId: deck.id,
      deckSignature: deck.contentSignature,
      orderedQuestionIds:
          deck.questions.map((question) => question.id).toList(),
      batchSize: 10,
    );

    await tester.pumpWidget(_buildApp(appState, deck));
    await tester.tap(find.text('新しい一周を開始'));
    await tester.pumpAndSettle();

    expect(find.text('新しい一周を始めますか？'), findsOneWidget);

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    final currentCycle = appState.studyCycleFor(deck.id);
    expect(currentCycle!.cycleId, activeCycle!.cycleId);
    expect(currentCycle.completedCount, 0);
    expect(find.text('一周学習の続き'), findsOneWidget);
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

QuizQuestion _question(
  String id, {
  String? questionText,
}) {
  return QuizQuestion(
    id: id,
    type: QuestionType.textInput,
    question: questionText ?? '$id の問題',
    answers: const <String>['正解'],
    explanation: '',
    tags: const <String>[],
    difficulty: Difficulty.normal,
  );
}
