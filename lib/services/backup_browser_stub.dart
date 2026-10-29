import 'dart:typed_data';

import 'backup_sandbox_service.dart';
import 'backup_service.dart';

BackupSource createBrowserBackupSource() =>
    throw UnsupportedError('Webブラウザ専用です。');
BackupSandboxService createBrowserBackupSandbox() =>
    throw UnsupportedError('Webブラウザ専用です。');

class BackupDownload {
  BackupDownload(Uint8List bytes);
  void save(String filename) => throw UnsupportedError('Webブラウザ専用です。');
  void dispose() {}
}
