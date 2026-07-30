import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/quiz_history.dart';
import '../models/quiz_question.dart';
import '../state/app_state.dart';
import '../state/quiz_session_state.dart';
import '../widgets/bottom_action_area.dart';
import '../widgets/choice_button.dart';
import '../widgets/question_audio_button.dart';
import 'result_screen.dart';

class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<QuizSessionState>(
      builder: (context, session, _) {
        if (!session.hasQuestions) {
          return Scaffold(
            appBar: AppBar(title: const Text('クイズ')),
            body: const Center(
              child: Text('出題できる問題がありません。'),
            ),
          );
        }

        final item = session.currentQuestion;
        final question = item.question;

        return PopScope<void>(
          canPop: !session.isSavingProgress && !session.isFinalizing,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                '${session.currentIndex + 1} / ${session.totalCount}',
              ),
              actions: [
                TextButton(
                  onPressed: session.isSavingProgress || session.isFinalizing
                      ? null
                      : () => _finishEarly(context, session),
                  child: const Text('途中終了'),
                ),
              ],
            ),
            body: ListView(
              key: ValueKey(
                'quiz-scroll-view-${session.currentIndex}-${question.id}',
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (question.type == QuestionType.flashcard)
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: _FlashcardQuestion(session: session),
                    ),
                  )
                else ...[
                  Text(
                    question.question,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(height: 1.45),
                  ),

                  if (question.audio != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: QuestionAudioButton(
                        audioPath: question.audio!,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 4択問題
                  if (question.type == QuestionType.multipleChoice)
                    for (var index = 0;
                        index < item.displayChoices.length;
                        index++) ...[
                      ChoiceButton(
                        index: index,
                        label: item.displayChoices[index],
                        isAnswered: session.answered,
                        isSelected: session.selectedIndex == index,
                        isCorrect: item.correctIndex == index,
                        onPressed: session.isFinalizing
                            ? null
                            : () async {
                                await session.answer(index);
                              },
                      ),
                      const SizedBox(height: 10),
                    ],

                  // 記述式問題
                  if (question.type == QuestionType.textInput)
                    _TextInputAnswer(
                      key: ValueKey(question.id),
                      session: session,
                    ),
                ],
                if (session.saveError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    session.saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (session.answered &&
                    question.type != QuestionType.flashcard) ...[
                  const SizedBox(height: 16),
                  _AnswerPanel(session: session),
                ],
              ],
            ),
            bottomNavigationBar: session.answered
                ? BottomActionArea(
                    child: FilledButton.icon(
                      onPressed:
                          session.isSavingProgress || session.isFinalizing
                              ? null
                              : () => _nextOrFinish(
                                    context,
                                    session,
                                  ),
                      icon: Icon(
                        session.isSavingProgress || session.isFinalizing
                            ? Icons.sync
                            : session.isLastQuestion
                                ? Icons.flag
                                : Icons.navigate_next,
                      ),
                      label: Text(
                        session.isSavingProgress
                            ? '進捗を保存中'
                            : session.isFinalizing
                                ? '結果を保存中'
                                : session.isLastQuestion
                                    ? '結果を見る'
                                    : '次へ',
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _nextOrFinish(
    BuildContext context,
    QuizSessionState session,
  ) async {
    if (!session.answered || session.isSavingProgress || session.isFinalizing) {
      return;
    }

    if (session.moveNext()) {
      return;
    }

    if (!session.beginFinalization()) {
      return;
    }

    final history = session.finish(completed: true);

    try {
      await context.read<AppState>().recordHistory(history);

      if (!context.mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            deck: session.deck,
            history: history,
          ),
        ),
      );
    } catch (_) {
      session.endFinalization();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('結果を保存できませんでした。もう一度お試しください。'),
          ),
        );
      }
    }
  }

  Future<void> _finishEarly(
    BuildContext context,
    QuizSessionState session,
  ) async {
    if (session.isSavingProgress || session.isFinalizing) {
      return;
    }

    if (session.answeredCount == 0) {
      Navigator.of(context).pop();
      return;
    }

    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('途中終了しますか？'),
        content: const Text(
          'ここまでの結果を学習履歴として保存します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('終了'),
          ),
        ],
      ),
    );

    if (shouldFinish != true || !context.mounted) {
      return;
    }

    if (!session.beginFinalization()) {
      return;
    }

    final history = session.finish(completed: false);

    try {
      await context.read<AppState>().recordHistory(history);

      if (!context.mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            deck: session.deck,
            history: history,
          ),
        ),
      );
    } catch (_) {
      session.endFinalization();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('結果を保存できませんでした。もう一度お試しください。'),
          ),
        );
      }
    }
  }
}

class _FlashcardQuestion extends StatelessWidget {
  const _FlashcardQuestion({
    required this.session,
  });

  final QuizSessionState session;

