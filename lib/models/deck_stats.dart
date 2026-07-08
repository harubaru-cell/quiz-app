class DeckStats {
  const DeckStats({
    required this.deckId,
    required this.attemptCount,
    required this.totalAnswered,
    required this.totalCorrect,
    required this.lastPlayedAt,
    required this.incorrectQuestionIds,
  });

  final String deckId;
  final int attemptCount;
  final int totalAnswered;
  final int totalCorrect;
  final DateTime? lastPlayedAt;
  final Set<String> incorrectQuestionIds;

  double get accuracy {
    if (totalAnswered == 0) {
      return 0;
    }
    return totalCorrect / totalAnswered;
  }

  factory DeckStats.empty(String deckId) {
    return DeckStats(
      deckId: deckId,
      attemptCount: 0,
      totalAnswered: 0,
      totalCorrect: 0,
      lastPlayedAt: null,
      incorrectQuestionIds: <String>{},
    );
  }

  factory DeckStats.fromJson(Map<String, dynamic> json) {
    return DeckStats(
      deckId: json['deckId'] as String,
      attemptCount: json['attemptCount'] as int? ?? 0,
      totalAnswered: json['totalAnswered'] as int? ?? 0,
      totalCorrect: json['totalCorrect'] as int? ?? 0,
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
      incorrectQuestionIds: ((json['incorrectQuestionIds'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
    );
  }

  DeckStats copyWith({
    int? attemptCount,
    int? totalAnswered,
    int? totalCorrect,
    DateTime? lastPlayedAt,
    Set<String>? incorrectQuestionIds,
  }) {
    return DeckStats(
      deckId: deckId,
      attemptCount: attemptCount ?? this.attemptCount,
      totalAnswered: totalAnswered ?? this.totalAnswered,
      totalCorrect: totalCorrect ?? this.totalCorrect,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      incorrectQuestionIds: incorrectQuestionIds ?? this.incorrectQuestionIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deckId': deckId,
      'attemptCount': attemptCount,
      'totalAnswered': totalAnswered,
      'totalCorrect': totalCorrect,
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      'incorrectQuestionIds': incorrectQuestionIds.toList(),
    };
  }
}
