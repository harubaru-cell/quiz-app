import 'package:flutter/material.dart';

import 'screens/backup_screen.dart';

/// Standalone entry: never constructs AppState or runs its legacy migrations.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BackupApp());
}

class BackupApp extends StatelessWidget {
  const BackupApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Quiz Study Backup',
        theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF256D85)),
            useMaterial3: true),
        darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF70A9A1),
                brightness: Brightness.dark),
            useMaterial3: true),
        home: const BackupScreen(),
      );
}
