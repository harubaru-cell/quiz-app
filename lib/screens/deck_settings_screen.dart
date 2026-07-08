import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/quiz_deck.dart';
import '../models/quiz_session.dart';
import '../services/quiz_engine.dart';
import '../state/quiz_session_state.dart';
import '../widgets/bottom_action_area.dart';
import 'quiz_screen.dart';

class DeckSettingsScreen extends StatefulWidget {
  const DeckSettingsScreen({
    super.key,
    required this.deck,
    this.onlyQuestionIds,
    this.initialShuffle = true,
  });

  final QuizDeck deck;
  final List<String>? onlyQuestionIds;
  final bool initialShuffle;

  @override
  State<DeckSettingsScreen> createState() => _DeckSettingsScreenState();
}

class _DeckSettingsScreenState extends State<DeckSettingsScreen> {
  QuestionCountOption _countOption = QuestionCountOption.ten;
  late bool _shuffle;

  @override
  void initState() {
    super.initState();
    _shuffle = widget.initialShuffle;
  }

  @override
  Widget build(BuildContext context) {
    final targetCount = widget.onlyQuestionIds?.length ?? widget.deck.questions.length;
    return Scaffold(
      appBar: AppBar(title: const Text('開始設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(widget.deck.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('${widget.deck.subject.isEmpty ? '科目未設定' : widget.deck.subject} / $targetCount問'),
          if (widget.onlyQuestionIds != null) ...[
            const SizedBox(height: 8),
            const Chip(label: Text('間違えた問題だけ')),
          ],
          const SizedBox(height: 24),
          Text('出題数', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<QuestionCountOption>(
            segments: QuestionCountOption.values
                .map(
                  (option) => ButtonSegment<QuestionCountOption>(
                    value: option,
                    label: Text(option.label),
                  ),
                )
                .toList(),
            selected: {_countOption},
            onSelectionChanged: (values) {
              setState(() => _countOption = values.first);
            },
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('シャッフル'),
            subtitle: const Text('問題の出題順をランダムにします'),
            value: _shuffle,
            onChanged: (value) => setState(() => _shuffle = value),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionArea(
        child: FilledButton.icon(
          onPressed: targetCount == 0 ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('開始'),
        ),
      ),
    );
  }

  void _start() {
    final questions = QuizEngine().buildQuestions(
      source: widget.deck.questions,
      countOption: _countOption,
      shuffle: _shuffle,
      onlyQuestionIds: widget.onlyQuestionIds,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => QuizSessionState(
            deck: widget.deck,
            questions: questions,
          ),
          child: const QuizScreen(),
        ),
      ),
    );
  }
}
