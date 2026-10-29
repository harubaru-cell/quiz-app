import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'backup_main.dart' show BackupApp;
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Backup-only mode reads raw data before AppState.load() can migrate anything.
  if (Uri.base.queryParameters['backup'] == '1') {
    runApp(const BackupApp());
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
