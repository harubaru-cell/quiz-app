import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:idb_shim/idb_client_native.dart';
import 'package:web/web.dart' as web;

import '../models/quiz_backup.dart';
import 'backup_sandbox_service.dart';
import 'backup_service.dart';
import 'live_restore_service.dart';

BackupSource createBrowserBackupSource() => BrowserBackupSource();
BackupSandboxService createBrowserBackupSandbox() =>
    BackupSandboxService(idbFactoryNative);
LiveRestoreStore createBrowserLiveRestoreStore() => BrowserLiveRestoreStore();

const _restoreLock = 'quiz-study-live-storage';
const _recoveryDatabase = 'quiz_study_restore_recovery_v1';

/// Hold a shared lock for the entire normal learning page lifetime. This also
/// covers cached AppState/SharedPreferences and the persistent audio connection.
Future<void> guardStudyStartup() async {
  if (web.window.navigator.getProperty<JSAny?>('locks'.toJS) == null) {
    if (await BrowserLiveRestoreStore().readRecovery() != null) {
      throw StateError('未完了の復元があります。対応ブラウザで復旧してください。');
    }
    // Browsers without Web Locks retain learning, but cannot perform restores.
    return;
  }
  final acquired = Completer<void>();
  final hold = Completer<JSAny?>();
  final lockReleased = web.window.navigator.locks
      .request(
          _restoreLock,
          web.LockOptions(mode: 'shared', ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null) {
              acquired.completeError(StateError('別のタブで復元・復旧中です。学習は開始できません。'));
              return Future<JSAny?>.value().toJS;
            }
            acquired.complete();
            return hold.future.toJS;
          }).toJS)
      .toDart
      .catchError((Object error) {
    if (!acquired.isCompleted) acquired.completeError(error);
    return null;
  });
  try {
    await acquired.future;
    if (await BrowserLiveRestoreStore().readRecovery() != null) {
      throw StateError('未完了の復元を検出しました。バックアップ専用画面で元データを復旧してください。');
    }
  } catch (_) {
    hold.complete();
    await lockReleased;
    rethrow;
  }
}

void openBackupOnly() {
  web.window.location.replace(Uri.base.replace(queryParameters: {
    ...Uri.base.queryParameters,
    'backup': '1',
  }).toString());
}

void reopenStudy() {
  final parameters = {...Uri.base.queryParameters}..remove('backup');
  web.window.location
      .replace(Uri.base.replace(queryParameters: parameters).toString());
}

class BrowserLiveRestoreStore extends BrowserBackupSource
    implements LiveRestoreStore {
  @override
  Future<void> exclusively(Future<void> Function() action) async {
    if (web.window.navigator.getProperty<JSAny?>('locks'.toJS) == null) {
      throw StateError('このブラウザは排他制御に対応していないため、本番復元・復旧は利用できません。');
    }
    Object? failure;
    StackTrace? failureStack;
    await web.window.navigator.locks
        .request(
            _restoreLock,
            web.LockOptions(mode: 'exclusive', ifAvailable: true),
            ((web.Lock? lock) {
              return (() async {
                try {
                  if (lock == null) {
                    throw StateError('他のタブで学習・復元中です。他のクイズアプリのタブを閉じてください。');
                  }
                  await action();
                } catch (error, stack) {
                  failure = error;
                  failureStack = stack;
                }
                return null;
              })()
                  .toJS;
            }).toJS)
        .toDart;
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  @override
  Future<QuizBackup?> readRecovery() async {
    Database? database;
    var absent = false;
    try {
      try {
        database = await idbFactoryNative.open(_recoveryDatabase,
            onUpgradeNeeded: (event) {
          absent = event.oldVersion == 0;
          event.transaction.abort();
          event.database.close();
        });
      } catch (_) {
        if (absent) return null;
        rethrow;
      }
      final transaction = database.transaction('recovery', idbModeReadOnly);
      final value =
          await transaction.objectStore('recovery').getObject('before');
      await transaction.completed;
      return value == null
          ? null
          : QuizBackup.decode(Uint8List.fromList(utf8.encode(value as String)));
    } finally {
      database?.close();
    }
  }

  @override
  Future<void> saveRecovery(QuizBackup backup) async {
    final database = await idbFactoryNative.open(_recoveryDatabase,
        version: 1,
        onUpgradeNeeded: (event) =>
            event.database.createObjectStore('recovery'));
    try {
      final transaction = database.transaction('recovery', idbModeReadWrite);
      await Future.wait([
        transaction
            .objectStore('recovery')
            .add(utf8.decode(backup.encode()), 'before'),
        transaction.completed,
      ]);
    } finally {
      database.close();
    }
  }

  @override
  Future<void> clearRecovery() async {
    final database = await idbFactoryNative.open(_recoveryDatabase);
    try {
      final transaction = database.transaction('recovery', idbModeReadWrite);
      await Future.wait([
        transaction.objectStore('recovery').delete('before'),
        transaction.completed,
      ]);
    } finally {
      database.close();
    }
  }

  @override
  Future<void> replace(BackupSnapshot snapshot) async {
    // Caller holds the exclusive lock and a verified recovery journal.
    // Preserve absence of the database, not merely an empty store.
    if (snapshot.audioDatabaseVersion == null) {
      await idbFactoryNative.deleteDatabase(backupAudioDatabase);
    } else {
      final database = await idbFactoryNative.open(backupAudioDatabase,
          version: 1,
          onUpgradeNeeded: (event) =>
              event.database.createObjectStore(backupAudioStore));
      try {
        final transaction =
            database.transaction(backupAudioStore, idbModeReadWrite);
        final store = transaction.objectStore(backupAudioStore);
        final writes = <Future<Object?>>[store.clear()];
        for (final entry in snapshot.audio.entries) {
          writes.add(store.put(entry.value, entry.key));
        }
        await Future.wait([...writes, transaction.completed]);
      } finally {
        database.close();
      }
    }
    final storage = web.window.localStorage;
    // Snapshot all scoped keys before deleting; unrelated keys stay untouched.
    final keys = <String>{...snapshot.preferences.keys};
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      if (key != null && key.startsWith(backupPreferencePrefix)) keys.add(key);
    }
    for (final key in keys) {
      final value = snapshot.preferences[key];
      if (value == null) {
        storage.removeItem(key);
      } else {
        storage.setItem(key, value);
      }
    }
  }
}

