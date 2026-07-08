class QuizHistory {
  const QuizHistory({
    required this.id,
    required this.deckId,
    required this.playedAt,
    required this.totalAnswered,
    required this.correctCount,
    required this.incorrectCount,
    required this.completed,
    required this.results,
  });

  final String id;
  final String deckId;
  final DateTime playedAt;
  final int totalAnswered;
  final int correctCount;
  final int incorrectCount;
  final bool completed;
  final List<QuestionResult> results;

  factory QuizHistory.fromJson(Map<String, dynamic> json) {
    return QuizHistory(
      id: json['id'] as String,
      deckId: json['deckId'] as String,
      playedAt: DateTime.parse(json['playedAt'] as String),
      totalAnswered: json['totalAnswered'] as int,
      correctCount: json['correctCount'] as int,
      incorrectCount: json['incorrectCount'] as int,
      completed: json['completed'] as bool,
      results: (json['results'] as List)
          .map((item) => QuestionResult.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deckId': deckId,
      'playedAt': playedAt.toIso8601String(),
      'totalAnswered': totalAnswered,
      'correctCount': correctCount,
      'incorrectCount': incorrectCount,
      'completed': completed,
      'results': results.map((result) => result.toJson()).toList(),
    };
  }
}

class QuestionResult {
  const QuestionResult({
    required this.questionId,
    required this.selectedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.answeredAt,
  });

  final String questionId;
  final int selectedAnswer;
  final int correctAnswer;
  final bool isCorrect;
  final DateTime answeredAt;

  factory QuestionResult.fromJson(Map<String, dynamic> json) {
    return QuestionResult(
      questionId: json['questionId'] as String,
      selectedAnswer: json['selectedAnswer'] as int,
      correctAnswer: json['correctAnswer'] as int,
      isCorrect: json['isCorrect'] as bool,
      answeredAt: DateTime.parse(json['answeredAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'questionId': questionId,
      'selectedAnswer': selectedAnswer,
      'correctAnswer': correctAnswer,
      'isCorrect': isCorrect,
      'answeredAt': answeredAt.toIso8601String(),
    };
  }
}
