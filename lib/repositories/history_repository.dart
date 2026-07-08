import 'dart:convert';

import '../models/deck_stats.dart';
import '../models/quiz_history.dart';
import '../services/storage_service.dart';

class HistoryRepository {
  HistoryRepository(this._storageService);

  final StorageService _storageService;

  Future<List<QuizHistory>> loadHistories() async {
    final raw = await _storageService.readString(StorageService.historiesKey);
    if (raw == null || raw.isEmpty) {
      return <QuizHistory>[];
    }
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((item) => QuizHistory.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> saveHistories(List<QuizHistory> histories) async {
    await _storageService.writeString(
      StorageService.historiesKey,
      jsonEncode(histories.map((history) => history.toJson()).toList()),
    );
  }

  Future<Map<String, DeckStats>> loadStats() async {
    final raw = await _storageService.readString(StorageService.deckStatsKey);
    if (raw == null || raw.isEmpty) {
      return <String, DeckStats>{};
    }
    final decoded = jsonDecode(raw) as List;
    final stats = decoded
        .map((item) => DeckStats.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    return {for (final item in stats) item.deckId: item};
  }

  Future<void> saveStats(Map<String, DeckStats> stats) async {
    await _storageService.writeString(
      StorageService.deckStatsKey,
      jsonEncode(stats.values.map((item) => item.toJson()).toList()),
    );
  }
}
