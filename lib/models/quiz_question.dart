enum QuestionType {
  multipleChoice('multiple_choice');

  const QuestionType(this.value);
  final String value;

  static QuestionType fromJson(String value) {
    return QuestionType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => throw FormatException('未対応の問題形式です: $value'),
    );
  }
}

enum Difficulty {
  easy('easy'),
  normal('normal'),
  hard('hard');

  const Difficulty(this.value);
  final String value;

  static Difficulty fromJson(String value) {
    return Difficulty.values.firstWhere(
      (difficulty) => difficulty.value == value,
      orElse: () => throw FormatException('difficulty は easy / normal / hard のいずれかにしてください。'),
    );
  }
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    required this.choices,
    required this.answer,
    required this.explanation,
    required this.tags,
    required this.difficulty,
  });

  final String id;
  final QuestionType type;
  final String question;
  final List<String> choices;
  final int answer;
  final String explanation;
  final List<String> tags;
  final Difficulty difficulty;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final choices = (json['choices'] as List?)?.cast<String>();
    final answer = json['answer'];
    final tags = (json['tags'] as List?)?.cast<String>() ?? <String>[];

    if (json['id'] is! String || (json['id'] as String).trim().isEmpty) {
      throw const FormatException('各問題には空でない id が必要です。');
    }
    if (json['question'] is! String || (json['question'] as String).trim().isEmpty) {
      throw FormatException('問題 ${json['id']} の question が空です。');
    }
    if (choices == null || choices.length != 4) {
      throw FormatException('問題 ${json['id']} の choices は必ず4つにしてください。');
    }
    if (answer is! int || answer < 0 || answer > 3) {
      throw FormatException('問題 ${json['id']} の answer は0〜3の整数にしてください。');
    }

    return QuizQuestion(
      id: json['id'] as String,
      type: QuestionType.fromJson(json['type'] as String? ?? ''),
      question: json['question'] as String,
      choices: choices,
      answer: answer,
      explanation: json['explanation'] as String? ?? '',
      tags: tags,
      difficulty: Difficulty.fromJson(json['difficulty'] as String? ?? 'normal'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.value,
      'question': question,
      'choices': choices,
      'answer': answer,
      'explanation': explanation,
      'tags': tags,
      'difficulty': difficulty.value,
    };
  }
}
