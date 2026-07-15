import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/quiz_deck.dart';
import '../state/app_state.dart';
import '../widgets/deck_card.dart';
import '../widgets/empty_state.dart';
import 'deck_settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String _appVersion = '1.4';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final message = appState.message;

        if (message != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
              ),
            );

            context.read<AppState>().clearMessage();
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('クイズ学習'),
            actions: [
              IconButton(
                tooltip: 'JSON・ZIPファイル追加',
                onPressed: appState.importDeckFromFile,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: appState.isLoading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : appState.decks.isEmpty
                  ? EmptyState(
                      onImport: appState.importDeckFromFile,
                    )
                  : RefreshIndicator(
                      onRefresh: appState.load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          24,
                        ),
                        itemCount: appState.decks.length,
                        itemBuilder: (context, index) {
                          final deck = appState.decks[index];

                          return DeckCard(
                            deck: deck,
                            stats: appState.statsFor(deck.id),
                            onTap: () => _openDeck(
                              context,
                              deck,
                            ),
                            onDelete: () => _confirmDelete(
                              context,
                              deck,
                            ),
                          );
                        },
                      ),
                    ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                8,
                16,
                10,
              ),
              child: Text(
                'アプリ Ver.$_appVersion',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          floatingActionButton: appState.decks.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: appState.importDeckFromFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('JSON・ZIP追加'),
                ),
        );
      },
    );
  }

  void _openDeck(
    BuildContext context,
    QuizDeck deck,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeckSettingsScreen(
          deck: deck,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    QuizDeck deck,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('デッキを削除しますか？'),
        content: Text(
          '「${deck.title}」と学習履歴、保存された音声を'
          'この端末から削除します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (shouldDelete == true && context.mounted) {
      await context.read<AppState>().deleteDeck(
            deck.id,
          );
    }
  }
}
