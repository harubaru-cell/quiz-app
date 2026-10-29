import 'dart:typed_data';

import 'package:idb_shim/idb.dart';
import 'package:uuid/uuid.dart';

import '../models/quiz_backup.dart';
import 'backup_service.dart';
import 'backup_validation_service.dart';

class BackupRestoreResult {
  BackupRestoreResult(
      {required this.databaseName,
      required this.snapshotDigest,
      required this.sourceUnchanged,
      required this.validation});
  final String databaseName;
  final String snapshotDigest;
  final bool sourceUnchanged;
  final BackupValidationReport validation;
}

/// No configurable destination: imported JSON can never select the live DB.
class BackupSandboxService {
  BackupSandboxService(this.factory);
  final IdbFactory factory;
  static const databasePrefix = 'quiz_study_backup_sandbox_';
  static final _sandboxName = RegExp(
    r'^quiz_study_backup_sandbox_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  Future<BackupRestoreResult> verify(
      QuizBackup backup, BackupSource source) async {
    final validation = BackupValidationService().validate(backup.snapshot);
    if (!validation.canVerifyRestore) {
      throw StateError('整合性エラーがあります。原文のバックアップは保存できますが、復元検証はできません。');
    }
    final before = await source.read();
    final databaseName = '$databasePrefix${const Uuid().v4()}';
    try {
      final restored = await _restoreAndRead(databaseName, backup.snapshot);
      final after = await source.read();
      if (restored.digest != backup.snapshot.digest) {
        throw StateError('隔離復元前後の保存値・音声が一致しません。');
      }
      return BackupRestoreResult(
        databaseName: databaseName,
        snapshotDigest: restored.digest,
        sourceUnchanged: before.digest == after.digest,
        validation: BackupValidationService().validate(restored),
      );
    } finally {
      // Only the newly generated sandbox is removed, never the source database.
      await remove(databaseName);
    }
  }

  Future<BackupSnapshot> _restoreAndRead(
      String name, BackupSnapshot snapshot) async {
    _requireSandboxName(name);
    Database? database;
    try {
      database = await factory.open(name, version: 1, onUpgradeNeeded: (event) {
        event.database.createObjectStore('preferences');
        event.database.createObjectStore('audio');
        event.database.createObjectStore('manifest');
      });
      var transaction = database.transactionList(
          ['preferences', 'audio', 'manifest'], idbModeReadWrite);
      final writes = <Future<Object?>>[];
      for (final entry in snapshot.preferences.entries) {
        if (entry.value != null) {
          writes.add(transaction
              .objectStore('preferences')
              .add(entry.value!, entry.key));
        }
      }
      for (final entry in snapshot.audio.entries) {
        writes
            .add(transaction.objectStore('audio').add(entry.value, entry.key));
      }
      writes.add(transaction.objectStore('manifest').add({
        'preferenceKeys': snapshot.preferences.keys.toList(),
        'audioDatabaseVersion': snapshot.audioDatabaseVersion,
      }, 'snapshot'));
      await Future.wait(writes);
      await transaction.completed;
      // Reopen to exercise persistent storage, not just the original objects.
      database.close();
      database = await factory.open(name);
      transaction = database.transactionList(
          ['preferences', 'audio', 'manifest'], idbModeReadOnly);
      final preferenceStore = transaction.objectStore('preferences');
      final audioStore = transaction.objectStore('audio');
      final values = await Future.wait([
        transaction.objectStore('manifest').getObject('snapshot'),
        preferenceStore.getAllKeys(),
        preferenceStore.getAll(),
        audioStore.getAllKeys(),
        audioStore.getAll(),
      ]);
      await transaction.completed;
      final manifest = values[0] as Map;
      final preferences = <String, String?>{
        for (final key in (manifest['preferenceKeys'] as List))
          key as String: null,
      };
      final preferenceKeys = values[1] as List;
      final preferenceValues = values[2] as List;
      for (var i = 0; i < preferenceKeys.length; i++) {
        preferences[preferenceKeys[i] as String] =
            preferenceValues[i] as String;
      }
      final audioKeys = values[3] as List;
      final audioValues = values[4] as List;
      final audio = <String, Uint8List>{};
      for (var i = 0; i < audioKeys.length; i++) {
        audio[audioKeys[i] as String] =
            Uint8List.fromList((audioValues[i] as List).cast<int>());
      }
      return BackupSnapshot(
          preferences: preferences,
          audio: audio,
          audioDatabaseVersion: manifest['audioDatabaseVersion'] as int?);
    } catch (_) {
      database?.close();
      database = null;
      await remove(name);
      rethrow;
    } finally {
      database?.close();
    }
  }

  Future<void> remove(String databaseName) async {
    _requireSandboxName(databaseName);
    await factory.deleteDatabase(databaseName);
  }

  void _requireSandboxName(String name) {
    if (!_sandboxName.hasMatch(name) || name == backupAudioDatabase) {
      throw ArgumentError('削除・復元の対象は専用の隔離DBだけです。');
    }
  }
}
