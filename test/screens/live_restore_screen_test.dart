import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/screens/backup_screen.dart';
import 'package:personal_quiz_study/services/backup_browser.dart';
import 'package:personal_quiz_study/services/backup_sandbox_service.dart';
import 'package:personal_quiz_study/services/live_restore_service.dart';
import '../support/backup_fixtures.dart';

void main() {
  testWidgets('退避の保存再確認・キャンセル・明示確認後の完全復元を区別する', (tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _ScreenRestoreStore(backupFixture(withAudio: true));
    final original = store.snapshot;
    final target = fixtureDocument(
        replacePreference(backupFixture(), 'study_cycles', null));
    Uint8List? saved;
    Uint8List? file;
    await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
      allowLiveRestore: true,
      source: store,
      restoreStore: store,
      sandbox: BackupSandboxService(newIdbFactoryMemory()),
      downloadFactory: (bytes) => _Download(bytes, () => saved = bytes),
      pickFile: () async => file,
    )));
    await tester.pumpAndSettle();
    OutlinedButton restoreButton() => tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('live-restore')));
    expect(restoreButton().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('prepare-backup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('download-backup')));
    await tester.pumpAndSettle();
    file = saved;
    await tester.tap(find.byKey(const ValueKey('verify-safety-file')));
    await tester.pumpAndSettle();
    file = target.encode();
    await tester.tap(find.byKey(const ValueKey('load-backup')));
    await tester.pumpAndSettle();
    expect(restoreButton().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('live-restore')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-live-restore')))
            .onPressed,
        isNull);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    expect(store.pending, isNull);
    expect(sameBackupContents(store.snapshot, original), isTrue);
    await tester.tap(find.byKey(const ValueKey('live-restore')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('restore-acknowledge')));
    await tester.tap(find.byKey(const ValueKey('restore-acknowledge')));
    await tester.ensureVisible(find.byKey(const ValueKey('restore-phrase')));
    await tester.enterText(
        find.byKey(const ValueKey('restore-phrase')), '復元する');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-live-restore')));
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(sameBackupContents(store.snapshot, target.snapshot), isTrue);
    expect(store.pending, isNull);
    expect(find.textContaining('本番復元が完了しました'), findsOneWidget);
  });
}

class _ScreenRestoreStore extends FixtureBackupSource
    implements LiveRestoreStore {
  _ScreenRestoreStore(super.snapshot);
  QuizBackup? pending;
  int writes = 0;
  @override
  Future<QuizBackup?> readRecovery() async => pending;
  @override
  Future<void> saveRecovery(QuizBackup backup) async => pending = backup;
  @override
  Future<void> clearRecovery() async => pending = null;
  @override
  Future<void> replace(BackupSnapshot value) async {
    writes++;
    snapshot = value;
  }

  @override
  Future<void> exclusively(Future<void> Function() action) => action();
}

class _Download extends BackupDownload {
  _Download(super.bytes, this.onSave);
  final VoidCallback onSave;
  @override
  void save(String filename) => onSave();
}
