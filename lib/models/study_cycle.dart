import 'dart:math' as math;

class StudyCycle {
  StudyCycle({
    required this.cycleId,
    required this.deckId,
    required this.deckSignature,
    required List<String> orderedQuestionIds,
    required this.nextIndex,
    required this.batchSize,
    required this.startedAt,
    required this.updatedAt,
    required List<StudyCycleAnswer> answeredEvents,
  })  : orderedQuestionIds = List<String>.unmodifiable(orderedQuestionIds),
        answeredEvents = List<StudyCycleAnswer>.unmodifiable(answeredEvents) {
    _validate();
  }

  factory StudyCycle.start({
    required String cycleId,
    required String deckId,
    required String deckSignature,
    required List<String> orderedQuestionIds,
    required int batchSize,
    required DateTime startedAt,
  }) {
    return StudyCycle(
      cycleId: cycleId,
      deckId: deckId,
      deckSignature: deckSignature,
      orderedQuestionIds: orderedQuestionIds,
      nextIndex: 0,
      batchSize: batchSize,
      startedAt: startedAt,
      updatedAt: startedAt,
      answeredEvents: const <StudyCycleAnswer>[],
    );
  }

  final String cycleId;
  final String deckId;
  final String deckSignature;
  final List<String> orderedQuestionIds;
  final int nextIndex;
  final int batchSize;
  final DateTime startedAt;
  final DateTime updatedAt;
  final List<StudyCycleAnswer> answeredEvents;

  int get completedCount => nextIndex;

  int get remainingCount => orderedQuestionIds.length - nextIndex;

  bool get isComplete => nextIndex >= orderedQuestionIds.length;

  String? get nextQuestionId {
    return isComplete ? null : orderedQuestionIds[nextIndex];
  }

  List<String> get nextBatchQuestionIds {
    if (isComplete) {
      return const <String>[];
    }

    final nextBatchBoundary = ((nextIndex ~/ batchSize) + 1) * batchSize;
    final endIndex = math.min(nextBatchBoundary, orderedQuestionIds.length);

    return List<String>.unmodifiable(
      orderedQuestionIds.sublist(nextIndex, endIndex),
    );
  }

  StudyCycle recordAnswer({
    required String questionId,
    required bool isCorrect,
    required DateTime answeredAt,
  }) {
    if (questionId != nextQuestionId) {
      return this;
    }

    return StudyCycle(
      cycleId: cycleId,
      deckId: deckId,
      deckSignature: deckSignature,
      orderedQuestionIds: orderedQuestionIds,
      nextIndex: nextIndex + 1,
      batchSize: batchSize,
      startedAt: startedAt,
      updatedAt: answeredAt,
      answeredEvents: <StudyCycleAnswer>[
        ...answeredEvents,
        StudyCycleAnswer(
          questionId: questionId,
          isCorrect: isCorrect,
          answeredAt: answeredAt,
        ),
      ],
    );
  }

  factory StudyCycle.fromJson(Map<String, dynamic> json) {
    final cycleId = json['cycleId'];
    final deckId = json['deckId'];
    final deckSignature = json['deckSignature'];
    final rawQuestionIds = json['orderedQuestionIds'];
    final nextIndex = json['nextIndex'];
    final batchSize = json['batchSize'];
    final startedAt = json['startedAt'];
    final updatedAt = json['updatedAt'];
    final rawAnsweredEvents = json['answeredEvents'];

    if (cycleId is! String || cycleId.isEmpty) {
      throw const FormatException('StudyCycle cycleId is invalid.');
    }
    if (deckId is! String || deckId.isEmpty) {
      throw const FormatException('StudyCycle deckId is invalid.');
    }
    if (deckSignature is! String || deckSignature.isEmpty) {
      throw const FormatException('StudyCycle deckSignature is invalid.');
    }
    if (rawQuestionIds is! List ||
        rawQuestionIds.any(
          (questionId) => questionId is! String || questionId.isEmpty,
        )) {
      throw const FormatException(
        'StudyCycle orderedQuestionIds is invalid.',
      );
    }
    if (nextIndex is! int) {
      throw const FormatException('StudyCycle nextIndex is invalid.');
    }
    if (batchSize is! int) {
      throw const FormatException('StudyCycle batchSize is invalid.');
    }
    if (startedAt is! String || updatedAt is! String) {
      throw const FormatException('StudyCycle date is invalid.');
    }
    if (rawAnsweredEvents is! List) {
      throw const FormatException('StudyCycle answeredEvents is invalid.');
    }

    final parsedStartedAt = DateTime.tryParse(startedAt);
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);

    if (parsedStartedAt == null || parsedUpdatedAt == null) {
      throw const FormatException('StudyCycle date is invalid.');
    }

