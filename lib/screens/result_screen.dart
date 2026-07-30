import 'package:flutter/material.dart';

import '../models/quiz_deck.dart';
import '../models/quiz_history.dart';
import '../models/quiz_question.dart';
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
    final accuracy = history.totalAnswered == 0
        ? 0.0
        : history.correctCount / history.totalAnswered;
    final wrongIds = history.results
        .where((result) => !result.isCorrect)
        .map((result) => result.questionId)
        .toList();
    final questionsById = <String, QuizQuestion>{
      for (final question in deck.questions) question.id: question,
    };
    final flashcardResults = history.results.where((result) {
      return questionsById[result.questionId]?.type == QuestionType.flashcard;
    }).toList();

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
          if (flashcardResults.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'フラッシュカードの振り返り',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final result in flashcardResults)
              _FlashcardResultCard(
                question: questionsById[result.questionId]!,
                result: result,
              ),
          ],
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
                onPressed: wrongIds.isEmpty
                    ? null
                    : () => _retryWrongOnly(context, wrongIds),
                icon: const Icon(Icons.replay),
                label: const Text('間違えた問題だけ挑戦'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
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

class _FlashcardResultCard extends StatelessWidget {
  const _FlashcardResultCard({
    required this.question,
    required this.result,
  });

  final QuizQuestion question;
  final QuestionResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(_ratingLabel(result)),
        subtitle: Text(
          result.isCorrect ? '正解扱い' : '要復習',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResultDetailSection(
                  title: '事案の概要',
                  content: question.question,
                ),
                const SizedBox(height: 16),
                _ResultDetailSection(
                  title: '模範解答',
                  content: question.flashcardAnswer ?? '',
                ),
                if (question.explanation.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ResultDetailSection(
                    title: '解説・事件名',
                    content: question.explanation,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ratingLabel(QuestionResult result) {
    return switch (result.flashcardRating) {
      FlashcardRating.remembered => '自己評価：覚えた',
      FlashcardRating.unsure => '自己評価：あやしい',
      FlashcardRating.forgotten => '自己評価：覚えていない',
      null => result.isCorrect ? '自己評価：覚えた' : '自己評価：要復習',
    };
  }
}

class _ResultDetailSection extends StatelessWidget {
  const _ResultDetailSection({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          softWrap: true,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.55,
              ),
        ),
      ],
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
