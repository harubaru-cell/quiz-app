import '../models/quiz_backup.dart';
import 'backup_validation_service.dart';

/// Intentionally has no write/delete API for the source storage.
abstract class BackupSource {
  String get origin;
  Future<BackupSnapshot> read();
}

class CapturedBackup {
  CapturedBackup(this.backup, this.validation);
  final QuizBackup backup;
  final BackupValidationReport validation;
}

class BackupService {
  BackupService(this.source);
  final BackupSource source;

  Future<CapturedBackup> capture(String deviceLabel) async {
    final before = await source.read();
    final after = await source.read();
    if (before.digest != after.digest) {
      throw StateError('取得中に学習データが変わりました。他のタブでの学習を止めて再試行してください。');
    }
    final backup = QuizBackup.create(
      origin: source.origin,
      deviceLabel: deviceLabel,
      snapshot: before,
    );
    final decoded = QuizBackup.decode(backup.encode());
    if (decoded.snapshot.digest != before.digest ||
        decoded.checksum != backup.checksum) {
      throw StateError('書き出し前後のデータが一致しません。');
    }
    return CapturedBackup(backup, BackupValidationService().validate(before));
  }
}
