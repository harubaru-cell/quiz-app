import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/models/quiz_question.dart';
import 'package:personal_quiz_study/services/json_import_service.dart';

void main() {
  test('flashcardを含むJSONを読み込み、先頭のanswersを模範解答にする', () {
    const caseSummary = '【事案の概要】\nXはY社で勤務していた。\n\n争いが生じた。';
    const modelAnswer = '【論点】\n論点A\n\n【結論】\n請求を認める。';
    final source = jsonEncode(<String, dynamic>{
      'deckId': 'labor-law',
      'subject': '労働法',
      'title': '判例フラッシュカード',
      'version': '1.5',
      'questions': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'labor-case-001',
          'type': 'flashcard',
          'question': caseSummary,
          'answers': <String>[modelAnswer, '表示には使用しない補足回答'],
          'explanation': '架空事件・2026年7月30日',
          'tags': <String>['労働法', '判例'],
          'difficulty': 'hard',
        },
      ],
    });

    final deck = JsonImportService().parseDeck(source);
    final question = deck.questions.single;

    expect(question.type, QuestionType.flashcard);
    expect(question.question, caseSummary);
    expect(question.answers, hasLength(2));
    expect(question.flashcardAnswer, modelAnswer);
    expect(question.explanation, '架空事件・2026年7月30日');
    expect(question.toJson()['answers'], <String>[
      modelAnswer,
      '表示には使用しない補足回答',
    ]);
  });

  test('従来のmultiple_choiceとtext_inputを読み込める', () {
    final multipleChoice = QuizQuestion.fromJson(<String, dynamic>{
      'id': 'choice-1',
      'type': 'multiple_choice',
      'question': '正しいものを選んでください。',
      'choices': <String>['A', 'B', 'C', 'D'],
      'answer': 2,
      'explanation': '解説',
      'tags': <String>[],
      'difficulty': 'normal',
    });
    final textInput = QuizQuestion.fromJson(<String, dynamic>{
      'id': 'text-1',
      'type': 'text_input',
      'question': '用語を答えてください。',
      'answers': <String>['解答', '回答'],
      'explanation': '',
      'tags': <String>[],
      'difficulty': 'easy',
    });

    expect(multipleChoice.type, QuestionType.multipleChoice);
    expect(multipleChoice.answer, 2);
    expect(multipleChoice.choices, <String>['A', 'B', 'C', 'D']);
    expect(textInput.type, QuestionType.textInput);
    expect(textInput.answers, <String>['解答', '回答']);
  });

  test('flashcardの表面が空なら読み込みを拒否する', () {
    expect(
      () => QuizQuestion.fromJson(<String, dynamic>{
        'id': 'flashcard-empty-front',
        'type': 'flashcard',
        'question': '  ',
        'answers': <String>['模範解答'],
        'explanation': '',
        'tags': <String>[],
        'difficulty': 'normal',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('question が空'),
        ),
      ),
    );
  });

  test('flashcardのidが空なら読み込みを拒否する', () {
    expect(
      () => QuizQuestion.fromJson(<String, dynamic>{
        'id': '',
        'type': 'flashcard',
        'question': '事案の概要',
        'answers': <String>['模範解答'],
        'explanation': '',
        'tags': <String>[],
        'difficulty': 'normal',
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('空でない id'),
        ),
      ),
    );
  });

  test('flashcardの模範解答がない、または空なら読み込みを拒否する', () {
    for (final answers in <dynamic>[
      null,
      <String>[],
      <String>['  '],
    ]) {
      expect(
        () => QuizQuestion.fromJson(<String, dynamic>{
          'id': 'flashcard-empty-answer',
          'type': 'flashcard',
          'question': '事案の概要',
          if (answers != null) 'answers': answers,
          'explanation': '',
          'tags': <String>[],
          'difficulty': 'normal',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('空でない模範解答'),
          ),
        ),
      );
    }
  });

  test('旧履歴と自己評価付き履歴の両方を読み込める', () {
    final oldResult = QuestionResult.fromJson(<String, dynamic>{
      'questionId': 'old-question',
      'isCorrect': true,
      'answeredAt': '2026-07-30T10:00:00.000Z',
    });
    final flashcardResult = QuestionResult.fromJson(<String, dynamic>{
      'questionId': 'flashcard-1',
      'flashcardRating': 'unsure',
      'isCorrect': false,
      'answeredAt': '2026-07-30T11:00:00.000Z',
    });

    expect(oldResult.flashcardRating, isNull);
    expect(flashcardResult.flashcardRating, FlashcardRating.unsure);
    expect(flashcardResult.toJson()['flashcardRating'], 'unsure');
  });
}
