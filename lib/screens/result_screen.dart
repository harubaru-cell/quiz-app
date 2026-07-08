import 'package:flutter/material.dart';

import '../models/quiz_deck.dart';
import '../models/quiz_history.dart';
import '../models/quiz_session.dart';
import '../utils/date_format.dart';
import '../widgets/bottom_action_area.dart';
import 'deck_settings_screen.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.deck,
    required this.history,
  });

  final QuizDeck deck;
  final QuizHistory history;

  @override
  Widget build(BuildContext context) {
    final accuracy = history.totalAnswered == 0 ? 0.0 : history.correctCount / history.totalAnswered;
    final wrongIds = history.results
        .where((result) => !result.isCorrect)
        .map((result) => result.questionId)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(deck.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(history.completed ? '完了' : '途中終了'),
          const SizedBox(height: 24),
          _ResultTile(label: '回答数', value: '${history.totalAnswered}問'),
          _ResultTile(label: '正答数', value: '${history.correctCount}問'),
          _ResultTile(label: '不正解数', value: '${history.incorrectCount}問'),
          _ResultTile(label: '正答率', value: formatPercent(accuracy)),
        ],
      ),
      bottomNavigationBar: BottomActionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _restart(context),
                icon: const Icon(Icons.refresh),
                label: const Text('もう一度挑戦'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: wrongIds.isEmpty ? null : () => _retryWrongOnly(context, wrongIds),
                icon: const Icon(Icons.replay),
                label: const Text('間違えた問題だけ挑戦'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                icon: const Icon(Icons.home_outlined),
                label: const Text('ホームへ戻る'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _restart(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DeckSettingsScreen(deck: deck),
      ),
    );
  }

  void _retryWrongOnly(BuildContext context, List<String> wrongIds) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DeckSettingsScreen(
          deck: deck,
          onlyQuestionIds: wrongIds,
          initialShuffle: false,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