    try {
      return StudyCycle(
        cycleId: cycleId,
        deckId: deckId,
        deckSignature: deckSignature,
        orderedQuestionIds: rawQuestionIds.cast<String>(),
        nextIndex: nextIndex,
        batchSize: batchSize,
        startedAt: parsedStartedAt,
        updatedAt: parsedUpdatedAt,
        answeredEvents: rawAnsweredEvents
            .map<StudyCycleAnswer>(
              (item) => StudyCycleAnswer.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'cycleId': cycleId,
      'deckId': deckId,
      'deckSignature': deckSignature,
      'orderedQuestionIds': orderedQuestionIds,
      'nextIndex': nextIndex,
      'batchSize': batchSize,
      'startedAt': startedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'answeredEvents': answeredEvents.map((event) => event.toJson()).toList(),
    };
  }

  void _validate() {
    if (cycleId.isEmpty) {
      throw ArgumentError.value(cycleId, 'cycleId', 'must not be empty');
    }
    if (deckId.isEmpty) {
      throw ArgumentError.value(deckId, 'deckId', 'must not be empty');
    }
    if (deckSignature.isEmpty) {
      throw ArgumentError.value(
        deckSignature,
        'deckSignature',
        'must not be empty',
      );
    }
    if (orderedQuestionIds.any((questionId) => questionId.isEmpty)) {
      throw ArgumentError.value(
        orderedQuestionIds,
        'orderedQuestionIds',
        'must not contain an empty question ID',
      );
    }
    if (orderedQuestionIds.toSet().length != orderedQuestionIds.length) {
      throw ArgumentError.value(
        orderedQuestionIds,
        'orderedQuestionIds',
        'must not contain duplicate question IDs',
      );
    }
    if (nextIndex < 0 || nextIndex > orderedQuestionIds.length) {
      throw ArgumentError.value(
        nextIndex,
        'nextIndex',
        'must be between 0 and the number of questions',
      );
    }
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }
    if (answeredEvents.length != nextIndex) {
      throw ArgumentError.value(
        answeredEvents,
        'answeredEvents',
        'length must match nextIndex',
      );
    }

    for (var index = 0; index < answeredEvents.length; index++) {
      if (answeredEvents[index].questionId != orderedQuestionIds[index]) {
        throw ArgumentError.value(
          answeredEvents,
          'answeredEvents',
          'must match the answered prefix of orderedQuestionIds',
        );
      }
    }
  }
}

class StudyCycleAnswer {
  StudyCycleAnswer({
    required this.questionId,
    required this.isCorrect,
    required this.answeredAt,
  }) {
    if (questionId.isEmpty) {
      throw ArgumentError.value(
        questionId,
        'questionId',
        'must not be empty',
      );
    }
  }

  final String questionId;
  final bool isCorrect;
  final DateTime answeredAt;

  factory StudyCycleAnswer.fromJson(Map<String, dynamic> json) {
    final questionId = json['questionId'];
    final isCorrect = json['isCorrect'];
    final answeredAt = json['answeredAt'];

    if (questionId is! String || questionId.isEmpty) {
      throw const FormatException('StudyCycleAnswer questionId is invalid.');
    }
    if (isCorrect is! bool) {
      throw const FormatException('StudyCycleAnswer isCorrect is invalid.');
    }
    if (answeredAt is! String) {
      throw const FormatException('StudyCycleAnswer answeredAt is invalid.');
    }

    final parsedAnsweredAt = DateTime.tryParse(answeredAt);

    if (parsedAnsweredAt == null) {
      throw const FormatException('StudyCycleAnswer answeredAt is invalid.');
    }

    return StudyCycleAnswer(
      questionId: questionId,
      isCorrect: isCorrect,
      answeredAt: parsedAnsweredAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'questionId': questionId,
      'isCorrect': isCorrect,
      'answeredAt': answeredAt.toIso8601String(),
    };
  }
}

class StudyCycleSnapshot {
  StudyCycleSnapshot({
    required this.schemaVersion,
    required List<StudyCycle> items,
  }) : items = List<StudyCycle>.unmodifiable(items);

  static const int currentSchemaVersion = 1;

  factory StudyCycleSnapshot.empty() {
    return StudyCycleSnapshot(
      schemaVersion: currentSchemaVersion,
      items: const <StudyCycle>[],
    );
  }

  final int schemaVersion;
  final List<StudyCycle> items;

  factory StudyCycleSnapshot.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? currentSchemaVersion;
    final rawItems = json['items'];

    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        'Unsupported StudyCycle schemaVersion: $schemaVersion',
      );
    }
    if (rawItems != null && rawItems is! List) {
      throw const FormatException('StudyCycle items is invalid.');
    }

    final items = rawItems == null
        ? <StudyCycle>[]
        : rawItems
            .map<StudyCycle>(
              (item) => StudyCycle.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();

    return StudyCycleSnapshot(
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
