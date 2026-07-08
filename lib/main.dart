import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.load();
  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const QuizStudyApp(),
    ),
  );
}
