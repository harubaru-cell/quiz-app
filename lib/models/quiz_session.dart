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
    this.displayChoices = const <String>[],
    this.correctIndex,
  });

  final QuizQuestion question;

  // 4択問題のときだけ使用
  final List<String> displayChoices;
  final int? correctIndex;
}
