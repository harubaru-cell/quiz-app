import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/quiz_deck.dart';

class JsonImportService {
  JsonImportService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  QuizDeck parseDeck(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('JSONの最上位はオブジェクトにしてください。');
    }

    final now = DateTime.now();
    final deck = QuizDeck.fromJson(Map<String, dynamic>.from(decoded));
    return deck.copyWith(
      id: deck.id.isEmpty ? _uuid.v4() : deck.id,
      createdAt: deck.createdAt,
      updatedAt: now,
    );
  }
}
