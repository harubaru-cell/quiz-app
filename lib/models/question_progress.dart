enum QuestionProgressStatus {
  unanswered,
  correct,
  needsReview,
}

enum QuestionProgressFilter {
  all,
  unanswered,
  incorrect,
  unmastered;

  bool includes(QuestionProgressStatus status) {
    return switch (this) {
      QuestionProgressFilter.all => true,
      QuestionProgressFilter.unanswered =>
        status == QuestionProgressStatus.unanswered,
      QuestionProgressFilter.incorrect =>
        status == QuestionProgressStatus.needsReview,
      QuestionProgressFilter.unmastered =>
        status != QuestionProgressStatus.correct,
    };
  }
}

class QuestionProgress {
  const QuestionProgress({
    required this.deckId,
    required this.questionId,
    required this.answerCount,
    required this.correctCount,
    required this.incorrectCount,
    required this.consecutiveCorrectCount,
    required this.latestIsCorrect,
    required this.lastAnsweredAt,
  });

  factory QuestionProgress.unanswered({
    required String deckId,
    required String questionId,
  }) {
    return QuestionProgress(
      deckId: deckId,
      questionId: questionId,
      answerCount: 0,
      correctCount: 0,
      incorrectCount: 0,
      consecutiveCorrectCount: 0,
      latestIsCorrect: null,
      lastAnsweredAt: null,
    );
  }

  final String deckId;
  final String questionId;
  final int answerCount;
  final int correctCount;
  final int incorrectCount;
  final int consecutiveCorrectCount;
  final bool? latestIsCorrect;
  final DateTime? lastAnsweredAt;

  QuestionProgressStatus get status {
    if (answerCount == 0) {
      return QuestionProgressStatus.unanswered;
    }

    return latestIsCorrect == true
        ? QuestionProgressStatus.correct
        : QuestionProgressStatus.needsReview;
  }

  QuestionProgress recordAnswer({
    required bool isCorrect,
    required DateTime answeredAt,
  }) {
    return QuestionProgress(
      deckId: deckId,
      questionId: questionId,
      answerCount: answerCount + 1,
      correctCount: correctCount + (isCorrect ? 1 : 0),
      incorrectCount: incorrectCount + (isCorrect ? 0 : 1),
      consecutiveCorrectCount: isCorrect ? consecutiveCorrectCount + 1 : 0,
      latestIsCorrect: isCorrect,
      lastAnsweredAt: answeredAt,
    );
  }

  factory QuestionProgress.fromJson(Map<String, dynamic> json) {
    final deckId = json['deckId'];
    final questionId = json['questionId'];
    final latestIsCorrect = json['latestIsCorrect'];
    final lastAnsweredAt = json['lastAnsweredAt'];

    if (deckId is! String || deckId.isEmpty) {
      throw const FormatException('問題別進捗の deckId が不正です。');
    }
    if (questionId is! String || questionId.isEmpty) {
      throw const FormatException('問題別進捗の questionId が不正です。');
    }
    if (latestIsCorrect != null && latestIsCorrect is! bool) {
      throw const FormatException('問題別進捗の latestIsCorrect が不正です。');
    }
    if (lastAnsweredAt != null && lastAnsweredAt is! String) {
      throw const FormatException('問題別進捗の lastAnsweredAt が不正です。');
    }

    final parsedLastAnsweredAt =
        lastAnsweredAt is String ? DateTime.tryParse(lastAnsweredAt) : null;

    if (lastAnsweredAt != null && parsedLastAnsweredAt == null) {
      throw const FormatException('問題別進捗の lastAnsweredAt が不正です。');
    }

    return QuestionProgress(
      deckId: deckId,
      questionId: questionId,
      answerCount: _readCount(json, 'answerCount'),
      correctCount: _readCount(json, 'correctCount'),
      incorrectCount: _readCount(json, 'incorrectCount'),
      consecutiveCorrectCount: _readCount(json, 'consecutiveCorrectCount'),
      latestIsCorrect: latestIsCorrect as bool?,
      lastAnsweredAt: parsedLastAnsweredAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deckId': deckId,
      'questionId': questionId,
      'answerCount': answerCount,
      'correctCount': correctCount,
      'incorrectCount': incorrectCount,
      'consecutiveCorrectCount': consecutiveCorrectCount,
      'latestIsCorrect': latestIsCorrect,
      'lastAnsweredAt': lastAnsweredAt?.toIso8601String(),
    };
  }
}

class QuestionProgressSnapshot {
  const QuestionProgressSnapshot({
    required this.schemaVersion,
    required this.items,
  });

  static const int currentSchemaVersion = 1;

  factory QuestionProgressSnapshot.empty() {
    return const QuestionProgressSnapshot(
      schemaVersion: currentSchemaVersion,
      items: <QuestionProgress>[],
    );
  }

  final int schemaVersion;
  final List<QuestionProgress> items;

  factory QuestionProgressSnapshot.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? currentSchemaVersion;
    final rawItems = json['items'];

    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        '未対応の問題別進捗データです: schemaVersion=$schemaVersion',
      );
    }
    if (rawItems != null && rawItems is! List) {
      throw const FormatException('問題別進捗の items が不正です。');
    }

    final List<QuestionProgress> items = rawItems == null
        ? <QuestionProgress>[]
        : rawItems
            .map<QuestionProgress>(
              (item) => QuestionProgress.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();

    return QuestionProgressSnapshot(
      schemaVersion: schemaVersion,
      items: items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

int _readCount(Map<String, dynamic> json, String key) {
  final value = json[key] as int? ?? 0;

  if (value < 0) {
    throw FormatException('問題別進捗の $key が不正です。');
  }

  return value;
}
