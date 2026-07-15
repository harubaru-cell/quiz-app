import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:personal_quiz_study/models/study_cycle.dart';
import 'package:personal_quiz_study/repositories/study_cycle_repository.dart';
import 'package:personal_quiz_study/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a missing new key loads as an empty versioned snapshot', () async {
    final repository = StudyCycleRepository(StorageService());

    final snapshot = await repository.loadCycles();

    expect(snapshot.schemaVersion, StudyCycleSnapshot.currentSchemaVersion);
    expect(snapshot.items, isEmpty);
  });

  test('saving cycles preserves all existing storage keys', () async {
    const existingDecks = '[{"deckId":"deck-1"}]';
    const existingHistories = '[{"id":"history-1"}]';
    const existingStats = '[{"deckId":"deck-1"}]';
    const existingProgress = '{"schemaVersion":1,"items":[]}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageService.decksKey: existingDecks,
      StorageService.historiesKey: existingHistories,
      StorageService.deckStatsKey: existingStats,
      StorageService.questionProgressKey: existingProgress,
    });
    final repository = StudyCycleRepository(StorageService());
    final cycle = StudyCycle.start(
      cycleId: 'cycle-1',
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['q-2', 'q-1'],
      batchSize: 10,
      startedAt: DateTime.utc(2026, 7, 15, 10),
    ).recordAnswer(
      questionId: 'q-2',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 11),
    );
    final snapshot = StudyCycleSnapshot(
      schemaVersion: StudyCycleSnapshot.currentSchemaVersion,
      items: <StudyCycle>[cycle],
    );

    await repository.saveCycles(snapshot);

    final loaded = await repository.loadCycles();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded.items.single.cycleId, 'cycle-1');
    expect(loaded.items.single.deckSignature, 'signature-1');
    expect(loaded.items.single.orderedQuestionIds, <String>['q-2', 'q-1']);
    expect(loaded.items.single.answeredEvents.single.questionId, 'q-2');
    expect(loaded.items.single.answeredEvents.single.isCorrect, isFalse);
    expect(preferences.getString(StorageService.decksKey), existingDecks);
    expect(
      preferences.getString(StorageService.historiesKey),
      existingHistories,
    );
    expect(preferences.getString(StorageService.deckStatsKey), existingStats);
    expect(
      preferences.getString(StorageService.questionProgressKey),
      existingProgress,
    );
    expect(preferences.getString(StorageService.studyCyclesKey), isNotNull);
  });
}
