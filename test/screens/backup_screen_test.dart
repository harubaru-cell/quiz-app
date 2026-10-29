import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:personal_quiz_study/screens/backup_screen.dart';
import 'package:personal_quiz_study/services/backup_browser.dart';
import 'package:personal_quiz_study/services/backup_sandbox_service.dart';

import '../support/backup_fixtures.dart';

void main() {
  testWidgets('再取得に失敗した後に以前のデータを新規バックアップとして保存させない', (tester) async {
    final source = FixtureBackupSource(backupFixture());
    final downloads = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      source: source,
      sandbox: BackupSandboxService(newIdbFactoryMemory()),
      downloadFactory: (bytes) => FixtureDownload(bytes, downloads),
    )));
    await tester.tap(find.byKey(const ValueKey('prepare-backup')));
    await tester.pumpAndSettle();
    source.failure = StateError('read denied');
    await tester.tap(find.byKey(const ValueKey('prepare-backup')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('download-backup')))
            .onPressed,
        isNull);
    expect(downloads, isEmpty);
  });

  testWidgets('小さい画面でも作成操作・診断へスクロールできる', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      source: FixtureBackupSource(backupFixture()),
      sandbox: BackupSandboxService(newIdbFactoryMemory()),
      downloadFactory: (bytes) => FixtureDownload(bytes, []),
    )));
    await tester.ensureVisible(find.byKey(const ValueKey('prepare-backup')));
    await tester.tap(find.byKey(const ValueKey('prepare-backup')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('保存内容の診断'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('保存内容の診断'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存の依頼とファイル再読込を区別し、選択前は復元できない', (tester) async {
    final source = FixtureBackupSource(backupFixture());
    final downloads = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      source: source,
      sandbox: BackupSandboxService(newIdbFactoryMemory()),
      downloadFactory: (bytes) => FixtureDownload(bytes, downloads),
    )));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('verify-backup')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('prepare-backup')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ファイルはまだ保存していません'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('download-backup')));
    await tester.pump();
    expect(downloads.single, endsWith('.quiz-backup.json'));
    expect(find.textContaining('保存完了はまだ未確認'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('verify-backup')))
            .onPressed,
        isNull);
    expect(source.readCount, 2);
  });

  testWidgets('整合性エラーのある選択ファイルは復元できず、原文診断を表示', (tester) async {
    final snapshot = replacePreference(backupFixture(), 'histories', 'broken');
    final source = FixtureBackupSource(backupFixture());
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      source: source,
      sandbox: BackupSandboxService(newIdbFactoryMemory()),
      pickFile: () async => fixtureDocument(snapshot).encode(),
    )));
    await tester.tap(find.byKey(const ValueKey('load-backup')));
    await tester.pumpAndSettle();
    expect(find.textContaining('隔離復元はまだ実行していません'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('verify-backup')))
            .onPressed,
        isNull);
    expect(source.readCount, 0);
  });

  testWidgets('破損ファイル選択後に以前の正常ファイルを復元対象として残さない', (tester) async {
    var first = true;
    final source = FixtureBackupSource(backupFixture());
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      source: source,
      sandbox: BackupSandboxService(newIdbFactoryMemory()),
      pickFile: () async {
        if (first) {
          first = false;
          return fixtureDocument(source.snapshot).encode();
        }
        return Uint8List.fromList([123]);
      },
    )));
    await tester.tap(find.byKey(const ValueKey('load-backup')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('verify-backup')))
            .onPressed,
        isNotNull);
    await tester.ensureVisible(find.byKey(const ValueKey('load-backup')));
    await tester.tap(find.byKey(const ValueKey('load-backup')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('verify-backup')))
            .onPressed,
        isNull);
    expect(source.readCount, 0);
  });
}

class FixtureDownload extends BackupDownload {
  FixtureDownload(super.bytes, this.downloads);
  final List<String> downloads;
  @override
  void save(String filename) => downloads.add(filename);
}
