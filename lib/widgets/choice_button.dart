import 'package:flutter/material.dart';

class ChoiceButton extends StatelessWidget {
  const ChoiceButton({
    super.key,
    required this.label,
    required this.index,
    required this.onPressed,
    this.isAnswered = false,
    this.isSelected = false,
    this.isCorrect = false,
  });

  final String label;
  final int index;
  final VoidCallback? onPressed;
  final bool isAnswered;
  final bool isSelected;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Color? background;
    Color? foreground;
    IconData? icon;

    if (isAnswered && isCorrect) {
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
      icon = Icons.check_circle;
    } else if (isAnswered && isSelected) {
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      icon = Icons.cancel;
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          disabledForegroundColor: foreground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: isAnswered ? null : onPressed,
        icon: Icon(icon ?? Icons.circle_outlined),
        label: Text(
          '${index + 1}. $label',
          style: const TextStyle(fontSize: 16, height: 1.35),
        ),
      ),
    );
  }
}
