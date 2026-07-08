import 'quiz_question.dart';

enum QuestionCountOption {
  ten(10, '10問'),
  twenty(20, '20問'),
  fifty(50, '50問'),
  all(null, '全問');

  const QuestionCountOption(this.limit, this.label);
  final int? limit;
  final String label;
}

class QuizSessionQuestion {
  const QuizSessionQuestion({
    required this.question,
    required this.displayChoices,
    required this.correctIndex,
  });

  final QuizQuestion question;
  final List<String> displayChoices;
  final int correctIndex;
}
