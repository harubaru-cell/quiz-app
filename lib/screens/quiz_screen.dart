import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
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

                if (session.answered) ...[
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
