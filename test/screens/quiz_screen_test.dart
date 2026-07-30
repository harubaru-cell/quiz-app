import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:personal_quiz_study/models/quiz_deck.dart';
import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/models/quiz_question.dart';
import 'package:personal_quiz_study/models/quiz_session.dart';
import 'package:personal_quiz_study/screens/quiz_screen.dart';
import 'package:personal_quiz_study/screens/result_screen.dart';
import 'package:personal_quiz_study/state/app_state.dart';
import 'package:personal_quiz_study/state/quiz_session_state.dart';
import 'package:personal_quiz_study/widgets/choice_button.dart';
import 'package:personal_quiz_study/widgets/decorated_study_text.dart';

void main() {
  testWidgets('記述式で空欄回答を不正解として記録し、回答内容を表示する', (tester) async {
    const question = QuizQuestion(
      id: 'text-1',
      type: QuestionType.textInput,
      question: '都の名前を答えてください。',
      answers: <String>['平城京', 'へいじょうきょう'],
      explanation: '710年に平城京が造営されました。',
      tags: <String>[],
      difficulty: Difficulty.easy,
    );
    final session = _createSession(question);

    await tester.pumpWidget(_buildApp(session));

    final answerButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '回答する'),
    );
    expect(answerButton.onPressed, isNotNull);

    await tester.tap(find.text('回答する'));
    await tester.pump();

    expect(session.answeredCount, 1);
    expect(session.incorrectCount, 1);
    expect(session.results.single.textAnswer, '');
    expect(session.results.single.isCorrect, isFalse);
    expect(find.text('不正解'), findsOneWidget);
    expect(find.text('あなたの回答：未入力'), findsOneWidget);
    expect(find.text('正解候補：平城京 / へいじょうきょう'), findsOneWidget);
    expect(find.text('710年に平城京が造営されました。'), findsOneWidget);
  });

  testWidgets('四択問題の回答処理には影響しない', (tester) async {
    const question = QuizQuestion(
      id: 'choice-1',
      type: QuestionType.multipleChoice,
      question: '正しい選択肢を選んでください。',
      choices: <String>['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
      answer: 1,
      explanation: '選択肢2が正解です。',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(question);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('2. 選択肢2'));
    await tester.pump();

    expect(session.answeredCount, 1);
    expect(session.correctCount, 1);
    expect(session.results.single.selectedAnswer, 1);
    expect(session.results.single.isCorrect, isTrue);
    expect(find.text('正解'), findsOneWidget);
    expect(find.text('選択肢2が正解です。'), findsOneWidget);
  });

  testWidgets('問題別進捗の保存中は画面遷移操作を無効にする', (tester) async {
    final saveCompleter = Completer<void>();
    const question = QuizQuestion(
      id: 'choice-1',
      type: QuestionType.multipleChoice,
      question: '正しい選択肢を選んでください。',
      choices: <String>['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
      answer: 1,
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(
      question,
      recorder: (_) => saveCompleter.future,
    );

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('2. 選択肢2'));
    await tester.pump();

    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '進捗を保存中'),
    );
    final finishButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '途中終了'),
    );

    expect(nextButton.onPressed, isNull);
    expect(finishButton.onPressed, isNull);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );

    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('結果を見る'), findsOneWidget);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isTrue,
    );
  });

  testWidgets('回答位置を保存できない場合は再回答できる状態へ戻す', (tester) async {
    const question = QuizQuestion(
      id: 'choice-1',
      type: QuestionType.multipleChoice,
      question: '正しい選択肢を選んでください。',
      choices: <String>['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
      answer: 1,
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(
      question,
      recorder: (_) => Future<void>.error(StateError('保存失敗')),
    );

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('2. 選択肢2'));
    await tester.pumpAndSettle();

    expect(session.isSavingProgress, isFalse);
    expect(session.answered, isFalse);
    expect(session.answeredCount, 0);
    expect(
      find.text('回答を保存できませんでした。もう一度回答してください。'),
      findsOneWidget,
    );
    expect(find.text('結果を見る'), findsNothing);
  });

  testWidgets('結果保存中の連打と戻る操作を防ぎ履歴保存を一度だけ呼ぶ', (tester) async {
    const question = QuizQuestion(
      id: 'choice-1',
      type: QuestionType.multipleChoice,
      question: '正しい選択肢を選んでください。',
      choices: <String>['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
      answer: 1,
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(question);
    final appState = _DelayedHistoryAppState();

    await tester.pumpWidget(_buildAppWithAppState(session, appState));
    await tester.tap(find.text('2. 選択肢2'));
    await tester.pump();

    await tester.tap(find.text('結果を見る'));
    await tester.tap(find.text('結果を見る'));
    await tester.pump();

    expect(appState.recordHistoryCallCount, 1);
    expect(session.isFinalizing, isTrue);
    expect(find.text('結果を保存中'), findsOneWidget);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );

    appState.completeSave();
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsOneWidget);
  });

  testWidgets('flashcardは初期状態で事案と答えを見るだけを表示する', (tester) async {
    const question = QuizQuestion(
      id: 'flashcard-1',
      type: QuestionType.flashcard,
      question: 'XとYの間で架空の労働紛争が生じた。',
      answers: <String>['【論点】\n架空の論点\n\n【結論】\n請求を認める。'],
      explanation: '架空事件・2026年7月30日',
      tags: <String>['労働法', '判例'],
      difficulty: Difficulty.hard,
    );
    final session = _createSession(question);

    await tester.pumpWidget(_buildApp(session));

    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('事案の概要'), findsOneWidget);
    expect(find.text(question.question), findsOneWidget);
    expect(find.byKey(const ValueKey('show-flashcard-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('flashcard-answer-card')), findsNothing);
    expect(
      find.byKey(const ValueKey('flashcard-rating-remembered')),
      findsNothing,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceButton), findsNothing);
    expect(session.answeredCount, 0);
  });

  testWidgets('答えを見ると模範解答と自己評価を表示し、評価までは進まない', (tester) async {
    const modelAnswer = '【論点】\n架空の論点\n\n【判旨】\n架空の判旨';
    final question = _flashcardQuestion(
      'flashcard-1',
      answer: modelAnswer,
    );
    final session = _createSession(question);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('答えを見る'));
    await tester.pump();

    expect(find.text(modelAnswer), findsOneWidget);
    expect(find.text('架空事件・2026年7月30日'), findsOneWidget);
    expect(find.text('覚えた'), findsOneWidget);
    expect(find.text('あやしい'), findsOneWidget);
    expect(find.text('覚えていない'), findsOneWidget);
    expect(session.currentIndex, 0);
    expect(session.answeredCount, 0);
    expect(find.text('次へ'), findsNothing);
    expect(find.text('結果を見る'), findsNothing);
  });

  testWidgets('flashcardの事案・模範解答・解説へ同じ装飾を適用する', (tester) async {
    const summary = '【事案の概要】\nXとYには**職種限定合意**があった。\n'
        'Yは==個別的同意なしに==配転を命じた。';
    const answer = '【判旨】\n**職種限定合意**がある場合、'
        '==個別的同意なしに配転できない==。\n\n'
        '【結論】\n__配転命令権は認められない__。';
    const explanation = '**架空事件**・最二小判令和6年4月26日';
    const question = QuizQuestion(
      id: 'decorated-flashcard',
      type: QuestionType.flashcard,
      question: summary,
      answers: <String>[answer],
      explanation: explanation,
      tags: <String>['労働法', '判例'],
      difficulty: Difficulty.hard,
    );
    final session = _createSession(question);

    await tester.pumpWidget(_buildApp(session));

    final caseText = find.descendant(
      of: find.byKey(const ValueKey('flashcard-case-card')),
      matching: find.byType(DecoratedStudyText),
    );
    expect(caseText, findsOneWidget);
    expect(tester.widget<DecoratedStudyText>(caseText).text, summary);
    expect(
      _renderedTextOf(tester, caseText),
      '【事案の概要】\nXとYには職種限定合意があった。\n'
      'Yは個別的同意なしに配転を命じた。',
    );
    expect(find.byKey(const ValueKey('flashcard-answer-card')), findsNothing);

    await tester.tap(find.text('答えを見る'));
    await tester.pump();

    final answerText = find.descendant(
      of: find.byKey(const ValueKey('flashcard-answer-card')),
      matching: find.byType(DecoratedStudyText),
    );
    final explanationText = find.descendant(
      of: find.byKey(const ValueKey('flashcard-explanation-card')),
      matching: find.byType(DecoratedStudyText),
    );
    expect(answerText, findsOneWidget);
    expect(explanationText, findsOneWidget);
    expect(tester.widget<DecoratedStudyText>(answerText).text, answer);
    expect(
      tester.widget<DecoratedStudyText>(explanationText).text,
      explanation,
    );
    expect(_renderedTextOf(tester, answerText), isNot(contains('==')));
    expect(_renderedTextOf(tester, answerText), isNot(contains('__')));
    expect(_renderedTextOf(tester, explanationText), isNot(contains('**')));

    final rememberedButton = find.text('覚えた');
    await tester.ensureVisible(rememberedButton);
    await tester.pumpAndSettle();
    await tester.tap(rememberedButton);
    await tester.pumpAndSettle();

    expect(session.flashcardRating, FlashcardRating.remembered);
    expect(session.correctCount, 1);
  });

  testWidgets('flashcardの自己評価後に保存し、新しいカードでは答えを隠す', (tester) async {
    final firstQuestion = _flashcardQuestion('flashcard-1');
    final secondQuestion = _flashcardQuestion(
      'flashcard-2',
      summary: '2件目の事案概要',
      answer: '2件目の模範解答',
    );
    final savedResults = <QuestionResult>[];
    final session = _createSession(
      firstQuestion,
      additionalQuestions: <QuizQuestion>[secondQuestion],
      recorder: (result) async {
        savedResults.add(result);
      },
    );

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('答えを見る'));
    await tester.pump();
    await tester.tap(find.text('覚えた'));
    await tester.pumpAndSettle();

    expect(savedResults, hasLength(1));
    expect(savedResults.single.isCorrect, isTrue);
    expect(
      savedResults.single.flashcardRating,
      FlashcardRating.remembered,
    );
    expect(find.text('次へ'), findsOneWidget);

    await tester.tap(find.text('次へ'));
    await tester.pump();

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('2件目の事案概要'), findsOneWidget);
    expect(find.text('2件目の模範解答'), findsNothing);
    expect(find.byKey(const ValueKey('show-flashcard-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('flashcard-answer-card')), findsNothing);
    expect(session.flashcardAnswerRevealed, isFalse);
    expect(session.flashcardRating, isNull);
  });

  testWidgets('四択・記述式・flashcardが混在しても前問の状態を残さない', (tester) async {
    const multipleChoice = QuizQuestion(
      id: 'choice-mixed',
      type: QuestionType.multipleChoice,
      question: '混在デッキの四択問題',
      choices: <String>['正解', 'B', 'C', 'D'],
      answer: 0,
      explanation: '四択の解説',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    const textInput = QuizQuestion(
      id: 'text-mixed',
      type: QuestionType.textInput,
      question: '混在デッキの記述式問題',
      answers: <String>['記述正解'],
      explanation: '記述式の解説',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final flashcard = _flashcardQuestion('flashcard-mixed');
    final session = _createSession(
      multipleChoice,
      additionalQuestions: <QuizQuestion>[textInput, flashcard],
    );

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('1. 正解'));
    await tester.pump();
    await tester.tap(find.text('次へ'));
    await tester.pump();

    expect(find.text('混在デッキの記述式問題'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('四択の解説'), findsNothing);

    await tester.enterText(find.byType(TextField), '記述正解');
    await tester.tap(find.text('回答する'));
    await tester.pump();
    await tester.tap(find.text('次へ'));
    await tester.pump();

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('show-flashcard-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('flashcard-answer-card')), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceButton), findsNothing);
    expect(session.selectedIndex, isNull);
    expect(session.textAnswer, isNull);
  });

  testWidgets('小さい画面でも長い事案と模範解答を最後までスクロールできる', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longSummary = List<String>.generate(
      60,
      (index) => '事案段落${index + 1}：X、Y、A組合に関する架空の事情です。',
    ).join('\n\n');
    final longAnswer = List<String>.generate(
      60,
      (index) => '判旨段落${index + 1}：第${index + 1}条との関係を検討する架空の記述です。',
    ).join('\n\n');
    final session = _createSession(
      _flashcardQuestion(
        'long-flashcard',
        summary: longSummary,
        answer: longAnswer,
      ),
    );

    await tester.pumpWidget(_buildApp(session));

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Scrollable>(find.byType(Scrollable).first).axisDirection,
      AxisDirection.down,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('show-flashcard-answer')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('show-flashcard-answer')));
    await tester.pump();

    expect(find.text(longAnswer), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('flashcard-rating-forgotten')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('flashcard-rating-forgotten')),
      findsOneWidget,
    );
  });

  testWidgets('要復習のflashcardを結果から再挑戦すると答えを隠して開始する', (tester) async {
    final question = _flashcardQuestion(
      'flashcard-retry',
      summary: '【事案の概要】\n**要復習の事案**',
      answer: '【判旨】\n==要復習の模範解答==',
    );
    final session = _createSession(question);
    final appState = _ImmediateHistoryAppState();

    await tester.pumpWidget(_buildAppWithAppState(session, appState));
    await tester.tap(find.text('答えを見る'));
    await tester.pump();

    final unsureButton = find.text('あやしい');
    await tester.ensureVisible(unsureButton);
    await tester.pumpAndSettle();
    await tester.tap(unsureButton);
    await tester.pumpAndSettle();

    final resultButton = find.text('結果を見る');
    expect(resultButton, findsOneWidget);
    await tester.ensureVisible(resultButton);
    await tester.pumpAndSettle();
    await tester.tap(resultButton);
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.text('不正解数'), findsOneWidget);
    expect(find.text('1問'), findsNWidgets(2));

    final ratingLabel = find.text('自己評価：あやしい');
    final resultScrollable = find.descendant(
      of: find.byType(ResultScreen),
      matching: find.byType(Scrollable),
    );
    expect(resultScrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      ratingLabel,
      200,
      scrollable: resultScrollable,
    );
    await tester.pumpAndSettle();
    expect(ratingLabel, findsOneWidget);

    await tester.tap(find.text('間違えた問題だけ挑戦'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始'));
    await tester.pumpAndSettle();

    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('show-flashcard-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('flashcard-answer-card')), findsNothing);

    final retryCaseText = find.descendant(
      of: find.byKey(const ValueKey('flashcard-case-card')),
      matching: find.byType(DecoratedStudyText),
    );
    expect(retryCaseText, findsOneWidget);
    expect(
      _renderedTextOf(tester, retryCaseText),
      '【事案の概要】\n要復習の事案',
    );
  });

  testWidgets('結果画面の事案・模範解答・解説にも同じ装飾を適用する', (tester) async {
    const summary = '【事案の概要】\n**結果画面の事案**';
    const answer = '【判旨】\n==結果画面の模範解答==\n\n'
        '【結論】\n__請求を認める__。';
    const explanation = '**結果画面の架空事件**';
    const question = QuizQuestion(
      id: 'result-decoration',
      type: QuestionType.flashcard,
      question: summary,
      answers: <String>[answer],
      explanation: explanation,
      tags: <String>['労働法', '判例'],
      difficulty: Difficulty.hard,
    );
    final deck = QuizDeck(
      id: 'result-deck',
      subject: '労働法',
      title: '結果画面テスト',
      version: '1.5',
      questions: const <QuizQuestion>[question],
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
    );
    final history = QuizHistory(
      id: 'result-history',
      deckId: deck.id,
      playedAt: DateTime(2026, 7, 30),
      totalAnswered: 1,
      correctCount: 1,
      incorrectCount: 0,
      completed: true,
      results: <QuestionResult>[
        QuestionResult(
          questionId: question.id,
          flashcardRating: FlashcardRating.remembered,
          isCorrect: true,
          answeredAt: DateTime(2026, 7, 30),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          deck: deck,
          history: history,
        ),
      ),
    );

    final ratingLabel = find.text('自己評価：覚えた');
    final resultScrollable = find.descendant(
      of: find.byType(ResultScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      ratingLabel,
      200,
      scrollable: resultScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(ratingLabel);
    await tester.pumpAndSettle();

    final decoratedTexts = tester
        .widgetList<DecoratedStudyText>(
          find.byType(DecoratedStudyText),
        )
        .map((widget) => widget.text)
        .toList();
    expect(
        decoratedTexts,
        containsAll(<String>[
          summary,
          answer,
          explanation,
        ]));

    for (final decoratedText in find.byType(DecoratedStudyText).evaluate()) {
      final renderedText = _renderedTextOf(
        tester,
        find.byWidget(decoratedText.widget),
      );
      expect(renderedText, isNot(contains('**')));
      expect(renderedText, isNot(contains('==')));
      expect(renderedText, isNot(contains('__')));
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _buildApp(QuizSessionState session) {
  return ChangeNotifierProvider<QuizSessionState>.value(
    value: session,
    child: const MaterialApp(
      home: QuizScreen(),
    ),
  );
}

Widget _buildAppWithAppState(
  QuizSessionState session,
  AppState appState,
) {
  return ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: _buildApp(session),
  );
}

QuizSessionState _createSession(
  QuizQuestion question, {
  QuestionResultRecorder? recorder,
  List<QuizQuestion> additionalQuestions = const <QuizQuestion>[],
}) {
  final questions = <QuizQuestion>[question, ...additionalQuestions];
  final deck = QuizDeck(
    id: 'deck-1',
    subject: 'テスト',
    title: 'テストデッキ',
    version: '1.4',
    questions: questions,
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 15),
  );

  return QuizSessionState(
    deck: deck,
    questions: questions
        .map(
          (item) => QuizSessionQuestion(
            question: item,
            displayChoices: List<String>.from(item.choices),
            correctIndex: item.answer,
          ),
        )
        .toList(),
    questionResultRecorder: recorder,
  );
}

QuizQuestion _flashcardQuestion(
  String id, {
  String summary = 'XとYの間で架空の労働紛争が生じた。',
  String answer = '【論点】\n架空の論点\n\n【結論】\n請求を認める。',
}) {
  return QuizQuestion(
    id: id,
    type: QuestionType.flashcard,
    question: summary,
    answers: <String>[answer],
    explanation: '架空事件・2026年7月30日',
    tags: const <String>['労働法', '判例'],
    difficulty: Difficulty.hard,
  );
}

class _DelayedHistoryAppState extends AppState {
  final Completer<void> _saveCompleter = Completer<void>();

  int recordHistoryCallCount = 0;

  @override
  Future<void> recordHistory(QuizHistory history) {
    recordHistoryCallCount += 1;
    return _saveCompleter.future;
  }

  void completeSave() {
    _saveCompleter.complete();
  }
}

class _ImmediateHistoryAppState extends AppState {
  @override
  Future<void> recordHistory(QuizHistory history) async {}
}

String _renderedTextOf(
  WidgetTester tester,
  Finder decoratedText,
) {
  final textWidget = tester.widget<Text>(
    find.descendant(
      of: decoratedText,
      matching: find.byType(Text),
    ),
  );

  return textWidget.textSpan?.toPlainText() ?? textWidget.data ?? '';
}
