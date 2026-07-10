import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/quiz_deck.dart';
import '../models/quiz_history.dart';
import '../models/quiz_session.dart';
import '../services/quiz_engine.dart';

class QuizSessionState extends ChangeNotifier {
  QuizSessionState({
    required this.deck,
    required List<QuizSessionQuestion> questions,
    QuizEngine? quizEngine,
    Uuid? uuid,
  })  : _questions = questions,
        _quizEngine = quizEngine ?? QuizEngine(),
        _uuid = uuid ?? const Uuid();

  final QuizDeck deck;
  final List<QuizSessionQuestion> _questions;
  final QuizEngine _quizEngine;
  final Uuid _uuid;

  final List<QuestionResult> _results = <QuestionResult>[];

  int _currentIndex = 0;
  int? _selectedIndex;
  String? _textAnswer;
  bool _answered = false;

  List<QuizSessionQuestion> get questions => List.unmodifiable(_questions);

  int get currentIndex => _currentIndex;
  int get totalCount => _questions.length;
  int? get selectedIndex => _selectedIndex;
  String? get textAnswer => _textAnswer;
  bool get answered => _answered;
  bool get hasQuestions => _questions.isNotEmpty;

  bool get isLastQuestion => _currentIndex >= _questions.length - 1;

  int get correctCount => _results.where((result) => result.isCorrect).length;

  int get incorrectCount =>
      _results.where((result) => !result.isCorrect).length;

  int get answeredCount => _results.length;

  List<QuestionResult> get results => List.unmodifiable(_results);

  QuizSessionQuestion get currentQuestion => _questions[_currentIndex];

  List<String> get wrongQuestionIds {
    return _results
        .where((result) => !result.isCorrect)
        .map((result) => result.questionId)
        .toList();
  }

  void answer(int selectedIndex) {
    if (_answered) {
      return;
    }

    final question = currentQuestion;

    if (question.correctIndex == null) {
      return;
    }

    final isCorrect = _quizEngine.isCorrect(question, selectedIndex);

    _selectedIndex = selectedIndex;
    _answered = true;

    _results.add(
      QuestionResult(
        questionId: question.question.id,
        selectedAnswer: selectedIndex,
        correctAnswer: question.correctIndex,
        isCorrect: isCorrect,
        answeredAt: DateTime.now(),
      ),
    );

    notifyListeners();
  }

  void answerText(String enteredAnswer) {
    if (_answered) {
      return;
    }

    final question = currentQuestion;

    if (question.question.answers.isEmpty) {
      return;
    }

    final isCorrect = _quizEngine.isTextCorrect(question, enteredAnswer);

    _textAnswer = enteredAnswer;
    _answered = true;

    _results.add(
      QuestionResult(
        questionId: question.question.id,
        textAnswer: enteredAnswer,
        correctTextAnswer: question.question.answers.first,
        isCorrect: isCorrect,
        answeredAt: DateTime.now(),
      ),
    );

    notifyListeners();
  }

  bool moveNext() {
    if (!isLastQuestion) {
      _currentIndex += 1;
      _selectedIndex = null;
      _textAnswer = null;
      _answered = false;
      notifyListeners();
      return true;
    }

    return false;
  }

  QuizHistory finish({required bool completed}) {
    return QuizHistory(
      id: _uuid.v4(),
      deckId: deck.id,
      playedAt: DateTime.now(),
      totalAnswered: _results.length,
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      completed: completed,
      results: List<QuestionResult>.from(_results),
    );
  }
}
