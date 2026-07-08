import '../models/quiz_question.dart';
import '../models/quiz_session.dart';

class QuizEngine {
  List<QuizSessionQuestion> buildQuestions({
    required List<QuizQuestion> source,
    required QuestionCountOption countOption,
    required bool shuffle,
    List<String>? onlyQuestionIds,
  }) {
    final allowedIds = onlyQuestionIds?.toSet();
    final candidates = source
        .where((question) => allowedIds == null || allowedIds.contains(question.id))
        .map(
          (question) => QuizSessionQuestion(
            question: question,
            displayChoices: List<String>.from(question.choices),
            correctIndex: question.answer,
          ),
        )
        .toList();

    if (shuffle) {
      candidates.shuffle();
    }

    final limit = countOption.limit;
    if (limit == null || candidates.length <= limit) {
      return candidates;
    }
    return candidates.take(limit).toList();
  }

  bool isCorrect(QuizSessionQuestion question, int selectedIndex) {
    return question.correctIndex == selectedIndex;
  }
}
