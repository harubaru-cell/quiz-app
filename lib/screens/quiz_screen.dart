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

        return Scaffold(
          appBar: AppBar(
            title: Text(
              '${session.currentIndex + 1} / ${session.totalCount}',
            ),
            actions: [
              TextButton(
                onPressed: () => _finishEarly(context, session),
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
                    onPressed: () => session.answer(index),
                  ),
                  const SizedBox(height: 10),
                ],

              // 記述式問題
              if (question.type == QuestionType.textInput)
                _TextInputAnswer(
                  key: ValueKey(question.id),
                  session: session,
                ),

              if (session.answered) ...[
                const SizedBox(height: 16),
                _AnswerPanel(session: session),
              ],
            ],
          ),
          bottomNavigationBar: session.answered
              ? BottomActionArea(
                  child: FilledButton.icon(
                    onPressed: () => _nextOrFinish(
                      context,
                      session,
                    ),
                    icon: Icon(
                      session.isLastQuestion ? Icons.flag : Icons.navigate_next,
                    ),
                    label: Text(
                      session.isLastQuestion ? '結果を見る' : '次へ',
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Future<void> _nextOrFinish(
    BuildContext context,
    QuizSessionState session,
  ) async {
    if (session.moveNext()) {
      return;
    }

    final history = session.finish(completed: true);

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
  }

  Future<void> _finishEarly(
    BuildContext context,
    QuizSessionState session,
  ) async {
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

    final history = session.finish(completed: false);

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
    return !widget.session.answered && _controller.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_canSubmit) {
      return;
    }

    FocusScope.of(context).unfocus();

    widget.session.answerText(_controller.text);
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
          enabled: !widget.session.answered,
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
                'あなたの回答: ${session.textAnswer}',
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
                '正解: ${item.question.answers.first}',
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
