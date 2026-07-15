import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const decksKey = 'quiz_app.decks';
  static const historiesKey = 'quiz_app.histories';
  static const deckStatsKey = 'quiz_app.deck_stats';
  static const questionProgressKey = 'quiz_app.question_progress';
  static const studyCyclesKey = 'quiz_app.study_cycles';

  Future<String?> readString(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  Future<void> writeString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final didSave = await preferences.setString(key, value);

    if (!didSave) {
      throw StateError('保存に失敗しました: $key');
    }
  }

  Future<void> remove(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}
