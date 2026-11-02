import '../models/quiz_backup.dart';
import 'backup_service.dart';
import 'backup_validation_service.dart';

/// Only the restore adapter has write access. BackupSource remains read-only.
abstract class LiveRestoreStore implements BackupSource {
  Future<QuizBackup?> readRecovery();
  Future<void> saveRecovery(QuizBackup backup);
  Future<void> clearRecovery();
  Future<void> replace(BackupSnapshot snapshot);
  Future<void> exclusively(Future<void> Function() action);
}

/// A missing unknown key and an explicitly absent unknown key mean the same
/// physical state. Known keys, raw non-null strings and audio remain exact.
bool sameBackupContents(BackupSnapshot a, BackupSnapshot b) {
  Object contents(BackupSnapshot snapshot) => {
        ...snapshot.toJson(),
        'preferences': {
          for (final entry in snapshot.preferences.entries)
            if (entry.value != null) entry.key: entry.value,
        },
      };
  return backupDigest(contents(a)) == backupDigest(contents(b));
}

class LiveRestoreService {
  LiveRestoreService(this.store);
  final LiveRestoreStore store;

  Future<void> restore(QuizBackup target, QuizBackup savedSafety,
      {required bool confirmed}) async {
    if (!confirmed) throw StateError('明示的な確認が必要です。');
    target = QuizBackup.decode(target.encode());
    savedSafety = QuizBackup.decode(savedSafety.encode());
    if (!BackupValidationService().validate(target.snapshot).canVerifyRestore) {
      throw StateError('復元ファイルに整合性エラーがあります。');
    }
    // AudioStorageService currently understands only v1, with no indexes.
    for (final snapshot in [target.snapshot, savedSafety.snapshot]) {
      if (snapshot.audioDatabaseVersion != null &&
          snapshot.audioDatabaseVersion != 1) {
        throw StateError('音声DBの版が未対応です。本番復元は行いません。');
      }
    }
    await store.exclusively(() async {
      if (await store.readRecovery() != null) {
        throw StateError('未完了の復旧があります。先に復旧してください。');
      }
      final current = await BackupService(store).capture('復元直前の端末内退避');
      if (!sameBackupContents(current.backup.snapshot, savedSafety.snapshot) ||
          savedSafety.origin != store.origin) {
        throw StateError('現行データと退避ファイルが一致しません。再度退避してください。');
      }
      // No live writes before a committed, re-opened recovery record exists.
      await store.saveRecovery(current.backup);
      final recovery = await store.readRecovery();
      if (recovery?.checksum != current.backup.checksum) {
        throw StateError('端末内退避の再読込が一致しません。復元は開始していません。');
      }
      // No live writes yet. If reading fails, retain the journal for recovery.
      if (!sameBackupContents(await store.read(), current.backup.snapshot)) {
        await store.clearRecovery();
        throw StateError('復元直前にデータが変化しました。再度退避してください。');
      }
      try {
        await _replaceAndCheck(target.snapshot);
        await store.clearRecovery();
      } catch (error) {
        try {
          await _replaceAndCheck(current.backup.snapshot);
          await store.clearRecovery();
        } catch (rollbackError) {
          throw StateError('復元は未完了です。元データへの復旧も未完了です。'
              '通常学習を再開せず、この画面で復旧を再試行してください。'
              '\n復元: $error\n復旧: $rollbackError');
        }
        throw StateError('復元に失敗しました。復元前の原文・音声への復旧と一致を確認しました。'
            '\n$error');
      }
    });
  }

  Future<void> recover() => store.exclusively(() async {
        final recovery = await store.readRecovery();
        if (recovery == null) return;
        await _replaceAndCheck(recovery.snapshot);
        await store.clearRecovery();
      });

  Future<void> _replaceAndCheck(BackupSnapshot snapshot) async {
    await store.replace(snapshot);
    final first = await store.read();
    final second = await store.read();
    if (!sameBackupContents(first, snapshot) ||
        !sameBackupContents(second, snapshot)) {
      throw StateError('保存後の再読込で原文・未作成キー・音声が一致しません。');
    }
  }
}
