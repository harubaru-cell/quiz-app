enum QuestionType {
  multipleChoice('multiple_choice'),
  textInput('text_input');

  const QuestionType(this.value);

  final String value;

  static QuestionType fromJson(String value) {
    return QuestionType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => throw FormatException(
        '未対応の問題形式です: $value',
      ),
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
      orElse: () => throw const FormatException(
        'difficulty は easy / normal / hard のいずれかにしてください。',
      ),
    );
  }
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    this.choices = const <String>[],
    this.answer,
    this.answers = const <String>[],
    required this.explanation,
    required this.tags,
    required this.difficulty,
  });

  final String id;
  final QuestionType type;
  final String question;

  // 4択問題で使用
  final List<String> choices;
  final int? answer;

  // 記述式問題で使用
  final List<String> answers;

  final String explanation;
  final List<String> tags;
  final Difficulty difficulty;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final question = json['question'];

    if (id is! String || id.trim().isEmpty) {
      throw const FormatException(
        '各問題には空でない id が必要です。',
      );
    }

    if (question is! String || question.trim().isEmpty) {
      throw FormatException(
        '問題 $id の question が空です。',
      );
    }

    final type = QuestionType.fromJson(
      json['type'] as String? ?? '',
    );

    final rawTags = json['tags'];

    if (rawTags != null &&
        (rawTags is! List || rawTags.any((tag) => tag is! String))) {
      throw FormatException(
        '問題 $id の tags は文字列の配列にしてください。',
      );
    }

    final tags = rawTags == null ? <String>[] : rawTags.cast<String>();

    List<String> choices = const <String>[];
    int? answer;
    List<String> answers = const <String>[];

    if (type == QuestionType.multipleChoice) {
      final rawChoices = json['choices'];
      final rawAnswer = json['answer'];

      if (rawChoices is! List ||
          rawChoices.length != 4 ||
          rawChoices.any(
            (choice) => choice is! String || choice.trim().isEmpty,
          )) {
        throw FormatException(
          '問題 $id の choices は、空でない文字列を4つ指定してください。',
        );
      }

      if (rawAnswer is! int || rawAnswer < 0 || rawAnswer > 3) {
        throw FormatException(
          '問題 $id の answer は0〜3の整数にしてください。',
        );
      }

      choices = rawChoices.cast<String>();
      answer = rawAnswer;
    }

    if (type == QuestionType.textInput) {
      final rawAnswers = json['answers'];

      if (rawAnswers is! List ||
          rawAnswers.isEmpty ||
          rawAnswers.any(
            (answer) => answer is! String || answer.trim().isEmpty,
          )) {
        throw FormatException(
          '問題 $id の answersには、正解候補を1つ以上指定してください。',
        );
      }

      answers = rawAnswers.cast<String>();
    }

    return QuizQuestion(
      id: id,
      type: type,
      question: question,
      choices: choices,
      answer: answer,
      answers: answers,
      explanation: json['explanation'] as String? ?? '',
      tags: tags,
      difficulty: Difficulty.fromJson(
        json['difficulty'] as String? ?? 'normal',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'type': type.value,
      'question': question,
      'explanation': explanation,
      'tags': tags,
      'difficulty': difficulty.value,
    };

    if (type == QuestionType.multipleChoice) {
      json['choices'] = choices;
      json['answer'] = answer;
    }

    if (type == QuestionType.textInput) {
      json['answers'] = answers;
    }

    return json;
  }
}
