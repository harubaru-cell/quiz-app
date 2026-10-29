import 'dart:js_interop';
import 'dart:typed_data';

import 'package:idb_shim/idb_client_native.dart';
import 'package:web/web.dart' as web;

import '../models/quiz_backup.dart';
import 'backup_sandbox_service.dart';
import 'backup_service.dart';

BackupSource createBrowserBackupSource() => BrowserBackupSource();
BackupSandboxService createBrowserBackupSandbox() =>
    BackupSandboxService(idbFactoryNative);

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
