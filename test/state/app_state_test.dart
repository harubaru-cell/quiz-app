import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:personal_quiz_study/models/question_progress.dart';
import 'package:personal_quiz_study/models/quiz_history.dart';
import 'package:personal_quiz_study/services/storage_service.dart';
import 'package:personal_quiz_study/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('旧履歴を残したまま問題別進捗を初回生成する', () async {
    final history = QuizHistory(
      id: 'history-1',
      deckId: 'deck-1',
      playedAt: DateTime.utc(2026, 7, 15, 10),
      totalAnswered: 1,
      correctCount: 0,
      incorrectCount: 1,
      completed: true,
      results: <QuestionResult>[
        QuestionResult(
          questionId: 'question-1',
          isCorrect: false,
          answeredAt: DateTime.utc(2026, 7, 15, 10),
        ),
      ],
    );
    final historiesRaw = jsonEncode(<Map<String, dynamic>>[
      history.toJson(),
    ]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      StorageService.historiesKey: historiesRaw,
    });
    final appState = AppState();

    await appState.load();

    final progress = appState.questionProgressFor('deck-1', 'question-1');
    final unanswered = appState.questionProgressFor('deck-1', 'question-2');
    final preferences = await SharedPreferences.getInstance();

    expect(appState.message, isNull);
    expect(progress.answerCount, 1);
    expect(progress.status, QuestionProgressStatus.needsReview);
    expect(unanswered.status, QuestionProgressStatus.unanswered);
    expect(preferences.getString(StorageService.historiesKey), historiesRaw);
    expect(
      preferences.getString(StorageService.questionProgressKey),
      isNotNull,
    );
  });

  test('回答直後に進捗だけを保存し、履歴と集計を二重加算しない', () async {
    final appState = AppState();
    final result = QuestionResult(
      questionId: 'question-1',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );

    await appState.load();
    await appState.recordQuestionResult('deck-1', result);

    final preferences = await SharedPreferences.getInstance();
    final savedProgressRaw = preferences.getString(
      StorageService.questionProgressKey,
    );

    expect(savedProgressRaw, isNotNull);
    expect(appState.questionProgressFor('deck-1', 'question-1').answerCount, 1);
    expect(appState.statsFor('deck-1').attemptCount, 0);
    expect(appState.statsFor('deck-1').totalAnswered, 0);
    expect(preferences.getString(StorageService.historiesKey), isNull);

    final reloadedAppState = AppState();
    await reloadedAppState.load();

    expect(
      reloadedAppState.questionProgressFor('deck-1', 'question-1').answerCount,
      1,
    );

    final history = QuizHistory(
      id: 'history-1',
      deckId: 'deck-1',
      playedAt: DateTime.utc(2026, 7, 15, 10),
      totalAnswered: 1,
      correctCount: 0,
      incorrectCount: 1,
      completed: true,
      results: <QuestionResult>[result],
    );

    await appState.recordHistory(history);

    expect(appState.statsFor('deck-1').attemptCount, 1);
    expect(appState.statsFor('deck-1').totalAnswered, 1);
    expect(appState.questionProgressFor('deck-1', 'question-1').answerCount, 1);
    expect(
      (jsonDecode(preferences.getString(StorageService.historiesKey)!) as List)
          .length,
      1,
    );
  });

  test('問題別進捗の保存に失敗しても呼び出しを完了する', () async {
    final storageService = _FailingStorageService();
    final appState = AppState(storageService: storageService);
    final result = QuestionResult(
      questionId: 'question-1',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );

    await appState.load();
    storageService.failQuestionProgressWrites = true;

    await appState.recordQuestionResult('deck-1', result);

    expect(appState.message, contains('問題別進捗の保存に失敗しました'));
    expect(appState.questionProgressFor('deck-1', 'question-1').answerCount, 1);
  });

  test('一周の回答位置を問題別進捗と保存し再起動後も同じ区切りから再開する', () async {
    final appState = AppState();

    await appState.load();
    final started = await appState.startStudyCycle(
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: List<String>.generate(
        23,
        (index) => 'question-${index + 1}',
      ),
      batchSize: 10,
    );

    expect(started, isNotNull);
    expect(
      started!.nextBatchQuestionIds,
      List<String>.generate(10, (index) => 'question-${index + 1}'),
    );

    for (var index = 0; index < 4; index++) {
      await appState.recordStudyCycleQuestionResult(
        deckId: 'deck-1',
        cycleId: started.cycleId,
        result: QuestionResult(
          questionId: 'question-${index + 1}',
          isCorrect: index.isEven,
          answeredAt: DateTime.utc(2026, 7, 15, 10, index),
        ),
      );
    }

    final current = appState.studyCycleFor('deck-1');
    expect(current, isNotNull);
    expect(current!.completedCount, 4);
    expect(
      current.nextBatchQuestionIds,
      List<String>.generate(6, (index) => 'question-${index + 5}'),
    );
    expect(appState.statsFor('deck-1').attemptCount, 0);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(StorageService.historiesKey), isNull);

    final reloaded = AppState();
    await reloaded.load();

    final restored = reloaded.studyCycleFor('deck-1');
    expect(restored, isNotNull);
    expect(restored!.completedCount, 4);
    expect(
      restored.nextBatchQuestionIds,
      List<String>.generate(6, (index) => 'question-${index + 5}'),
    );
    expect(
      reloaded.questionProgressFor('deck-1', 'question-4').answerCount,
      1,
    );
  });

  test('古い一周IDや同じ問題の重複通知では位置と進捗を二重更新しない', () async {
    final appState = AppState();

    await appState.load();
    final cycle = await appState.startStudyCycle(
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['question-1', 'question-2'],
      batchSize: 10,
    );
    final firstResult = QuestionResult(
      questionId: 'question-1',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 15, 10),
    );

    await appState.recordStudyCycleQuestionResult(
      deckId: 'deck-1',
      cycleId: cycle!.cycleId,
      result: firstResult,
    );
    await expectLater(
      appState.recordStudyCycleQuestionResult(
        deckId: 'deck-1',
        cycleId: cycle.cycleId,
        result: firstResult,
      ),
      throwsStateError,
    );
    await expectLater(
      appState.recordStudyCycleQuestionResult(
        deckId: 'deck-1',
        cycleId: 'old-cycle',
        result: QuestionResult(
          questionId: 'question-2',
          isCorrect: true,
          answeredAt: DateTime.utc(2026, 7, 15, 11),
        ),
      ),
      throwsStateError,
    );

    expect(appState.studyCycleFor('deck-1')!.completedCount, 1);
    expect(
      appState.questionProgressFor('deck-1', 'question-1').answerCount,
      1,
    );
    expect(
      appState.questionProgressFor('deck-1', 'question-2').answerCount,
      0,
    );
  });

  test('一周状態の保存に失敗した場合は以前の状態へ戻して呼び出しを完了する', () async {
    final storageService = _FailingStorageService();
    final appState = AppState(storageService: storageService);

    await appState.load();
    storageService.failStudyCycleWrites = true;

    final cycle = await appState.startStudyCycle(
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['question-1'],
      batchSize: 10,
    );

    expect(cycle, isNull);
    expect(appState.studyCycleFor('deck-1'), isNull);
    expect(appState.message, contains('一周学習の保存に失敗しました'));
  });

  test('回答位置の保存に失敗した場合は進捗を加算せず一周位置を戻す', () async {
    final storageService = _FailingStorageService();
    final appState = AppState(storageService: storageService);

    await appState.load();
    final cycle = await appState.startStudyCycle(
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['question-1'],
      batchSize: 10,
    );
    storageService.failStudyCycleWrites = true;

    await expectLater(
      appState.recordStudyCycleQuestionResult(
        deckId: 'deck-1',
        cycleId: cycle!.cycleId,
        result: QuestionResult(
          questionId: 'question-1',
          isCorrect: true,
          answeredAt: DateTime.utc(2026, 7, 15, 10),
        ),
      ),
      throwsStateError,
    );

    expect(appState.studyCycleFor('deck-1')!.completedCount, 0);
    expect(
      appState.questionProgressFor('deck-1', 'question-1').answerCount,
      0,
    );
  });

  test('進捗保存だけ失敗した回答は一周記録から次回起動時に復旧する', () async {
    final storageService = _FailingStorageService();
    final appState = AppState(storageService: storageService);

    await appState.load();
    final cycle = await appState.startStudyCycle(
      deckId: 'deck-1',
      deckSignature: 'signature-1',
      orderedQuestionIds: const <String>['question-1'],
      batchSize: 10,
    );
    storageService.failQuestionProgressWrites = true;

    await appState.recordStudyCycleQuestionResult(
      deckId: 'deck-1',
      cycleId: cycle!.cycleId,
      result: QuestionResult(
        questionId: 'question-1',
        isCorrect: false,
        answeredAt: DateTime.utc(2026, 7, 15, 10),
      ),
    );

    expect(appState.studyCycleFor('deck-1')!.isComplete, isTrue);
    expect(appState.message, contains('次回起動時に一周学習の記録から復旧します'));

    final replacement = await appState.startStudyCycle(
      deckId: 'deck-1',
      deckSignature: 'signature-2',
      orderedQuestionIds: const <String>['question-2'],
      batchSize: 10,
    );

    expect(replacement, isNull);
    expect(appState.studyCycleFor('deck-1')!.cycleId, cycle.cycleId);

    storageService.failQuestionProgressWrites = false;
    final reloaded = AppState(storageService: storageService);
    await reloaded.load();

    final restoredProgress = reloaded.questionProgressFor(
      'deck-1',
      'question-1',
    );
    expect(restoredProgress.answerCount, 1);
    expect(restoredProgress.latestIsCorrect, isFalse);
    expect(reloaded.studyCycleFor('deck-1')!.isComplete, isTrue);
  });

  test('デッキ更新で削除された問題の進捗だけを除外する', () async {
    final appState = AppState();
    final firstResult = QuestionResult(
      questionId: 'question-1',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 16, 10),
    );
    final secondResult = QuestionResult(
      questionId: 'question-2',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 16, 10, 1),
    );

    await appState.load();
    await appState.importDeckFromBytes(
      _deckBytes(
        deckId: 'deck-1',
        questionIds: const <String>['question-1', 'question-2'],
        version: '1.3',
      ),
    );
    await appState.recordQuestionResult('deck-1', firstResult);
    await appState.recordQuestionResult('deck-1', secondResult);
    await appState.recordHistory(
      _historyForDeck(
        id: 'history-1',
        deckId: 'deck-1',
        results: <QuestionResult>[firstResult, secondResult],
      ),
    );

    final originalDeck = appState.decks.single;
    final originalCycle = await appState.startStudyCycle(
      deckId: originalDeck.id,
      deckSignature: originalDeck.contentSignature,
      orderedQuestionIds:
          originalDeck.questions.map((question) => question.id).toList(),
      batchSize: 10,
    );

    await appState.importDeckFromBytes(
      _deckBytes(
        deckId: 'deck-1',
        questionIds: const <String>['question-2', 'question-3'],
      ),
    );

    final updatedDeck = appState.decks.single;
    final remainingProgressIds = appState
        .questionProgressForDeck('deck-1')
        .map((progress) => progress.questionId)
        .toSet();

    expect(remainingProgressIds, <String>{'question-2'});
    expect(
      appState.questionProgressFor('deck-1', 'question-1').status,
      QuestionProgressStatus.unanswered,
    );
    expect(
      appState.questionProgressFor('deck-1', 'question-2').answerCount,
      1,
    );
    expect(
      appState.questionProgressFor('deck-1', 'question-3').status,
      QuestionProgressStatus.unanswered,
    );
    expect(appState.statsFor('deck-1').attemptCount, 1);
    expect(appState.statsFor('deck-1').totalAnswered, 2);
    expect(appState.studyCycleFor('deck-1')!.cycleId, originalCycle!.cycleId);
    expect(
      appState.studyCycleFor('deck-1')!.deckSignature,
      isNot(updatedDeck.contentSignature),
    );

    final preferences = await SharedPreferences.getInstance();
    final savedHistories = jsonDecode(
      preferences.getString(StorageService.historiesKey)!,
    ) as List;
    expect(savedHistories, hasLength(1));
    expect(savedHistories.single['id'], 'history-1');

    final reloaded = AppState();
    await reloaded.load();

    expect(
      reloaded
          .questionProgressForDeck('deck-1')
          .map((progress) => progress.questionId)
          .toSet(),
      <String>{'question-2'},
    );
    expect(
      reloaded.questionProgressFor('deck-1', 'question-3').status,
      QuestionProgressStatus.unanswered,
    );
    expect(reloaded.statsFor('deck-1').attemptCount, 1);
    expect(
      reloaded.studyCycleFor('deck-1')!.deckSignature,
      isNot(reloaded.decks.single.contentSignature),
    );
  });

  test('デッキ削除で対象の進捗と一周だけを保存データから削除する', () async {
    final appState = AppState();
    final firstResult = QuestionResult(
      questionId: 'question-a',
      isCorrect: false,
      answeredAt: DateTime.utc(2026, 7, 16, 11),
    );
    final secondResult = QuestionResult(
      questionId: 'question-b',
      isCorrect: true,
      answeredAt: DateTime.utc(2026, 7, 16, 11, 1),
    );

    await appState.load();
    await appState.importDeckFromBytes(
      _deckBytes(
        deckId: 'deck-a',
        questionIds: const <String>['question-a'],
      ),
    );
    await appState.importDeckFromBytes(
      _deckBytes(
        deckId: 'deck-b',
        questionIds: const <String>['question-b'],
      ),
    );
    await appState.recordQuestionResult('deck-a', firstResult);
    await appState.recordQuestionResult('deck-b', secondResult);

    for (final deck in appState.decks) {
      await appState.startStudyCycle(
        deckId: deck.id,
        deckSignature: deck.contentSignature,
        orderedQuestionIds:
            deck.questions.map((question) => question.id).toList(),
        batchSize: 10,
      );
    }

    await appState.recordHistory(
      _historyForDeck(
        id: 'history-a',
        deckId: 'deck-a',
        results: <QuestionResult>[firstResult],
      ),
    );
    await appState.recordHistory(
      _historyForDeck(
        id: 'history-b',
        deckId: 'deck-b',
        results: <QuestionResult>[secondResult],
      ),
    );

    final remainingCycleId = appState.studyCycleFor('deck-b')!.cycleId;
    await appState.deleteDeck('deck-a');

    expect(appState.decks.map((deck) => deck.id), <String>['deck-b']);
    expect(appState.questionProgressForDeck('deck-a'), isEmpty);
    expect(appState.studyCycleFor('deck-a'), isNull);
    expect(appState.statsFor('deck-a').attemptCount, 0);
    expect(
      appState.questionProgressFor('deck-b', 'question-b').answerCount,
      1,
    );
    expect(appState.studyCycleFor('deck-b')!.cycleId, remainingCycleId);
    expect(appState.statsFor('deck-b').attemptCount, 1);

    final preferences = await SharedPreferences.getInstance();
    final savedHistories = jsonDecode(
      preferences.getString(StorageService.historiesKey)!,
    ) as List;
    expect(
      savedHistories.map((item) => (item as Map)['deckId']).toSet(),
      <String>{'deck-b'},
    );

    final reloaded = AppState();
    await reloaded.load();

    expect(reloaded.decks.map((deck) => deck.id), <String>['deck-b']);
    expect(reloaded.questionProgressForDeck('deck-a'), isEmpty);
    expect(reloaded.studyCycleFor('deck-a'), isNull);
    expect(
      reloaded.questionProgressFor('deck-b', 'question-b').answerCount,
      1,
    );
    expect(reloaded.studyCycleFor('deck-b')!.cycleId, remainingCycleId);
    expect(reloaded.statsFor('deck-b').attemptCount, 1);
  });

  test('同じ履歴IDを再保存しても履歴と挑戦回数を二重加算しない', () async {
    final appState = AppState();
    final history = _historyForIdempotencyTest();

    await appState.load();
    await appState.recordHistory(history);
    await appState.recordHistory(history);

    final preferences = await SharedPreferences.getInstance();
    final savedHistories = jsonDecode(
      preferences.getString(StorageService.historiesKey)!,
    ) as List;

    expect(savedHistories.length, 1);
    expect(appState.statsFor('deck-1').attemptCount, 1);
    expect(appState.statsFor('deck-1').totalAnswered, 1);
  });

  test('履歴保存の途中失敗後に同じIDで再試行しても集計は一度だけ加算する', () async {
    final storageService = _FailingStorageService();
    final appState = AppState(storageService: storageService);
    final history = _historyForIdempotencyTest();

    await appState.load();
    storageService.failDeckStatsWrites = true;

    await expectLater(
      appState.recordHistory(history),
      throwsStateError,
    );

    storageService.failDeckStatsWrites = false;
    await appState.recordHistory(history);

    final preferences = await SharedPreferences.getInstance();
    final savedHistories = jsonDecode(
      preferences.getString(StorageService.historiesKey)!,
    ) as List;
    final savedStats = jsonDecode(
      preferences.getString(StorageService.deckStatsKey)!,
    ) as List;

    expect(savedHistories.length, 1);
    expect(savedStats.single['attemptCount'], 1);
    expect(savedStats.single['totalAnswered'], 1);
    expect(appState.statsFor('deck-1').attemptCount, 1);
  });
}

