import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:personal_quiz_study/models/quiz_backup.dart';
import 'package:personal_quiz_study/services/backup_sandbox_service.dart';
import 'package:personal_quiz_study/services/backup_service.dart';
import 'package:personal_quiz_study/services/backup_validation_service.dart';

import '../support/backup_fixtures.dart';

void main() {
  final validator = BackupValidationService();

  test('3形式、空白、日時、未知の項目、音声を原文のまま往復する', () {
    final snapshot = backupFixture(withAudio: true);
    final backup = fixtureDocument(snapshot);
    final decoded = QuizBackup.decode(backup.encode());
    expect(decoded.checksum, backup.checksum);
    expect(decoded.snapshot.preferences, snapshot.preferences);
    expect(decoded.snapshot.digest, snapshot.digest);
    expect(decoded.snapshot.audio.values.single, [0, 1, 128, 255]);
    expect(decoded.createdAt, DateTime.utc(2026, 2, 5));
    expect(decoded.snapshot.preferences[backupPreferenceKeys.first],
        contains('unknownFutureField'));
  });

  test('未作成、空文字、空配列、未知の保存キーを区別して保持する', () {
    final snapshot = BackupSnapshot(preferences: {
      for (final key in backupPreferenceKeys) key: null,
      backupPreferenceKeys[0]: jsonEncode(''),
      backupPreferenceKeys[1]: wrapPreference([]),
      '${backupPreferencePrefix}future': 'not interpreted',
    });
    final restored =
        QuizBackup.decode(fixtureDocument(snapshot).encode()).snapshot;
    expect(restored.preferences, snapshot.preferences);
    expect(validator.validate(restored).errors, isEmpty);
    expect(validator.validate(restored).warnings, isNotEmpty);
  });

  test('バイト列を外部から変更できない', () {
    final bytes = Uint8List.fromList([7]);
    final snapshot = BackupSnapshot(
        preferences: {for (final k in backupPreferenceKeys) k: null},
        audio: {'orphan': bytes},
        audioDatabaseVersion: 1);
    bytes[0] = 99;
    expect(snapshot.audio['orphan'], [7]);
    expect(() => snapshot.audio['orphan']![0] = 3, throwsUnsupportedError);
  });

  test('保存内容の変更をSHA-256で検出する', () {
    final json = fixtureDocument(backupFixture()).toJson();
    (json['snapshot'] as Map)['preferences'] = {
      for (final k in backupPreferenceKeys) k: null
    };
    expect(() => QuizBackup.decode(bytesOf(json)), throwsFormatException);
  });

  test('未対応版、通常デッキJSON、欠損JSONを拒否する', () {
    final json = fixtureDocument(backupFixture()).toJson()
      ..['formatVersion'] = 999;
    expect(() => QuizBackup.decode(bytesOf(json)), throwsFormatException);
    expect(() => QuizBackup.decode(bytesOf({'title': 'deck', 'questions': []})),
        throwsFormatException);
    expect(() => QuizBackup.decode(Uint8List.fromList(utf8.encode('{'))),
        throwsFormatException);
  });

  test('ハッシュ再計算済みでも必須キー欠損・対象外キーは拒否する', () {
    for (final outside in [false, true]) {
      final json = fixtureDocument(backupFixture()).toJson();
      final preferences = Map<String, dynamic>.from(
          (json['snapshot'] as Map)['preferences'] as Map);
      if (outside) {
        preferences['auth_token'] = 'secret';
      } else {
        preferences.remove(backupPreferenceKeys.first);
      }
      (json['snapshot'] as Map)['preferences'] = preferences;
      resign(json);
      expect(() => QuizBackup.decode(bytesOf(json)), throwsFormatException);
    }
  });

  test('不正Base64や未対応の取得元情報を拒否する', () {
    final audioJson = fixtureDocument(backupFixture(withAudio: true)).toJson();
    (audioJson['snapshot'] as Map)['audio'] = {'audio': '!bad'};
    resign(audioJson);
    expect(() => QuizBackup.decode(bytesOf(audioJson)), throwsFormatException);
    final metadata = fixtureDocument(backupFixture()).toJson();
    (metadata['source'] as Map)['storageFormat'] = 'unknown';
    resign(metadata);
    expect(() => QuizBackup.decode(bytesOf(metadata)), throwsFormatException);
  });

  test('BOM付きUTF-8も同じ内容で読み込む', () {
    final original = fixtureDocument(backupFixture());
    expect(
        QuizBackup.decode(
            Uint8List.fromList([239, 187, 191, ...original.encode()])).checksum,
        original.checksum);
  });

  test('正常な件数を領域別に表示し二重加算しない', () {
    final report = validator.validate(backupFixture(withAudio: true));
    expect(report.errors, isEmpty);
    expect(report.warnings, isEmpty);
    expect(report.counts, {
      'デッキ': 1,
      '問題': 3,
      '学習履歴': 1,
      '履歴内の回答': 3,
      'デッキ集計': 1,
      '問題別進捗': 2,
      '一周状態': 1,
      '一周内の回答': 1,
      '音声ファイル': 1,
      '音声バイト': 4,
    });
  });

  test('壊れた元データも書き出せるが、正常な復元とは扱わない', () {
    final source =
        replacePreference(backupFixture(), 'histories', 'broken raw wrapper');
    final restored =
        QuizBackup.decode(fixtureDocument(source).encode()).snapshot;
    expect(restored.preferences, source.preferences);
    expect(validator.validate(restored).canVerifyRestore, isFalse);
  });

  test('履歴内の不整合、進捗内の不整合を診断する', () {
    var snapshot = backupFixture();
    final histories = unwrap(snapshot, 'histories') as List;
    (histories.first as Map)['totalAnswered'] = 99;
    snapshot =
        replacePreference(snapshot, 'histories', wrapPreference(histories));
    final progress = unwrap(snapshot, 'question_progress') as Map;
    ((progress['items'] as List).first as Map)['answerCount'] = 99;
    snapshot = replacePreference(
        snapshot, 'question_progress', wrapPreference(progress));
    expect(validator.validate(snapshot).errors, hasLength(2));
  });

  test('一周の位置と回答列が不正なら復元検証を止める', () {
    final snapshot = backupFixture();
    final cycles = unwrap(snapshot, 'study_cycles') as Map;
    ((cycles['items'] as List).first as Map)['nextIndex'] = 2;
    expect(
        validator
            .validate(replacePreference(
                snapshot, 'study_cycles', wrapPreference(cycles)))
            .errors,
        isNotEmpty);
  });

  test('旧進捗未作成・存在しない参照は補正や移行をせず警告する', () {
    var snapshot =
        replacePreference(backupFixture(), 'question_progress', null);
    final histories = unwrap(snapshot, 'histories') as List;
    (histories.first as Map)['deckId'] = 'deleted-deck';
    snapshot =
        replacePreference(snapshot, 'histories', wrapPreference(histories));
    final original = snapshot.digest;
    final report = validator.validate(snapshot);
    expect(report.errors, isEmpty);
    expect(report.warnings, hasLength(2));
    expect(snapshot.digest, original);
  });

  test('不足音声はエラー、孤立音声は省略せず警告する', () {
    final withAudio = backupFixture(withAudio: true);
    final missing = BackupSnapshot(preferences: withAudio.preferences);
    expect(validator.validate(missing).errors, isNotEmpty);
    final orphan = BackupSnapshot(
        preferences: backupFixture().preferences,
        audioDatabaseVersion: 1,
        audio: {
          'orphan': Uint8List.fromList([1])
        });
    expect(validator.validate(orphan).errors, isEmpty);
    expect(validator.validate(orphan).warnings, isNotEmpty);
  });

  test('未取得の外部音声を完全なバックアップと扱わない', () {
    final snapshot = backupFixture(withAudio: true);
    final decks = unwrap(snapshot, 'decks') as List;
    (((decks.first as Map)['questions'] as List).first as Map)['audio'] =
        'https://example.invalid/audio.mp3';
    expect(
        validator
            .validate(
                replacePreference(snapshot, 'decks', wrapPreference(decks)))
            .errors,
        contains(contains('完全性')));
  });

  test('空の保存領域は公開データ取得済みと扱わず注意を表示する', () {
    final snapshot = BackupSnapshot(
        preferences: {for (final key in backupPreferenceKeys) key: null});
    expect(
        validator.validate(snapshot).warnings.single, contains('学習データはありません'));
  });

  test('未作成キーと保存済みのnull JSONを混同しない', () {
    final snapshot =
        replacePreference(backupFixture(), 'histories', jsonEncode('null'));
    expect(validator.validate(snapshot).errors, isNotEmpty);
    expect(
        QuizBackup.decode(fixtureDocument(snapshot).encode())
            .snapshot
            .preferences,
        snapshot.preferences);
  });

  test('取得は2回読取とJSON往復の一致を確認し書込口を持たない', () async {
    final source = FixtureBackupSource(backupFixture(withAudio: true));
    final before = source.snapshot.digest;
    final result = await BackupService(source).capture('PC Chrome');
    expect(source.readCount, 2);
    expect(source.snapshot.digest, before);
    expect(result.backup.snapshot.digest, before);
    expect(result.validation.errors, isEmpty);
  });

  test('取得中の変更・取得失敗を空の正常バックアップにしない', () async {
    final source = FixtureBackupSource(backupFixture())
      ..subsequent = replacePreference(backupFixture(), 'histories', null);
    await expectLater(BackupService(source).capture('PC'), throwsStateError);
    final unavailable = FixtureBackupSource(backupFixture())
      ..failure = StateError('denied');
    await expectLater(
        BackupService(unavailable).capture('PC'), throwsStateError);
  });

  test('別DBへ書き込み再オープンして原文・音声・不在キーを一致確認する', () async {
    final factory = newIdbFactoryMemory();
    final snapshot = replacePreference(
        backupFixture(withAudio: true), 'question_progress', null);
    final source = FixtureBackupSource(snapshot);
    final database = await factory.open(backupAudioDatabase,
        version: 1,
        onUpgradeNeeded: (event) =>
            event.database.createObjectStore(backupAudioStore));
    final tx = database.transaction(backupAudioStore, idbModeReadWrite);
    await tx
        .objectStore(backupAudioStore)
        .put(Uint8List.fromList([42]), 'sentinel');
    await tx.completed;
    final result = await BackupSandboxService(factory)
        .verify(fixtureDocument(snapshot), source);
    expect(result.sourceUnchanged, isTrue);
    expect(result.snapshotDigest, snapshot.digest);
    expect(result.validation.counts, validator.validate(snapshot).counts);
    final read = database.transaction(backupAudioStore, idbModeReadOnly);
    expect(
        await read.objectStore(backupAudioStore).getObject('sentinel'), [42]);
    await read.completed;
    database.close();
    expect(source.snapshot.digest, snapshot.digest);
    expect(
        result.databaseName, startsWith(BackupSandboxService.databasePrefix));
  });

  test('元DBや任意の名前を削除対象にできない', () async {
    final sandbox = BackupSandboxService(newIdbFactoryMemory());
    for (final name in [
      backupAudioDatabase,
      'other',
      '${BackupSandboxService.databasePrefix}bad'
    ]) {
      await expectLater(sandbox.remove(name), throwsArgumentError);
    }
  });

  test('元データが検証中に変化した場合を一致確認済みと扱わない', () async {
    final snapshot = backupFixture();
    final source = FixtureBackupSource(snapshot)
      ..subsequent = replacePreference(snapshot, 'histories', null);
    final result = await BackupSandboxService(newIdbFactoryMemory())
        .verify(fixtureDocument(snapshot), source);
    expect(result.sourceUnchanged, isFalse);
  });

  test('整合性エラー時は隔離書込も開始しない', () async {
    final snapshot = replacePreference(backupFixture(), 'histories', 'bad');
    final source = FixtureBackupSource(snapshot);
    await expectLater(
        BackupSandboxService(newIdbFactoryMemory())
            .verify(fixtureDocument(snapshot), source),
        throwsStateError);
    expect(source.readCount, 0);
  });

  test('隔離DBの作成失敗でも元データはそのまま残す', () async {
    final snapshot = backupFixture();
    final factory = FailingSandboxFactory(newIdbFactoryMemory());
    final source = FixtureBackupSource(snapshot);
    await expectLater(
        BackupSandboxService(factory).verify(fixtureDocument(snapshot), source),
        throwsStateError);
    expect(source.snapshot.digest, snapshot.digest);
    expect(
        factory.names.every(
            (name) => name.startsWith(BackupSandboxService.databasePrefix)),
        isTrue);
  });
}

Uint8List bytesOf(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));
Object? unwrap(BackupSnapshot snapshot, String suffix) => jsonDecode(
    jsonDecode(snapshot.preferences['$backupPreferencePrefix$suffix']!)
        as String);
void resign(Map<String, Object?> json) {
  json.remove('sha256');
  json['sha256'] = backupDigest(json);
}

class FailingSandboxFactory implements IdbFactory {
  FailingSandboxFactory(this.delegate);
  final IdbFactory delegate;
  final names = <String>[];
  @override
  Future<Database> open(String name,
      {int? version,
      OnUpgradeNeededFunction? onUpgradeNeeded,
      OnBlockedFunction? onBlocked}) async {
    names.add(name);
    throw StateError('simulated unavailable storage');
  }

  @override
  Future<IdbFactory> deleteDatabase(String name,
      {OnBlockedFunction? onBlocked}) {
    names.add(name);
    return delegate.deleteDatabase(name, onBlocked: onBlocked);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
