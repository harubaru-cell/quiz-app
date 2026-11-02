import 'dart:io';
import '../test/support/backup_fixtures.dart';

/// Synthetic fixture only; never reads an existing browser or personal file.
void main() {
  final directory = Directory('build/live-restore-ui');
  directory.createSync(recursive: true);
  File('${directory.path}/target.quiz-backup.json').writeAsBytesSync(
      fixtureDocument(backupFixture(withAudio: true)).encode());
  File('${directory.path}/invalid.quiz-backup.json')
      .writeAsStringSync('{broken');
}