QuizHistory _historyForIdempotencyTest() {
  final result = QuestionResult(
    questionId: 'question-1',
    isCorrect: true,
    answeredAt: DateTime.utc(2026, 7, 15, 10),
  );

  return QuizHistory(
    id: 'history-1',
    deckId: 'deck-1',
    playedAt: DateTime.utc(2026, 7, 15, 10),
    totalAnswered: 1,
    correctCount: 1,
    incorrectCount: 0,
    completed: true,
    results: <QuestionResult>[result],
  );
}

Uint8List _deckBytes({
  required String deckId,
  required List<String> questionIds,
  String version = '1.4',
}) {
  final deck = <String, dynamic>{
    'deckId': deckId,
    'subject': 'テスト科目',
    'title': '$deckId テストデッキ',
    'version': version,
    'questions': questionIds
        .map(
          (questionId) => <String, dynamic>{
            'id': questionId,
            'type': 'multiple_choice',
            'question': '$questionId の問題',
            'choices': <String>['A', 'B', 'C', 'D'],
            'answer': 0,
            'explanation': '解説',
            'tags': <String>[],
            'difficulty': 'normal',
          },
        )
        .toList(),
  };

  return Uint8List.fromList(utf8.encode(jsonEncode(deck)));
}

QuizHistory _historyForDeck({
  required String id,
  required String deckId,
  required List<QuestionResult> results,
}) {
  final correctCount = results.where((result) => result.isCorrect).length;

  return QuizHistory(
    id: id,
    deckId: deckId,
    playedAt: results.last.answeredAt,
    totalAnswered: results.length,
    correctCount: correctCount,
    incorrectCount: results.length - correctCount,
    completed: true,
    results: results,
  );
}

class _FailingStorageService extends StorageService {
  bool failQuestionProgressWrites = false;
  bool failStudyCycleWrites = false;
  bool failDeckStatsWrites = false;

  @override
  Future<void> writeString(String key, String value) {
    if (failQuestionProgressWrites &&
        key == StorageService.questionProgressKey) {
      return Future<void>.error(StateError('保存失敗'));
    }
    if (failStudyCycleWrites && key == StorageService.studyCyclesKey) {
      return Future<void>.error(StateError('保存失敗'));
    }
    if (failDeckStatsWrites && key == StorageService.deckStatsKey) {
      return Future<void>.error(StateError('保存失敗'));
    }

    return super.writeString(key, value);
  }
}
