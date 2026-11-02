import 'dart:typed_data';

import 'backup_sandbox_service.dart';
import 'backup_service.dart';
import 'live_restore_service.dart';

LiveRestoreStore createBrowserLiveRestoreStore() =>
    throw UnsupportedError('Webブラウザ専用です。');
Future<void> guardStudyStartup() async {}
void openBackupOnly() => throw UnsupportedError('Webブラウザ専用です。');
void reopenStudy() => throw UnsupportedError('Webブラウザ専用です。');

BackupSource createBrowserBackupSource() =>
    throw UnsupportedError('Webブラウザ専用です。');
BackupSandboxService createBrowserBackupSandbox() =>
    throw UnsupportedError('Webブラウザ専用です。');

class BackupDownload {
  BackupDownload(Uint8List bytes);
  void save(String filename) => throw UnsupportedError('Webブラウザ専用です。');
  void dispose() {}
}
