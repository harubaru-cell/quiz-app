import 'dart:convert';

import '../models/quiz_deck.dart';
import '../services/storage_service.dart';

class DeckRepository {
  DeckRepository(this._storageService);

  final StorageService _storageService;

  Future<List<QuizDeck>> loadDecks() async {
    final raw = await _storageService.readString(StorageService.decksKey);
    if (raw == null || raw.isEmpty) {
      return <QuizDeck>[];
    }
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((item) => QuizDeck.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> saveDecks(List<QuizDeck> decks) async {
    await _storageService.writeString(
      StorageService.decksKey,
      jsonEncode(decks.map((deck) => deck.toJson()).toList()),
    );
  }
}
