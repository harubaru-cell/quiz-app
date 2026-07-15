import 'package:flutter_test/flutter_test.dart';

import 'package:personal_quiz_study/models/quiz_deck.dart';
import 'package:personal_quiz_study/models/quiz_question.dart';

void main() {
  test('同一デッキ内の重複問題IDを検出する', () {
    const firstQuestion = QuizQuestion(
      id: 'question-1',
      type: QuestionType.textInput,
      question: '問題1',
      answers: <String>['正解1'],
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    const secondQuestion = QuizQuestion(
      id: 'question-2',
      type: QuestionType.textInput,
      question: '問題2',
      answers: <String>['正解2'],
      explanation: '',
      tags: <String>[],
      difficulty: Difficulty.normal,
    );
    final deck = QuizDeck(
      id: 'deck-1',
      subject: 'テスト',
      title: 'テストデッキ',
      version: '1.4',
      questions: <QuizQuestion>[
        firstQuestion,
        secondQuestion,
        firstQuestion,
      ],
      createdAt: DateTime.utc(2026, 7, 15),
      updatedAt: DateTime.utc(2026, 7, 15),
    );

    expect(deck.hasDuplicateQuestionIds, isTrue);
    expect(deck.duplicateQuestionIds, <String>{'question-1'});
  });
}
