import 'package:flutter_test/flutter_test.dart';
import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/services/live_restore_service.dart';
import '../support/backup_fixtures.dart';

void main() {
  late MemoryRestoreStore store;
  late QuizBackup safety;
  late QuizBackup target;
  setUp(() {
    store = MemoryRestoreStore(backupFixture(withAudio: true));
    safety = fixtureDocument(store.snapshot);
    target = fixtureDocument(
        replacePreference(backupFixture(), 'study_cycles', null));
  });
  test('完全置換・再読込確認後だけ退避ジャーナルを解除', () async {
    await LiveRestoreService(store).restore(target, safety, confirmed: true);
    expect(sameBackupContents(store.snapshot, target.snapshot), isTrue);
    expect(store.pending, isNull);
    expect(store.writes, 1);
  });
  test('未確認・不正ファイル・古い退避では書き込まない', () async {
    await expectLater(
        LiveRestoreService(store).restore(target, safety, confirmed: false),
        throwsStateError);
    final broken = fixtureDocument(
        replacePreference(target.snapshot, 'histories', 'broken'));
    await expectLater(
        LiveRestoreService(store).restore(broken, safety, confirmed: true),
        throwsStateError);
    await expectLater(
        LiveRestoreService(store).restore(target, target, confirmed: true),
        throwsStateError);
    expect(store.writes, 0);
    expect(store.pending, isNull);
    expect(sameBackupContents(store.snapshot, safety.snapshot), isTrue);
  });
  test('部分書込後のエラー・読戻し不一致では元の原文と音声へ戻す', () async {
    for (final mismatch in [false, true]) {
      store.failWrites = mismatch ? 0 : 1;
      store.mismatchOnce = mismatch;
      await expectLater(
          LiveRestoreService(store).restore(target, safety, confirmed: true),
          throwsStateError);
      expect(sameBackupContents(store.snapshot, safety.snapshot), isTrue);
      expect(store.pending, isNull);
    }
  });
  test('復旧失敗で退避を保持し、再起動相当の再試行で元に戻す', () async {
    store.failWrites = 2;
    await expectLater(
        LiveRestoreService(store).restore(target, safety, confirmed: true),
        throwsStateError);
    expect(store.pending, isNotNull);
    await LiveRestoreService(store).recover();
    expect(sameBackupContents(store.snapshot, safety.snapshot), isTrue);
    expect(store.pending, isNull);
  });
  test('退避保存失敗では本体に書き込まない', () async {
    store.failJournal = true;
    await expectLater(
        LiveRestoreService(store).restore(target, safety, confirmed: true),
        throwsStateError);
    expect(store.writes, 0);
    expect(sameBackupContents(store.snapshot, safety.snapshot), isTrue);
  });
}

class MemoryRestoreStore implements LiveRestoreStore {
  MemoryRestoreStore(this.snapshot);
  BackupSnapshot snapshot;
  QuizBackup? pending;
  int failWrites = 0;
  int writes = 0;
  bool mismatchOnce = false;
  bool failJournal = false;
  @override
  String get origin => 'https://example.invalid';
  @override
  Future<BackupSnapshot> read() async => snapshot;
  @override
  Future<QuizBackup?> readRecovery() async => pending;
  @override
  Future<void> saveRecovery(QuizBackup backup) async {
    if (failJournal) throw StateError('journal quota');
    pending = QuizBackup.decode(backup.encode());
  }

  @override
  Future<void> clearRecovery() async => pending = null;
  @override
  Future<void> exclusively(Future<void> Function() action) => action();
  @override
  Future<void> replace(BackupSnapshot value) async {
    expect(pending, isNotNull);
    writes++;
    snapshot = value;
    if (failWrites > 0) {
      failWrites--;
      throw StateError('injected partial write');
    }
    if (mismatchOnce) {
      mismatchOnce = false;
      snapshot = replacePreference(value, 'study_cycles', 'injected mismatch');
    }
  }
}
