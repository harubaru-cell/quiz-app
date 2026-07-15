import 'package:flutter_test/flutter_test.dart';

import 'package:personal_quiz_study/models/study_cycle.dart';

void main() {
  test('returns the rest of the current fixed-size batch', () {
    var cycle = StudyCycle.start(
      cycleId: 'cycle-1',
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds:
          List<String>.generate(23, (index) => 'q-${index + 1}'),
      batchSize: 10,
      startedAt: DateTime.utc(2026, 7, 15, 10),
    );

    for (var index = 0; index < 4; index++) {
      cycle = cycle.recordAnswer(
        questionId: 'q-${index + 1}',
        isCorrect: index.isEven,
        answeredAt: DateTime.utc(2026, 7, 15, 10, index + 1),
      );
    }

    expect(cycle.completedCount, 4);
    expect(cycle.remainingCount, 19);
    expect(cycle.nextQuestionId, 'q-5');
    expect(
      cycle.nextBatchQuestionIds,
      <String>['q-5', 'q-6', 'q-7', 'q-8', 'q-9', 'q-10'],
    );

    for (var index = 4; index < 10; index++) {
      cycle = cycle.recordAnswer(
        questionId: 'q-${index + 1}',
        isCorrect: index.isEven,
        answeredAt: DateTime.utc(2026, 7, 15, 11, index),
      );
    }

    expect(cycle.nextQuestionId, 'q-11');
    expect(
      cycle.nextBatchQuestionIds,
      List<String>.generate(10, (index) => 'q-${index + 11}'),
    );
  });

  test('only the expected question advances the cycle and completion remains',
      () {
    final startedAt = DateTime.utc(2026, 7, 15, 10);
    final cycle = StudyCycle.start(
      cycleId: 'cycle-1',
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['q-1', 'q-2'],
      batchSize: 10,
      startedAt: startedAt,
    );

    final unchanged = cycle.recordAnswer(
      questionId: 'q-2',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 11),
    );
    final firstAnswered = unchanged.recordAnswer(
      questionId: 'q-1',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 12),
    );
    final completed = firstAnswered.recordAnswer(
      questionId: 'q-2',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 13),
    );
    final afterCompletion = completed.recordAnswer(
      questionId: 'q-2',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 14),
    );

    expect(identical(unchanged, cycle), isTrue);
    expect(completed.isComplete, isTrue);
    expect(completed.completedCount, 2);
    expect(completed.remainingCount, 0);
    expect(completed.nextQuestionId, isNull);
    expect(completed.nextBatchQuestionIds, isEmpty);
    expect(completed.answeredEvents.length, 2);
    expect(completed.answeredEvents.first.isCorrect, isTrue);
    expect(completed.answeredEvents.last.isCorrect, isFalse);
    expect(identical(afterCompletion, completed), isTrue);
  });

  test('rejects duplicate question IDs', () {
    expect(
      () => StudyCycle.start(
        cycleId: 'cycle-1',
        deckId: 'deck-1',
        deckSignature: 'signature-1',
        orderedQuestionIds: const <String>['q-1', 'q-1'],
        batchSize: 10,
        startedAt: DateTime.utc(2026, 7, 15),
      ),
      throwsArgumentError,
    );
  });

  test('rejects answer events that do not match the completed prefix', () {
    final startedAt = DateTime.utc(2026, 7, 15, 10);

    expect(
      () => StudyCycle(
        cycleId: 'cycle-1',
        deckId: 'deck-1',
        deckSignature: 'signature-1',
        orderedQuestionIds: const <String>['q-1', 'q-2'],
        nextIndex: 1,
        batchSize: 10,
        startedAt: startedAt,
        updatedAt: startedAt,
        answeredEvents: const <StudyCycleAnswer>[],
      ),
      throwsArgumentError,
    );

    expect(
      () => StudyCycle(
        cycleId: 'cycle-1',
        deckId: 'deck-1',
        deckSignature: 'signature-1',
        orderedQuestionIds: const <String>['q-1', 'q-2'],
        nextIndex: 1,
        batchSize: 10,
        startedAt: startedAt,
        updatedAt: startedAt,
        answeredEvents: <StudyCycleAnswer>[
          StudyCycleAnswer(
            questionId: 'q-2',
            isCorrect: false,
            answeredAt: startedAt,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('snapshot JSON round-trip preserves an ordered completed state', () {
    var cycle = StudyCycle.start(
      cycleId: 'cycle-1',
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['q-2', 'q-1'],
      batchSize: 1,
      startedAt: DateTime.utc(2026, 7, 15, 10),
    );
    cycle = cycle.recordAnswer(
      questionId: 'q-2',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 11),
    );
    cycle = cycle.recordAnswer(
      questionId: 'q-1',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 12),
    );
    final snapshot = StudyCycleSnapshot(
      schemaVersion: StudyCycleSnapshot.currentSchemaVersion,
      items: <StudyCycle>[cycle],
    );

    final restored = StudyCycleSnapshot.fromJson(snapshot.toJson());
    final restoredCycle = restored.items.single;

    expect(restored.schemaVersion, 1);
    expect(restoredCycle.orderedQuestionIds, <String>['q-2', 'q-1']);
    expect(restoredCycle.deckSignature, 'signature-1');
    expect(restoredCycle.completedCount, 2);
    expect(restoredCycle.isComplete, isTrue);
    expect(restoredCycle.updatedAt, DateTime.utc(2026, 7, 15, 12));
    expect(restoredCycle.answeredEvents.length, 2);
    expect(restoredCycle.answeredEvents.first.questionId, 'q-2');
    expect(restoredCycle.answeredEvents.first.isCorrect, isFalse);
    expect(
      restoredCycle.answeredEvents.first.answeredAt,
      DateTime.utc(2026, 7, 15, 11),
    );
    expect(restoredCycle.answeredEvents.last.questionId, 'q-1');
    expect(restoredCycle.answeredEvents.last.isCorrect, isTrue);
  });

  test('23 questions are served as 10, 10, and 3 without duplication', () {
    var cycle = StudyCycle.start(
      cycleId: 'cycle-1',
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds:
          List<String>.generate(23, (index) => 'q-${index + 1}'),
      batchSize: 10,
      startedAt: DateTime.utc(2026, 7, 15, 10),
    );
    final batches = <List<String>>[];

    while (!cycle.isComplete) {
      final batch = cycle.nextBatchQuestionIds;
      batches.add(batch);

      for (final questionId in batch) {
        cycle = cycle.recordAnswer(
          questionId: questionId,
          isCorrect: true,
          answeredAt: DateTime.utc(2026, 7, 15, 11),
        );
      }
    }

    final allQuestionIds = batches.expand((batch) => batch).toList();

    expect(batches.map((batch) => batch.length), <int>[10, 10, 3]);
    expect(allQuestionIds.length, 23);
    expect(allQuestionIds.toSet().length, 23);
    expect(cycle.isComplete, isTrue);
    expect(cycle.nextBatchQuestionIds, isEmpty);
  });
}
