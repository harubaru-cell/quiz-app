import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_quiz_study/models/quiz_deck.dart';
import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/models/quiz_question.dart';
import 'package:personal_quiz_study/models/quiz_session.dart';
import 'package:personal_quiz_study/state/quiz_session_state.dart';

void main() {
  test('四択の回答結果を1回だけ保存し、完了まで保存中にする', () async {
    final saveCompleter = Completer<void>();
    QuestionResult? recordedResult;
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
    const secondQuestion = QuizQuestion(
      id: 'choice-2',
      type: QuestionType.multipleChoice,
      question: '2問目です。',
      choices: <String>['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
      answer: 0,
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(
      question,
      additionalQuestions: <QuizQuestion>[secondQuestion],
      recorder: (result) {
        recordedResult = result;
        return saveCompleter.future;
      },
    );

    final answerFuture = session.answer(1);

    expect(session.answered, isTrue);
    expect(session.isSavingProgress, isTrue);
    expect(session.answeredCount, 1);
    expect(recordedResult?.questionId, 'choice-1');
    expect(recordedResult?.isCorrect, isTrue);

    await session.answer(0);

    expect(session.answeredCount, 1);
    expect(session.moveNext(), isFalse);
    expect(session.currentIndex, 0);

    saveCompleter.complete();
    await answerFuture;

    expect(session.isSavingProgress, isFalse);
    expect(session.moveNext(), isTrue);
    expect(session.currentIndex, 1);
  });

  test('記述式の空欄回答も保存コールバックへ渡す', () async {
    QuestionResult? recordedResult;
    const question = QuizQuestion(
      id: 'text-1',
      type: QuestionType.textInput,
      question: '答えてください。',
      answers: <String>['正解'],
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(
      question,
      recorder: (result) {
        recordedResult = result;
        return Future<void>.value();
      },
    );

    await session.answerText('');

    expect(recordedResult?.textAnswer, '');
    expect(recordedResult?.isCorrect, isFalse);
    expect(session.answeredCount, 1);
    expect(session.incorrectCount, 1);
  });

  test('保存コールバックが失敗しても保存中状態を解除する', () async {
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

    await expectLater(
      session.answer(1),
      throwsA(isA<StateError>()),
    );

    expect(session.isSavingProgress, isFalse);
    expect(session.answered, isTrue);
    expect(session.answeredCount, 1);
  });
}

QuizSessionState _createSession(
  QuizQuestion question, {
  required QuestionResultRecorder recorder,
  List<QuizQuestion> additionalQuestions = const <QuizQuestion>[],
}) {
  final questions = <QuizQuestion>[question, ...additionalQuestions];
  final deck = QuizDeck(
    id: 'deck-1',
    subject: 'テスト',
    title: 'テストデッキ',
    version: '1.4',
    questions: questions,
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15),
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