class BrowserBackupSource implements BackupSource {
  @override
  String get origin => web.window.location.origin;

  @override
  Future<BackupSnapshot> read() async {
    // No SharedPreferences/AppState initialization, migration or setter calls.
    final preferences = _readPreferences();
    final audio = await readBackupAudio(idbFactoryNative);
    return BackupSnapshot(
        preferences: preferences,
        audio: audio.$1,
        audioDatabaseVersion: audio.$2);
  }

  Map<String, String?> _readPreferences() {
    final storage = web.window.localStorage;
    final keys = <String>{...backupPreferenceKeys};
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      if (key != null && key.startsWith(backupPreferencePrefix)) keys.add(key);
    }
    return {for (final key in keys) key: storage.getItem(key)};
  }
}

/// An absent source database must stay absent. An attempted creation is aborted,
/// not committed. Existing databases are opened without a requested version and
/// all their records are read in a single read-only transaction.
Future<(Map<String, Uint8List>, int?)> readBackupAudio(
    IdbFactory factory) async {
  Database? database;
  var absent = false;
  try {
    try {
      database =
          await factory.open(backupAudioDatabase, onUpgradeNeeded: (event) {
        absent = event.oldVersion == 0;
        event.transaction.abort();
        event.database.close();
      });
    } catch (_) {
      if (absent) return (<String, Uint8List>{}, null);
      rethrow;
    }
    final names = database.objectStoreNames;
    if (names.length != 1 || !names.contains(backupAudioStore)) {
      throw StateError('音声DBに未対応の保存領域があります。省略バックアップは行いません。');
    }
    final transaction = database.transaction(backupAudioStore, idbModeReadOnly);
    final store = transaction.objectStore(backupAudioStore);
    if (store.keyPath != null ||
        store.autoIncrement ||
        store.indexNames.isNotEmpty) {
      throw StateError('音声ストアの構造が未対応です。省略バックアップ・復元は行いません。');
    }
    final entries = await Future.wait([store.getAllKeys(), store.getAll()]);
    await transaction.completed;
    final audio = <String, Uint8List>{};
    for (var i = 0; i < entries[0].length; i++) {
      final key = entries[0][i];
      final value = entries[1][i];
      if (key is! String ||
          value is! List ||
          value.any((byte) => byte is! int || byte < 0 || byte > 255)) {
        throw StateError('音声DBに未対応の値があります。省略せず処理を中止しました。');
      }
      audio[key] = Uint8List.fromList(value.cast<int>());
    }
    return (audio, database.version);
  } finally {
    database?.close();
  }
}

class BackupDownload {
  BackupDownload(Uint8List bytes)
      : _url = web.URL.createObjectURL(web.Blob(
          [bytes.toJS].toJS,
          web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
        ));
  String? _url;

  /// Called by a separate user gesture, especially important on mobile Safari.
  /// Keep the URL alive until replaced or the screen is disposed.
  void save(String filename) {
    final url = _url;
    if (url == null) throw StateError('保存するバックアップがありません。');
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
  }

  void dispose() {
    final url = _url;
    if (url != null) web.URL.revokeObjectURL(url);
    _url = null;
  }
}
