import 'dart:convert';

import '../models/question_progress.dart';
import '../models/quiz_history.dart';
import '../services/storage_service.dart';

class QuestionProgressRepository {
  QuestionProgressRepository(this._storageService);

  final StorageService _storageService;

  Future<QuestionProgressSnapshot?> loadProgress() async {
    final raw = await _storageService.readString(
      StorageService.questionProgressKey,
    );

    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw const FormatException('問題別進捗の保存形式が不正です。');
    }

    return QuestionProgressSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<void> saveProgress(QuestionProgressSnapshot snapshot) async {
    await _storageService.writeString(
      StorageService.questionProgressKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  QuestionProgressSnapshot migrateFromHistories(
    List<QuizHistory> histories,
  ) {
    final latestHistoriesById = <String, QuizHistory>{};

    for (final history in histories) {
      latestHistoriesById[history.id] = history;
    }

    final events = <_ProgressEvent>[];
    var sequence = 0;

    for (final history in latestHistoriesById.values) {
      for (final result in history.results) {
        events.add(
          _ProgressEvent(
            deckId: history.deckId,
            result: result,
            sequence: sequence,
          ),
        );
        sequence += 1;
      }
    }

    events.sort((left, right) {
      final dateComparison = left.result.answeredAt.compareTo(
        right.result.answeredAt,
      );

      if (dateComparison != 0) {
        return dateComparison;
      }

      return left.sequence.compareTo(right.sequence);
    });

    final progressByDeck = <String, Map<String, QuestionProgress>>{};

    for (final event in events) {
      final progressByQuestion = progressByDeck.putIfAbsent(
        event.deckId,
        () => <String, QuestionProgress>{},
      );
      final questionId = event.result.questionId;
      final current = progressByQuestion[questionId] ??
          QuestionProgress.unanswered(
            deckId: event.deckId,
            questionId: questionId,
          );

      progressByQuestion[questionId] = current.recordAnswer(
        isCorrect: event.result.isCorrect,
        answeredAt: event.result.answeredAt,
      );
    }

    final items = progressByDeck.values
        .expand((progressByQuestion) => progressByQuestion.values)
        .toList()
      ..sort((left, right) {
        final deckComparison = left.deckId.compareTo(right.deckId);

        if (deckComparison != 0) {
          return deckComparison;
        }

        return left.questionId.compareTo(right.questionId);
      });

    return QuestionProgressSnapshot(
      schemaVersion: QuestionProgressSnapshot.currentSchemaVersion,
      items: items,
    );
  }
}

class _ProgressEvent {
  const _ProgressEvent({
    required this.deckId,
    required this.result,
    required this.sequence,
  });

  final String deckId;
  final QuestionResult result;
  final int sequence;
}
