import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:personal_quiz_study/models/quiz_deck.dart';
import 'package:personal_quiz_study/models/quiz_question.dart';
import 'package:personal_quiz_study/models/quiz_session.dart';
import 'package:personal_quiz_study/screens/quiz_screen.dart';
import 'package:personal_quiz_study/state/quiz_session_state.dart';

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

    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('結果を見る'), findsOneWidget);
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

QuizSessionState _createSession(
  QuizQuestion question, {
  QuestionResultRecorder? recorder,
}) {
  final deck = QuizDeck(
    id: 'deck-1',
    subject: 'テスト',
    title: 'テストデッキ',
    version: '1.4',
    questions: <QuizQuestion>[question],
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 15),
  );

  return QuizSessionState(
    deck: deck,
    questions: <QuizSessionQuestion>[
      QuizSessionQuestion(
        question: question,
        displayChoices: List<String>.from(question.choices),
        correctIndex: question.answer,
      ),
    ],
    questionResultRecorder: recorder,
  );
}
