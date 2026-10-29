import 'dart:convert';

import '../models/deck_stats.dart';
import '../models/question_progress.dart';
import '../models/quiz_backup.dart';
import '../models/quiz_deck.dart';
import '../models/quiz_history.dart';
import '../models/study_cycle.dart';

class BackupValidationReport {
  BackupValidationReport(this.counts, this.errors, this.warnings);

  final Map<String, int> counts;
  final List<String> errors;
  final List<String> warnings;
  bool get canVerifyRestore => errors.isEmpty;
}

/// Diagnostics never write model.toJson() back to the snapshot. Unknown fields,
/// missing optional fields, timestamps and even malformed source strings survive.
class BackupValidationService {
  BackupValidationReport validate(BackupSnapshot snapshot) {
    final counts = <String, int>{
      'デッキ': 0,
      '問題': 0,
      '学習履歴': 0,
      '履歴内の回答': 0,
      'デッキ集計': 0,
      '問題別進捗': 0,
      '一周状態': 0,
      '一周内の回答': 0,
      '音声ファイル': snapshot.audio.length,
      '音声バイト':
          snapshot.audio.values.fold(0, (sum, bytes) => sum + bytes.length),
    };
    final errors = <String>[];
    final warnings = <String>[];
    final decoded = <String, dynamic>{};
    for (final entry in snapshot.preferences.entries) {
      if (!backupPreferenceKeys.contains(entry.key)) {
        warnings.add('未解釈の保存キーも原文で保持します: ${entry.key}');
        continue;
      }
      if (entry.value == null) continue;
      try {
        final value = jsonDecode(entry.value!);
        if (value is! String) throw const FormatException('文字列保存ではありません。');
        if (value.isEmpty) {
          warnings.add('${entry.key}: 空の保存値をそのまま保持しています。');
          continue;
        }
        final content = jsonDecode(value);
        if (content == null) {
          throw const FormatException('保存内容がnullです。');
        }
        decoded[entry.key] = content;
      } catch (_) {
        errors.add('${entry.key}: 保存値のJSONを読み取れません。原文は保持されています。');
      }
    }
    dynamic value(String suffix) => decoded['$backupPreferencePrefix$suffix'];
    Map<String, dynamic> object(dynamic item) =>
        Map<String, dynamic>.from(item as Map);
    void check(bool condition, String message) {
      if (!condition) errors.add(message);
    }

    void attempt(String label, void Function() read) {
      try {
        read();
      } catch (_) {
        errors.add('$label: 現行モデルで読み取れない構造です。原文は保持されています。');
      }
    }

    final decks = <String, QuizDeck>{};
    final audioReferences = <String>{};
    final externalAudio = <String>{};
    if (value('decks') != null) {
      attempt('デッキ', () {
        final items = value('decks') as List;
        counts['デッキ'] = items.length;
        for (var i = 0; i < items.length; i++) {
          attempt('デッキ${i + 1}', () {
            final raw = object(items[i]);
            final deck = QuizDeck.fromJson(raw);
            check(deck.id.isNotEmpty, 'デッキ${i + 1}: IDがありません。');
            if (decks.containsKey(deck.id)) {
              warnings.add('デッキIDが重複しています: ${deck.id}');
            }
            decks[deck.id] = deck;
            counts['問題'] = counts['問題']! + deck.questions.length;
            if (deck.hasDuplicateQuestionIds) {
              warnings.add('問題IDが重複しています: ${deck.id}');
            }
            for (final field in ['createdAt', 'updatedAt']) {
              if (raw[field] is! String ||
                  DateTime.tryParse(raw[field] as String) == null) {
                warnings.add('${deck.id}: $fieldが未指定・不正です。日時を補わず原文を保持します。');
              }
            }
            for (final question in deck.questions) {
              final audio = question.audio;
              if (audio == null) continue;
              if (audio.startsWith('stored-audio:')) {
                audioReferences.add(audio.substring('stored-audio:'.length));
              } else {
                externalAudio.add(audio);
              }
            }
          });
        }
      });
    }
    void references(String deckId, Iterable<String> ids, String label) {
      final deck = decks[deckId];
      if (deck == null) {
        warnings.add('$label: 現在存在しないデッキへの参照です: $deckId');
      } else {
        final known = deck.questions.map((q) => q.id).toSet();
        if (ids.any((id) => !known.contains(id))) {
          warnings.add('$label: 現在存在しない問題への参照があります。履歴を削除せず保持します。');
        }
      }
    }

    if (value('histories') != null) {
      attempt('学習履歴', () {
        final items = value('histories') as List;
        counts['学習履歴'] = items.length;
        final seen = <String>{};
        for (var i = 0; i < items.length; i++) {
          attempt('学習履歴${i + 1}', () {
            final history = QuizHistory.fromJson(object(items[i]));
            if (!seen.add(history.id)) {
              warnings.add('履歴IDが重複しています: ${history.id}');
            }
            counts['履歴内の回答'] = counts['履歴内の回答']! + history.results.length;
            check(
                history.totalAnswered == history.results.length &&
                    history.correctCount ==
                        history.results.where((r) => r.isCorrect).length &&
                    history.incorrectCount ==
                        history.results.where((r) => !r.isCorrect).length,
                '${history.id}: 履歴内の回答件数と正誤集計が一致しません。');
            references(history.deckId, history.results.map((r) => r.questionId),
                history.id);
          });
        }
      });
    }
    if (value('deck_stats') != null) {
      attempt('デッキ集計', () {
        final items = value('deck_stats') as List;
        counts['デッキ集計'] = items.length;
        final seen = <String>{};
        for (final item in items) {
          final stats = DeckStats.fromJson(object(item));
          if (!seen.add(stats.deckId)) {
            warnings.add('デッキ集計IDが重複しています: ${stats.deckId}');
          }
          check(
              stats.attemptCount >= 0 &&
                  stats.totalAnswered >= 0 &&
                  stats.totalCorrect >= 0 &&
                  stats.totalCorrect <= stats.totalAnswered,
              '${stats.deckId}: デッキ集計の数値が不正です。');
          references(stats.deckId, stats.incorrectQuestionIds, 'デッキ集計');
        }
      });
    }
    if (value('question_progress') != null) {
      attempt('問題別進捗', () {
        final progress = QuestionProgressSnapshot.fromJson(
            object(value('question_progress')));
        counts['問題別進捗'] = progress.items.length;
        final seen = <String>{};
        for (final p in progress.items) {
          if (!seen.add(jsonEncode([p.deckId, p.questionId]))) {
            warnings.add('問題別進捗が重複しています: ${p.deckId}/${p.questionId}');
          }
          check(
              p.answerCount == p.correctCount + p.incorrectCount &&
                  p.consecutiveCorrectCount <= p.correctCount,
              '${p.deckId}/${p.questionId}: 進捗内の回答件数が一致しません。');
          references(p.deckId, [p.questionId], '問題別進捗');
        }
      });
    }
    if (value('study_cycles') != null) {
      attempt('一周学習', () {
        final cycles =
            StudyCycleSnapshot.fromJson(object(value('study_cycles')));
        counts['一周状態'] = cycles.items.length;
        final seen = <String>{};
        for (final cycle in cycles.items) {
          counts['一周内の回答'] = counts['一周内の回答']! + cycle.answeredEvents.length;
          if (!seen.add(cycle.deckId)) {
            warnings.add('同じデッキの一周状態が重複しています: ${cycle.deckId}');
          }
          references(cycle.deckId, cycle.orderedQuestionIds, '一周学習');
          final deck = decks[cycle.deckId];
          if (deck != null && deck.contentSignature != cycle.deckSignature) {
            warnings.add('${cycle.deckId}: 一周開始時とデッキ内容が異なります。元の署名を保持します。');
          }
        }
      });
    }
    if (snapshot.audioDatabaseVersion != null &&
        snapshot.audioDatabaseVersion != 1) {
      errors.add('音声DBの版が未対応です。');
    }
    for (final key in audioReferences) {
      check(snapshot.audio.containsKey(key) && snapshot.audio[key]!.isNotEmpty,
          '参照する端末内音声が不足しています: $key');
    }
    if (externalAudio.isNotEmpty) {
      errors.add('外部URL・ZIP相対パスの音声はファイルに含まれないため、完全性を確認できません。');
    }
    if (snapshot.audio.keys.any((key) => !audioReferences.contains(key))) {
      warnings.add('現在の問題から参照されていない音声も省略せず保持しています。');
    }
    if (snapshot.preferences.values.every((value) => value == null) &&
        snapshot.audio.isEmpty) {
      warnings.add('この保存領域に学習データはありません。公開URL・ブラウザ・プロファイルを確認してください。');
    }
    if (value('question_progress') == null && (counts['履歴内の回答']! > 0)) {
      warnings.add('問題別進捗は未作成です。今回は履歴からの移行・再計算を行いません。');
    }
    return BackupValidationReport(Map.unmodifiable(counts),
        List.unmodifiable(errors), List.unmodifiable(warnings.toSet()));
  }
}
