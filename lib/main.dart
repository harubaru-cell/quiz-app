import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'backup_main.dart' show BackupApp;
import 'state/app_state.dart';
import 'services/backup_browser.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Backup-only mode reads raw data before AppState.load() can migrate anything.
  if (Uri.base.queryParameters['backup'] == '1') {
    runApp(const BackupApp());
    return;
  }
  try {
    await guardStudyStartup();
  } catch (error) {
    runApp(MaterialApp(
        home: Scaffold(
      appBar: AppBar(title: const Text('保存データの保護')),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            SelectableText('学習は開始していません。\n$error'),
            const FilledButton(
                onPressed: openBackupOnly, child: Text('バックアップ専用画面を開く')),
          ])),
    )));
    return;
  }
  final appState = AppState();
  await appState.load();
  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const QuizStudyApp(),
    ),
  );
}
