import 'dart:convert';
import 'dart:js_interop';

import 'package:idb_shim/idb_client_native.dart';
import 'package:web/web.dart' as web;

import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/services/backup_browser_web.dart';
import 'package:personal_quiz_study/services/backup_sandbox_service.dart';
import 'package:personal_quiz_study/services/backup_service.dart';
import '../test/support/backup_fixtures.dart';

/// Plain Dart browser test of the production storage adapters. It deliberately
/// does not initialize Flutter's rendering engine or use a personal profile.
Future<void> main() async {
  final checks = <String>[];
  final report = <String, Object?>{'passed': false, 'checks': checks};
  try {
    require(Uri.base.host == '127.0.0.1', '専用ループバックサーバー以外では実行しません。');
    final storage = web.window.localStorage;
    require(storage.length == 0 && (await names()).isEmpty,
        '使い捨ての空のプロファイルが必要です。既存データには触れません。');
    storage.setItem('unrelated-test-sentinel', 'unchanged');

    final plain = backupFixture();
    seed(plain);
    final source = BrowserBackupSource();
    final captured =
        await BackupService(source).capture('disposable Chrome test');
    require(captured.backup.snapshot.digest == plain.digest, '原文の読取不一致');
    require((await names()).isEmpty, '存在しない元音声DBが作成された');
    checks.add('原文一致・不在の元音声DBを作成しない');

    final audio = backupFixture(withAudio: true);
    seed(audio);
    var database = await idbFactoryNative.open(backupAudioDatabase,
        version: 1,
        onUpgradeNeeded: (event) =>
            event.database.createObjectStore(backupAudioStore));
    final transaction =
        database.transaction(backupAudioStore, idbModeReadWrite);
    await transaction
        .objectStore(backupAudioStore)
        .put(audio.audio.values.single, audio.audio.keys.single);
    await transaction.completed;
    database.close();
    final audioBackup =
        await BackupService(source).capture('disposable Chrome test');
    final selected = QuizBackup.decode(audioBackup.backup.encode());
    final restored =
        await BackupSandboxService(idbFactoryNative).verify(selected, source);
    require(restored.sourceUnchanged && restored.snapshotDigest == audio.digest,
        '隔離復元または元データの不変性が不一致');
    require((await source.read()).digest == audio.digest, '元保存データが変化した');
    require(!(await names()).contains(restored.databaseName), '隔離DBが残っている');
    require(storage.getItem('unrelated-test-sentinel') == 'unchanged',
        '対象外データが変化した');
    checks.add('実IndexedDBで音声込み復元・再オープン・元データ不変・検証DB削除');

    await idbFactoryNative.deleteDatabase(backupAudioDatabase);
    database = await idbFactoryNative.open(backupAudioDatabase, version: 1,
        onUpgradeNeeded: (event) {
      event.database.createObjectStore(backupAudioStore);
      event.database.createObjectStore('future-store');
    });
    database.close();
    var refused = false;
    try {
      await BackupService(source).capture('disposable Chrome test');
    } on StateError {
      refused = true;
    }
    require(refused, '未知のストアを省略して成功扱いした');
    database = await idbFactoryNative.open(backupAudioDatabase);
    require(database.objectStoreNames.contains('future-store'), '元スキーマが変化した');
    database.close();
    checks.add('未知の音声ストアを省略せず拒否・元スキーマ維持');
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  }
  final encoded = jsonEncode(report);
  web.document.body!.textContent = encoded;
  await web.window
      .fetch(
          '/result'.toJS, web.RequestInit(method: 'POST', body: encoded.toJS))
      .toDart;
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void seed(BackupSnapshot snapshot) {
  for (final entry in snapshot.preferences.entries) {
    if (entry.value != null) {
      web.window.localStorage.setItem(entry.key, entry.value!);
    }
  }
}

Future<List<String>> names() async =>
    (await web.window.indexedDB.databases().toDart)
        .toDart
        .map((database) => database.name)
        .toList();
