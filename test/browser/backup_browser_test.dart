@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_native.dart';
import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/services/backup_browser_web.dart';
import 'package:personal_quiz_study/services/backup_sandbox_service.dart';
import 'package:personal_quiz_study/services/backup_service.dart';
import 'package:web/web.dart' as web;

import '../support/backup_fixtures.dart';

void main() {
  setUpAll(() {
    // These tests may write fixture data ONLY in Flutter's disposable test
    // browser origin, never a production page or an existing browser profile.
    expect(Uri.base.host, anyOf('localhost', '127.0.0.1'));
  });
  setUp(() async {
    for (final key in backupPreferenceKeys) {
      web.window.localStorage.removeItem(key);
    }
    await idbFactoryNative.deleteDatabase(backupAudioDatabase);
  });
  tearDown(() async {
    for (final key in backupPreferenceKeys) {
      web.window.localStorage.removeItem(key);
    }
    web.window.localStorage.removeItem('unrelated-test-sentinel');
    await idbFactoryNative.deleteDatabase(backupAudioDatabase);
  });

  test('実ブラウザで原文を読み、存在しない音声DBは作成しない', () async {
    final expected = backupFixture();
    seedPreferences(expected);
    final beforeNames = await databaseNames();
    final captured =
        await BackupService(BrowserBackupSource()).capture('Chrome test');
    expect(captured.backup.snapshot.digest, expected.digest);
    expect(captured.validation.errors, isEmpty);
    expect(await databaseNames(), beforeNames);
    expect(web.window.localStorage.getItem('unrelated-test-sentinel'),
        'unchanged');
    for (final entry in expected.preferences.entries) {
      expect(web.window.localStorage.getItem(entry.key), entry.value);
    }
  });

  test('実IndexedDBで音声込みの読取・隔離復元・再読込・隔離DB削除を確認', () async {
    final expected = backupFixture(withAudio: true);
    seedPreferences(expected);
    final original = await idbFactoryNative.open(backupAudioDatabase,
        version: 1,
        onUpgradeNeeded: (event) =>
            event.database.createObjectStore(backupAudioStore));
    final transaction =
        original.transaction(backupAudioStore, idbModeReadWrite);
    await transaction
        .objectStore(backupAudioStore)
        .put(expected.audio.values.single, expected.audio.keys.single);
    await transaction.completed;
    original.close();
    final source = BrowserBackupSource();
    final captured = await BackupService(source).capture('Chrome test');
    final selected = QuizBackup.decode(captured.backup.encode());
    final result =
        await BackupSandboxService(idbFactoryNative).verify(selected, source);
    expect(result.sourceUnchanged, isTrue);
    expect(result.snapshotDigest, expected.digest);
    expect((await source.read()).digest, expected.digest);
    final names = await databaseNames();
    expect(names, contains(backupAudioDatabase));
    expect(names, isNot(contains(result.databaseName)));
    expect(web.window.localStorage.getItem('unrelated-test-sentinel'),
        'unchanged');
  });

  test('未知の音声ストアを省略して完全バックアップにしない', () async {
    seedPreferences(backupFixture());
    final database = await idbFactoryNative
        .open(backupAudioDatabase, version: 1, onUpgradeNeeded: (event) {
      event.database.createObjectStore(backupAudioStore);
      event.database.createObjectStore('future-store');
    });
    database.close();
    await expectLater(
        BackupService(BrowserBackupSource()).capture('Chrome test'),
        throwsStateError);
    final check = await idbFactoryNative.open(backupAudioDatabase);
    expect(check.objectStoreNames, contains('future-store'));
    check.close();
  });
}

void seedPreferences(BackupSnapshot snapshot) {
  for (final entry in snapshot.preferences.entries) {
    if (entry.value != null) {
      web.window.localStorage.setItem(entry.key, entry.value!);
    }
  }
  web.window.localStorage.setItem('unrelated-test-sentinel', 'unchanged');
}

Future<List<String>> databaseNames() async {
  final databases = (await web.window.indexedDB.databases().toDart).toDart;
  final names = databases.map((database) => database.name).toList();
  names.sort();
  return names;
}