  @override
  Widget build(BuildContext context) {
    final question = session.currentQuestion.question;
    final answer = question.flashcardAnswer!;
    final isInteractionDisabled =
        session.answered || session.isSavingProgress || session.isFinalizing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlashcardContentCard(
          key: const ValueKey('flashcard-case-card'),
          title: '事案の概要',
          content: question.question,
          icon: Icons.description_outlined,
        ),
        const SizedBox(height: 16),
        if (!session.flashcardAnswerRevealed)
          FilledButton.icon(
            key: const ValueKey('show-flashcard-answer'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed:
                isInteractionDisabled ? null : session.revealFlashcardAnswer,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('答えを見る'),
          )
        else ...[
          _FlashcardContentCard(
            key: const ValueKey('flashcard-answer-card'),
            title: '模範解答',
            content: answer,
            icon: Icons.menu_book_outlined,
          ),
          if (question.explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FlashcardContentCard(
              key: const ValueKey('flashcard-explanation-card'),
              title: '解説・事件名',
              content: question.explanation,
              icon: Icons.info_outline,
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '自己評価',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            session.isSavingProgress
                ? '進捗を保存中です。'
                : session.answered
                    ? '選択した評価を保存しました。'
                    : '模範解答と照合して、理解度を選んでください。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _FlashcardRatingButton(
            key: const ValueKey('flashcard-rating-remembered'),
            label: '覚えた',
            icon: Icons.check_circle_outline,
            selected: session.flashcardRating == FlashcardRating.remembered,
            onPressed: isInteractionDisabled
                ? null
                : () => session.answerFlashcard(
                      FlashcardRating.remembered,
                    ),
          ),
          const SizedBox(height: 10),
          _FlashcardRatingButton(
            key: const ValueKey('flashcard-rating-unsure'),
            label: 'あやしい',
            icon: Icons.help_outline,
            selected: session.flashcardRating == FlashcardRating.unsure,
            onPressed: isInteractionDisabled
                ? null
                : () => session.answerFlashcard(
                      FlashcardRating.unsure,
                    ),
          ),
          const SizedBox(height: 10),
          _FlashcardRatingButton(
            key: const ValueKey('flashcard-rating-forgotten'),
            label: '覚えていない',
            icon: Icons.replay_outlined,
            selected: session.flashcardRating == FlashcardRating.forgotten,
            onPressed: isInteractionDisabled
                ? null
                : () => session.answerFlashcard(
                      FlashcardRating.forgotten,
                    ),
          ),
        ],
      ],
    );
  }
}

class _FlashcardContentCard extends StatelessWidget {
  const _FlashcardContentCard({
    super.key,
    required this.title,
    required this.content,
    required this.icon,
  });

  final String title;
  final String content;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              softWrap: true,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.65,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlashcardRatingButton extends StatelessWidget {
  const _FlashcardRatingButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          backgroundColor: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          foregroundColor: selected
              ? Theme.of(context).colorScheme.onSecondaryContainer
              : null,
          disabledBackgroundColor: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          disabledForegroundColor: selected
              ? Theme.of(context).colorScheme.onSecondaryContainer
              : null,
        ),
        onPressed: onPressed,
        icon: Icon(selected ? Icons.check_circle : icon),
        label: Text(
          selected ? '$label（選択済み）' : label,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class _TextInputAnswer extends StatefulWidget {
  const _TextInputAnswer({
    required this.session,
    super.key,
  });

  final QuizSessionState session;

  @override
  State<_TextInputAnswer> createState() => _TextInputAnswerState();
}

class _TextInputAnswerState extends State<_TextInputAnswer> {
  final TextEditingController _controller = TextEditingController();

  bool get _canSubmit {
    return !widget.session.answered &&
        !widget.session.isSavingProgress &&
        !widget.session.isFinalizing;
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }

    FocusScope.of(context).unfocus();

    await widget.session.answerText(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          enabled: _canSubmit,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '回答',
            hintText: '答えを入力してください',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            setState(() {});
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: const Icon(Icons.check),
          label: const Text('回答する'),
        ),
      ],
    );
  }
}

class _AnswerPanel extends StatelessWidget {
  const _AnswerPanel({
    required this.session,
  });

  final QuizSessionState session;

  @override
  Widget build(BuildContext context) {
    final item = session.currentQuestion;

    final isCorrect =
        session.results.isNotEmpty && session.results.last.isCorrect;

    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isCorrect
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCorrect ? '正解' : '不正解',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isCorrect
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            if (session.textAnswer != null) ...[
              Text(
                session.textAnswer!.trim().isEmpty
                    ? 'あなたの回答：未入力'
                    : 'あなたの回答：${session.textAnswer}',
              ),
              const SizedBox(height: 4),
            ],
            if (item.correctIndex != null)
              Text(
                '正解: ${item.correctIndex! + 1}. '
                '${item.displayChoices[item.correctIndex!]}',
              )
            else if (item.question.answers.isNotEmpty)
              Text(
                '正解候補：${item.question.answers.join(' / ')}',
              ),
            if (item.question.explanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(item.question.explanation),
            ],
          ],
        ),
      ),
    );
  }
}
