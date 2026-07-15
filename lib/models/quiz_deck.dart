import 'dart:convert';

import 'quiz_question.dart';

class QuizDeck {
  const QuizDeck({
    required this.id,
    required this.subject,
    required this.title,
    required this.version,
    required this.questions,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String subject;
  final String title;
  final String version;
  final List<QuizQuestion> questions;
  final DateTime createdAt;
  final DateTime updatedAt;

  Set<String> get duplicateQuestionIds {
    final seen = <String>{};
    final duplicates = <String>{};

    for (final question in questions) {
      if (!seen.add(question.id)) {
        duplicates.add(question.id);
      }
    }

    return Set<String>.unmodifiable(duplicates);
  }

  bool get hasDuplicateQuestionIds => duplicateQuestionIds.isNotEmpty;

  String get contentSignature {
    final bytes = utf8.encode(jsonEncode(toJson()));
    const firstModulus = 1000000007;
    const secondModulus = 1000000009;
    var firstHash = 7;
    var secondHash = 11;

    for (final byte in bytes) {
      firstHash = (firstHash * 257 + byte) % firstModulus;
      secondHash = (secondHash * 263 + byte) % secondModulus;
    }

    return '${bytes.length}:$firstHash:$secondHash';
  }

  factory QuizDeck.fromJson(Map<String, dynamic> json) {
    final questionsJson = json['questions'];
    if (json['subject'] is! String) {
      throw const FormatException('subject は文字列にしてください。');
    }
    if (json['title'] is! String || (json['title'] as String).trim().isEmpty) {
      throw const FormatException('title は空でない文字列にしてください。');
    }
    if (json['version'] is! String) {
      throw const FormatException('version は文字列にしてください。');
    }
    if (questionsJson is! List || questionsJson.isEmpty) {
      throw const FormatException('questions は1件以上の配列にしてください。');
    }

    final now = DateTime.now();
    return QuizDeck(
      id: json['deckId'] as String? ?? '',
      subject: json['subject'] as String,
      title: json['title'] as String,
      version: json['version'] as String,
      questions: questionsJson
          .map((item) =>
              QuizQuestion.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  QuizDeck copyWith({
    String? id,
    List<QuizQuestion>? questions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuizDeck(
      id: id ?? this.id,
      subject: subject,
      title: title,
      version: version,
      questions: questions ?? this.questions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deckId': id,
      'subject': subject,
      'title': title,
      'version': version,
      'questions': questions.map((question) => question.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
