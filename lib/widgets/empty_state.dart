import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.onImport,
  });

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.quiz_outlined,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              'クイズデッキを追加してください',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'JSONファイル、または音声付きのZIPファイルを読み込むと、'
              'ここにデッキが表示されます。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'JSONは通常の4択・記述式問題、'
              'ZIPはJSONと音声をまとめたデッキに対応しています。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('JSON・ZIPを追加'),
            ),
          ],
        ),
      ),
    );
  }
}
