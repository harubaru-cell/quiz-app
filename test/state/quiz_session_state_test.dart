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
    var shouldFail = true;
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
      recorder: (_) {
        if (shouldFail) {
          return Future<void>.error(StateError('保存失敗'));
        }
        return Future<void>.value();
      },
    );

    await session.answer(1);

    expect(session.isSavingProgress, isFalse);
    expect(session.answered, isFalse);
    expect(session.answeredCount, 0);
    expect(session.saveError, contains('もう一度回答してください'));

    shouldFail = false;
    await session.answer(1);

    expect(session.answered, isTrue);
    expect(session.answeredCount, 1);
    expect(session.saveError, isNull);
  });

  test('同じセッションの履歴IDを固定し結果保存の開始を一度だけ許可する', () {
    const question = QuizQuestion(
      id: 'choice-1',
      type: QuestionType.multipleChoice,
      question: '問題',
      choices: <String>['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
      answer: 1,
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final session = _createSession(
      question,
      recorder: (_) => Future<void>.value(),
    );

    final firstHistory = session.finish(completed: true);
    final secondHistory = session.finish(completed: true);

    expect(firstHistory.id, secondHistory.id);
    expect(session.beginFinalization(), isTrue);
    expect(session.beginFinalization(), isFalse);
    expect(session.isFinalizing, isTrue);

    session.endFinalization();

    expect(session.isFinalizing, isFalse);
  });

  test('flashcardは答えを見るだけでは回答せず、3段階評価を正誤へ変換する', () async {
    const expectations = <FlashcardRating, bool>{
      FlashcardRating.remembered: true,
      FlashcardRating.unsure: false,
      FlashcardRating.forgotten: false,
    };

    for (final entry in expectations.entries) {
      QuestionResult? recordedResult;
      final session = _createSession(
        _flashcard('flashcard-${entry.key.value}'),
        recorder: (result) {
          recordedResult = result;
          return Future<void>.value();
        },
      );

      await session.answerFlashcard(entry.key);

      expect(session.answeredCount, 0);
      expect(session.answered, isFalse);

      session.revealFlashcardAnswer();

      expect(session.flashcardAnswerRevealed, isTrue);
      expect(session.answeredCount, 0);

      await session.answerFlashcard(entry.key);

      expect(session.answeredCount, 1);
      expect(session.flashcardRating, entry.key);
      expect(recordedResult?.flashcardRating, entry.key);
      expect(recordedResult?.isCorrect, entry.value);
    }
  });

  test('flashcardの自己評価を連打しても保存と履歴追加を一度だけ行う', () async {
    final saveCompleter = Completer<void>();
    var saveCount = 0;
    final session = _createSession(
      _flashcard('flashcard-1'),
      recorder: (_) {
        saveCount += 1;
        return saveCompleter.future;
      },
    );

    session.revealFlashcardAnswer();
    final firstAnswer = session.answerFlashcard(FlashcardRating.unsure);
    final secondAnswer = session.answerFlashcard(FlashcardRating.forgotten);

    await secondAnswer;

    expect(saveCount, 1);
    expect(session.answeredCount, 1);
    expect(session.flashcardRating, FlashcardRating.unsure);
    expect(session.isSavingProgress, isTrue);
    expect(session.moveNext(), isFalse);

    saveCompleter.complete();
    await firstAnswer;

    expect(session.isSavingProgress, isFalse);
    expect(session.results.single.flashcardRating, FlashcardRating.unsure);
  });

  test('次のflashcardへ進むと答えと自己評価を非表示状態へ戻す', () async {
    final session = _createSession(
      _flashcard('flashcard-1'),
      additionalQuestions: <QuizQuestion>[
        _flashcard('flashcard-2'),
      ],
      recorder: (_) => Future<void>.value(),
    );

    session.revealFlashcardAnswer();
    await session.answerFlashcard(FlashcardRating.remembered);

    expect(session.moveNext(), isTrue);
    expect(session.currentQuestion.question.id, 'flashcard-2');
    expect(session.flashcardAnswerRevealed, isFalse);
    expect(session.flashcardRating, isNull);
    expect(session.answered, isFalse);
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

QuizQuestion _flashcard(String id) {
  return QuizQuestion(
    id: id,
    type: QuestionType.flashcard,
    question: '$id の事案概要',
    answers: const <String>['模範解答'],
    explanation: '架空事件',
    tags: const <String>['労働法', '判例'],
    difficulty: Difficulty.hard,
  );
}
