import 'dart:convert';
import 'dart:js_interop';

import 'package:idb_shim/idb_client_native.dart';
import 'package:web/web.dart' as web;

import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/services/backup_browser_web.dart';
import 'package:personal_quiz_study/services/backup_sandbox_service.dart';
import 'package:personal_quiz_study/services/backup_service.dart';
import 'package:personal_quiz_study/services/live_restore_service.dart';
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

    final live = BrowserLiveRestoreStore();
    final beforeRestore = (await BackupService(live).capture('退避')).backup;
    final targetSnapshot = BackupSnapshot(preferences: {
      ...replacePreference(plain, 'study_cycles', null).preferences,
      '${backupPreferencePrefix}future-absent': null,
      '${backupPreferencePrefix}future-value': ' 原文\n未知の値 ',
    });
    final target = fixtureDocument(targetSnapshot);
    await LiveRestoreService(live)
        .restore(target, beforeRestore, confirmed: true);
    require(
        sameBackupContents(await live.read(), targetSnapshot), '本番形式の完全置換不一致');
    require(!(await names()).contains(backupAudioDatabase), '音声DB不在に戻っていない');
    require(storage.getItem('unrelated-test-sentinel') == 'unchanged',
        '無関係キーを変更した');
    require(await live.readRecovery() == null, '成功後に未完了退避が残った');
    checks.add('本番アダプターで完全置換・未作成キー・未知キー・DB不在・再読込一致');

    final safety = (await BackupService(live).capture('退避')).backup;
    final failing = FailingBrowserRestoreStore();
    var failed = false;
    try {
      await LiveRestoreService(failing)
          .restore(selected, safety, confirmed: true);
    } catch (_) {
      failed = true;
    }
    require(failed && sameBackupContents(await live.read(), safety.snapshot),
        '書込後エラーのロールバック不一致');
    require(await live.readRecovery() == null, '正常なロールバック後に退避が残った');
    checks.add('実保存後の注入エラーから元の原文・音声DB不在へロールバック');

    // Persist the same journal and partial state left by an interrupted page.
    await live.exclusively(() async {
      await live.saveRecovery(safety);
      await live.replace(BackupSnapshot(
          preferences: safety.snapshot.preferences,
          audio: selected.snapshot.audio,
          audioDatabaseVersion: selected.snapshot.audioDatabaseVersion));
    });
    var startupBlocked = false;
    try {
      await guardStudyStartup();
    } catch (_) {
      startupBlocked = true;
    }
    require(startupBlocked, '未完了の復元で通常学習が開始された');
    await LiveRestoreService(BrowserLiveRestoreStore()).recover();
    require(
        sameBackupContents(await live.read(), safety.snapshot), '中断後の復旧不一致');
    require(await live.readRecovery() == null, '復旧後に未完了退避が残った');
    checks.add('永続退避を新インスタンスで検出・通常起動停止・復旧して完全一致');

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
    await idbFactoryNative.deleteDatabase(backupAudioDatabase);
    await guardStudyStartup();
    var exclusiveRefused = false;
    try {
      await LiveRestoreService(live).restore(selected, safety, confirmed: true);
    } catch (_) {
      exclusiveRefused = true;
    }
    require(exclusiveRefused && await live.readRecovery() == null,
        '学習中の排他復元を拒否できていない');
    require(sameBackupContents(await live.read(), safety.snapshot),
        '排他拒否時にデータが変わった');
    checks.add('通常学習の共有ロック中は本番復元を拒否・元データ不変');
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

class FailingBrowserRestoreStore extends BrowserLiveRestoreStore {
  bool failOnce = true;
  @override
  Future<void> replace(BackupSnapshot snapshot) async {
    if (failOnce) {
      failOnce = false;
      final previous = await read();
      await super.replace(BackupSnapshot(
          preferences: previous.preferences,
          audio: snapshot.audio,
          audioDatabaseVersion: snapshot.audioDatabaseVersion));
      throw StateError('test-only failure between audio and preferences');
    }
    await super.replace(snapshot);
  }
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
