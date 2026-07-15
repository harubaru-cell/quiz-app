import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/question_progress.dart';
import '../models/quiz_deck.dart';
import '../models/quiz_question.dart';
import '../models/quiz_session.dart';
import '../models/study_cycle.dart';
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
  bool _isStartingStudy = false;

  late final List<String> _availableCategories;
  late final Set<String> _selectedCategories;
  late final String _deckSignature;

  @override
  void initState() {
    super.initState();

    _shuffle = widget.initialShuffle;
    _deckSignature = widget.deck.contentSignature;
    _availableCategories = _findAvailableCategories();
    _selectedCategories = _availableCategories.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final baseQuestions = _baseTargetQuestions;
    final selectedQuestions = _selectedTargetQuestions(appState);
    final studyCycle = widget.onlyQuestionIds == null
        ? appState.studyCycleFor(widget.deck.id)
        : null;
    final canResumeStudyCycle = studyCycle != null &&
        !studyCycle.isComplete &&
        _isStudyCycleCompatible(studyCycle);

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
          if (studyCycle != null) ...[
            const SizedBox(height: 16),
            _StudyCycleCard(
              cycle: studyCycle,
              isCompatible: _isStudyCycleCompatible(studyCycle),
              isStarting: _isStartingStudy,
              onContinue: canResumeStudyCycle
                  ? () => _continueStudyCycle(studyCycle)
                  : null,
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
          onPressed: selectedCount == 0 || _isStartingStudy
              ? null
              : () => _start(studyCycle),
          icon: Icon(
            _isStartingStudy ? Icons.sync : Icons.play_arrow,
          ),
          label: Text(
            selectedCount == 0
                ? emptySelectionLabel
                : _startButtonLabel(studyCycle),
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

  Future<void> _start(StudyCycle? existingCycle) async {
    if (_isStartingStudy) {
      return;
    }

    setState(() {
      _isStartingStudy = true;
    });

    var navigated = false;

    try {
      final appState = context.read<AppState>();
      final selectedSource = _selectedTargetQuestions(appState);

      if (!_usesStudyCycle) {
        navigated = _openOneOffQuiz(appState, selectedSource);
        return;
      }

      if (existingCycle != null && !existingCycle.isComplete) {
        final shouldRestart = await _confirmStudyCycleRestart();

        if (shouldRestart != true || !mounted) {
          return;
        }
      }

      final orderedQuestions = QuizEngine().buildQuestions(
        source: selectedSource,
        countOption: QuestionCountOption.all,
        shuffle: _shuffle,
      );

      if (orderedQuestions.isEmpty) {
        return;
      }

      final orderedQuestionIds = orderedQuestions
          .map((item) => item.question.id)
          .toList(growable: false);
      final cycle = await appState.startStudyCycle(
        deckId: widget.deck.id,
        deckSignature: _deckSignature,
        orderedQuestionIds: orderedQuestionIds,
        batchSize: _countOption.limit ?? orderedQuestionIds.length,
      );

      if (!mounted) {
        return;
      }
      if (cycle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('一周学習を開始できませんでした。もう一度お試しください。'),
          ),
        );
        return;
      }

      navigated = _openStudyCycleQuiz(appState, cycle);
    } finally {
      if (mounted && !navigated) {
        setState(() {
          _isStartingStudy = false;
        });
      }
    }
  }

  Future<void> _continueStudyCycle(StudyCycle cycle) async {
    if (_isStartingStudy ||
        cycle.isComplete ||
        !_isStudyCycleCompatible(cycle)) {
      return;
    }

    setState(() {
      _isStartingStudy = true;
    });

    final appState = context.read<AppState>();
    final navigated = _openStudyCycleQuiz(appState, cycle);

    if (mounted && !navigated) {
      setState(() {
        _isStartingStudy = false;
      });
    }
  }

  bool _openOneOffQuiz(
    AppState appState,
    List<QuizQuestion> selectedSource,
  ) {
    final questions = QuizEngine().buildQuestions(
      source: selectedSource,
      countOption: _countOption,
      shuffle: _shuffle,
      onlyQuestionIds: widget.onlyQuestionIds,
    );

    if (questions.isEmpty) {
      return false;
    }

    _navigateToQuiz(
      questions: questions,
      recorder: (result) => appState.recordQuestionResult(
        widget.deck.id,
        result,
      ),
    );
    return true;
  }

  bool _openStudyCycleQuiz(
    AppState appState,
    StudyCycle cycle,
  ) {
    final questionsById = <String, QuizQuestion>{
      for (final question in widget.deck.questions) question.id: question,
    };
    final source = <QuizQuestion>[];

    for (final questionId in cycle.nextBatchQuestionIds) {
      final question = questionsById[questionId];

      if (question == null) {
        return false;
      }

      source.add(question);
    }

    final questions = QuizEngine().buildQuestions(
      source: source,
      countOption: QuestionCountOption.all,
      shuffle: false,
    );

    if (questions.isEmpty) {
      return false;
    }

    _navigateToQuiz(
      questions: questions,
      recorder: (result) => appState.recordStudyCycleQuestionResult(
        deckId: widget.deck.id,
        cycleId: cycle.cycleId,
        result: result,
      ),
    );
    return true;
  }

  void _navigateToQuiz({
    required List<QuizSessionQuestion> questions,
    required QuestionResultRecorder recorder,
  }) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => QuizSessionState(
            deck: widget.deck,
            questions: questions,
            questionResultRecorder: recorder,
          ),
          child: const QuizScreen(),
        ),
      ),
    );
  }

  Future<bool?> _confirmStudyCycleRestart() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しい一周を始めますか？'),
        content: const Text(
          '現在の一周の位置はリセットされます。問題別の回答履歴と進捗は残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('新しい一周を開始'),
          ),
        ],
      ),
    );
  }

  bool get _usesStudyCycle {
    return widget.onlyQuestionIds == null &&
        !widget.deck.hasDuplicateQuestionIds;
  }

  bool _isStudyCycleCompatible(StudyCycle cycle) {
    if (widget.deck.hasDuplicateQuestionIds || cycle.deckId != widget.deck.id) {
      return false;
    }
    if (cycle.deckSignature != _deckSignature) {
      return false;
    }

    final currentQuestionIds =
        widget.deck.questions.map((question) => question.id).toSet();

    return cycle.orderedQuestionIds.every(currentQuestionIds.contains);
  }

  String _startButtonLabel(StudyCycle? cycle) {
    if (_isStartingStudy) {
      return '準備中';
    }
    if (!_usesStudyCycle) {
      return '開始';
    }

    return cycle == null ? '一周学習を開始' : '新しい一周を開始';
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

class _StudyCycleCard extends StatelessWidget {
  const _StudyCycleCard({
    required this.cycle,
    required this.isCompatible,
    required this.isStarting,
    required this.onContinue,
  });

  final StudyCycle cycle;
  final bool isCompatible;
  final bool isStarting;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final completedCount = cycle.completedCount;
    final totalCount = cycle.orderedQuestionIds.length;

    return Card(
      key: const ValueKey('study-cycle-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  cycle.isComplete
                      ? Icons.check_circle_outline
                      : Icons.route_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cycle.isComplete ? '一周完了' : '一周学習の続き',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('$completedCount / $totalCount問 完了'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: totalCount == 0 ? 0 : completedCount / totalCount,
            ),
            const SizedBox(height: 8),
            Text(
              cycle.isComplete
                  ? '全問題に一度回答しました。新しい一周は下のボタンから開始できます。'
                  : '残り${cycle.remainingCount}問。次は最大${cycle.batchSize}問の区切りを進めます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!cycle.isComplete && !isCompatible) ...[
              const SizedBox(height: 8),
              Text(
                'デッキ内容が変更されているため、この一周は再開できません。新しい一周を開始してください。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (!cycle.isComplete && isCompatible) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const ValueKey('continue-study-cycle'),
                onPressed: isStarting ? null : onContinue,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  '続きから学習（${cycle.nextBatchQuestionIds.length}問）',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
