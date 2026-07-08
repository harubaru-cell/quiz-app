import 'package:flutter/material.dart';

import '../models/deck_stats.dart';
import '../models/quiz_deck.dart';
import '../utils/date_format.dart';

class DeckCard extends StatelessWidget {
  const DeckCard({
    super.key,
    required this.deck,
    required this.stats,
    required this.onTap,
    required this.onDelete,
  });

  final QuizDeck deck;
  final DeckStats stats;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(deck.title, style: textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          deck.subject.isEmpty ? '科目未設定' : deck.subject,
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'デッキ削除',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _StatChip(label: '問題数', value: '${deck.questions.length}問'),
                  _StatChip(label: '正答率', value: formatPercent(stats.accuracy)),
                  _StatChip(label: '挑戦', value: '${stats.attemptCount}回'),
                ],
              ),
              const SizedBox(height: 10),
              Text('最終プレイ: ${formatLastPlayed(stats.lastPlayedAt)}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label $value'),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
