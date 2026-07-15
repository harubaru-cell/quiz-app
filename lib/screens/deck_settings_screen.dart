import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/question_progress.dart';
import '../models/quiz_deck.dart';
import '../models/quiz_question.dart';
import '../models/quiz_session.dart';
import '../services/quiz_engine.dart';
import '../state/app_state.dart';
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
  static const List<String> _mainCategories = <String>[
    '単語',
    '文法',
    '和文中訳',
    'リスニング',
  ];

  static const String _otherCategory = 'その他';

  QuestionCountOption _countOption = QuestionCountOption.ten;
  QuestionProgressFilter _progressFilter = QuestionProgressFilter.all;
  late bool _shuffle;

  late final List<String> _availableCategories;
  late final Set<String> _selectedCategories;

  @override
  void initState() {
    super.initState();

    _shuffle = widget.initialShuffle;
    _availableCategories = _findAvailableCategories();
    _selectedCategories = _availableCategories.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final baseQuestions = _baseTargetQuestions;
    final selectedQuestions = _selectedTargetQuestions(appState);

    final baseCount = baseQuestions.length;
    final selectedCount = selectedQuestions.length;
    final emptySelectionLabel =
        _selectedCategories.isEmpty ? 'カテゴリーを選択してください' : '該当する問題がありません';

    return Scaffold(
      appBar: AppBar(
        title: const Text('開始設定'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            widget.deck.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.deck.subject.isEmpty ? '科目未設定' : widget.deck.subject}'
            ' / 対象$selectedCount問',
          ),
          if (selectedCount != baseCount) ...[
            const SizedBox(height: 4),
            Text(
              '絞り込み前：$baseCount問',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (widget.onlyQuestionIds != null) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text('間違えた問題だけ'),
              ),
            ),
          ],
          if (widget.onlyQuestionIds == null) ...[
            const SizedBox(height: 24),
            Text(
              '学習範囲',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<QuestionProgressFilter>(
              key: const ValueKey('question-progress-filter'),
              initialValue: _progressFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: QuestionProgressFilter.values
                  .map(
                    (filter) => DropdownMenuItem<QuestionProgressFilter>(
                      value: filter,
                      child: Text(_progressFilterLabel(filter)),
                    ),
                  )
                  .toList(),
              onChanged: widget.deck.hasDuplicateQuestionIds
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _progressFilter = value;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Text(
              _progressFilterDescription(_progressFilter),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.deck.hasDuplicateQuestionIds) ...[
              const SizedBox(height: 8),
              Text(
                '問題IDが重複しているため、問題別の学習範囲は選択できません。'
                '重複ID：${widget.deck.duplicateQuestionIds.join('、')}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
          if (_availableCategories.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'カテゴリー',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _areAllCategoriesSelected
                      ? _clearAllCategories
                      : _selectAllCategories,
                  child: Text(
                    _areAllCategoriesSelected ? 'すべて解除' : 'すべて選択',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '勉強したいカテゴリーを選んでください',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableCategories.map((category) {
                final count = _categoryCount(category, appState);
                final selected = _selectedCategories.contains(category);

                return FilterChip(
                  label: Text('$category（$count問）'),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _selectedCategories.add(category);
                      } else {
                        _selectedCategories.remove(category);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (_selectedCategories.isEmpty)
              Text(
                'カテゴリーを1つ以上選択してください。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (selectedCount == 0)
              Text(
                'この学習範囲に該当する問題はありません。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              Text(
                '選択中：$selectedCount問',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
          const SizedBox(height: 24),
          Text(
            '出題数',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
            selected: <QuestionCountOption>{_countOption},
            onSelectionChanged: selectedCount == 0
                ? null
                : (values) {
                    setState(() {
                      _countOption = values.first;
                    });
                  },
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('シャッフル'),
            subtitle: const Text('問題の出題順をランダムにします'),
            value: _shuffle,
            onChanged: selectedCount == 0
                ? null
                : (value) {
                    setState(() {
                      _shuffle = value;
                    });
                  },
          ),
        ],
      ),
      bottomNavigationBar: BottomActionArea(
        child: FilledButton.icon(
          onPressed: selectedCount == 0 ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            selectedCount == 0 ? emptySelectionLabel : '開始',
          ),
        ),
      ),
    );
  }

  List<QuizQuestion> get _baseTargetQuestions {
    final allowedIds = widget.onlyQuestionIds?.toSet();

    return widget.deck.questions.where((question) {
      return allowedIds == null || allowedIds.contains(question.id);
    }).toList();
  }

  List<QuizQuestion> _progressTargetQuestions(AppState appState) {
    return _baseTargetQuestions.where((question) {
      final progress = appState.questionProgressFor(
        widget.deck.id,
        question.id,
      );

      return _progressFilter.includes(progress.status);
    }).toList();
  }

  List<QuizQuestion> _selectedTargetQuestions(AppState appState) {
    if (_selectedCategories.isEmpty) {
      return <QuizQuestion>[];
    }

    return _progressTargetQuestions(appState).where((question) {
      final categories = _categoriesOf(question);

      return categories.any(_selectedCategories.contains);
    }).toList();
  }

  List<String> _findAvailableCategories() {
    final questions = _baseTargetQuestions;
    final categories = <String>[];

    for (final category in _mainCategories) {
      final exists = questions.any(
        (question) => question.tags.contains(category),
      );

      if (exists) {
        categories.add(category);
      }
    }

    final hasOtherQuestions = questions.any(
      (question) => _mainCategories.every(
        (category) => !question.tags.contains(category),
      ),
    );

    if (hasOtherQuestions) {
      categories.add(_otherCategory);
    }

    return categories;
  }

  Set<String> _categoriesOf(QuizQuestion question) {
    final categories = _mainCategories.where(question.tags.contains).toSet();

    if (categories.isEmpty) {
      return <String>{_otherCategory};
    }

    return categories;
  }

  int _categoryCount(String category, AppState appState) {
    return _progressTargetQuestions(appState).where((question) {
      return _categoriesOf(question).contains(category);
    }).length;
  }

  bool get _areAllCategoriesSelected {
    return _availableCategories.isNotEmpty &&
        _selectedCategories.length == _availableCategories.length;
  }

  void _selectAllCategories() {
    setState(() {
      _selectedCategories
        ..clear()
        ..addAll(_availableCategories);
    });
  }

  void _clearAllCategories() {
    setState(() {
      _selectedCategories.clear();
    });
  }

  void _start() {
    final appState = context.read<AppState>();
    final selectedSource = _selectedTargetQuestions(appState);

    final questions = QuizEngine().buildQuestions(
      source: selectedSource,
      countOption: _countOption,
      shuffle: _shuffle,
      onlyQuestionIds: widget.onlyQuestionIds,
    );

    if (questions.isEmpty) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => QuizSessionState(
            deck: widget.deck,
            questions: questions,
            questionResultRecorder: (result) => appState.recordQuestionResult(
              widget.deck.id,
              result,
            ),
          ),
          child: const QuizScreen(),
        ),
      ),
    );
  }

  String _progressFilterLabel(QuestionProgressFilter filter) {
    return switch (filter) {
      QuestionProgressFilter.all => 'すべて',
      QuestionProgressFilter.unanswered => '未回答',
      QuestionProgressFilter.incorrect => '間違えた問題',
      QuestionProgressFilter.unmastered => '未習得',
    };
  }

  String _progressFilterDescription(QuestionProgressFilter filter) {
    return switch (filter) {
      QuestionProgressFilter.all => 'デッキ内のすべての問題を対象にします。',
      QuestionProgressFilter.unanswered => 'まだ一度も回答していない問題を対象にします。',
      QuestionProgressFilter.incorrect => '最新の回答が不正解の問題を対象にします。',
      QuestionProgressFilter.unmastered => '未回答、または最新の回答が不正解の問題を対象にします。',
    };
  }
}
