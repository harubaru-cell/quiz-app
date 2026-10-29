import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Physical localStorage keys used by SharedPreferences Web. Values are kept
/// verbatim, including its JSON string wrapper, whitespace and unknown fields.
const backupPreferencePrefix = 'flutter.quiz_app.';
const backupPreferenceKeys = <String>[
  '${backupPreferencePrefix}decks',
  '${backupPreferencePrefix}histories',
  '${backupPreferencePrefix}deck_stats',
  '${backupPreferencePrefix}question_progress',
  '${backupPreferencePrefix}study_cycles',
];
const backupAudioDatabase = 'quiz_study_audio_database';
const backupAudioStore = 'audio_files';

String canonicalBackupJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return <String, Object?>{for (final key in keys) key: sort(item[key])};
    }
    if (item is List) return item.map(sort).toList();
    return item;
  }

  return jsonEncode(sort(value));
}

String backupDigest(Object? value) =>
    sha256.convert(utf8.encode(canonicalBackupJson(value))).toString();

class BackupSnapshot {
  BackupSnapshot({
    required Map<String, String?> preferences,
    Map<String, Uint8List> audio = const {},
    this.audioDatabaseVersion,
  })  : preferences = Map.unmodifiable(preferences),
        audio = Map.unmodifiable({
          for (final entry in audio.entries)
            entry.key: Uint8List.fromList(entry.value).asUnmodifiableView(),
        });

  final Map<String, String?> preferences;
  final Map<String, Uint8List> audio;
  final int? audioDatabaseVersion;

  Map<String, Object?> toJson() => {
        'preferences': preferences,
        'audioDatabaseVersion': audioDatabaseVersion,
        'audio': {
          for (final entry in audio.entries)
            entry.key: base64Encode(entry.value),
        },
      };

  String get digest => backupDigest(toJson());

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) {
    if (json.length != 3 ||
        !json.containsKey('preferences') ||
        !json.containsKey('audioDatabaseVersion') ||
        !json.containsKey('audio')) {
      throw const FormatException('保存データの項目が不足しているか未対応です。');
    }
    final rawPreferences = json['preferences'];
    final rawAudio = json['audio'];
    final version = json['audioDatabaseVersion'];
    if (rawPreferences is! Map ||
        rawAudio is! Map ||
        (version != null && (version is! int || version < 1))) {
      throw const FormatException('保存データの形式が不正です。');
    }
    final preferences = <String, String?>{};
    for (final entry in rawPreferences.entries) {
      if (entry.key is! String ||
          !(entry.key as String).startsWith(backupPreferencePrefix) ||
          (entry.value != null && entry.value is! String)) {
        throw const FormatException('学習データ以外のキー、または不正な保存値です。');
      }
      preferences[entry.key as String] = entry.value as String?;
    }
    if (!backupPreferenceKeys.every(preferences.containsKey)) {
      throw const FormatException('必須保存キーの存在・未作成情報が不足しています。');
    }
    final audio = <String, Uint8List>{};
    for (final entry in rawAudio.entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          entry.value is! String) {
        throw const FormatException('音声データの形式が不正です。');
      }
      audio[entry.key as String] = base64Decode(entry.value as String);
    }
    if (version == null && audio.isNotEmpty) {
      throw const FormatException('音声DBの情報と保存内容が一致しません。');
    }
    return BackupSnapshot(
      preferences: preferences,
      audio: audio,
      audioDatabaseVersion: version as int?,
    );
  }
}

class QuizBackup {
  QuizBackup._(this.createdAt, this.origin, this.deviceLabel, this.snapshot);

  factory QuizBackup.create({
    required String origin,
    required String deviceLabel,
    required BackupSnapshot snapshot,
    DateTime? createdAt,
  }) {
    if (deviceLabel.trim().isEmpty) {
      throw const FormatException('端末名を入力してください。');
    }
    // Validate the envelope without interpreting or normalizing stored values.
    BackupSnapshot.fromJson(snapshot.toJson());
    return QuizBackup._(
      (createdAt ?? DateTime.now()).toUtc(),
      origin,
      deviceLabel.trim(),
      snapshot,
    );
  }

  static const format = 'quiz-study-backup';
  static const formatVersion = 1;
  static const maxFileBytes = 64 * 1024 * 1024;

  final DateTime createdAt;
  final String origin;
  final String deviceLabel;
  final BackupSnapshot snapshot;

  Map<String, Object?> get _payload => {
        'format': format,
        'formatVersion': formatVersion,
        'createdAt': createdAt.toIso8601String(),
        'source': {
          'origin': origin,
          'deviceLabel': deviceLabel,
          'appVersion': '1.5',
          'storageFormat': 'shared_preferences_web-localStorage-json-v1',
          'captureMethod': 'two-identical-reads',
          'audioDatabase': backupAudioDatabase,
          'audioStore': backupAudioStore,
        },
        'snapshot': snapshot.toJson(),
      };

  String get checksum => backupDigest(_payload);

  Map<String, Object?> toJson() => {..._payload, 'sha256': checksum};

  Uint8List encode() {
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson())),
    );
    if (bytes.length > maxFileBytes) {
      throw const FormatException('バックアップが64 MiBを超えています。省略保存はしません。');
    }
    return bytes;
  }

  factory QuizBackup.decode(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('バックアップの上限は64 MiBです。');
    }
    var source = utf8.decode(bytes);
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['formatVersion'] != formatVersion ||
        decoded.length != 6) {
      throw const FormatException('未対応のバックアップ形式です。通常のデッキJSONとは異なります。');
    }
    final payload = Map<String, dynamic>.from(decoded)..remove('sha256');
    if (decoded['sha256'] is! String ||
        decoded['sha256'] != backupDigest(payload)) {
      throw const FormatException('SHA-256が一致しません。ファイルの欠損・変更を確認してください。');
    }
    final sourceInfo = decoded['source'];
    final createdAt = decoded['createdAt'];
    if (sourceInfo is! Map ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        sourceInfo['origin'] is! String ||
        sourceInfo['deviceLabel'] is! String ||
        (sourceInfo['deviceLabel'] as String).trim().isEmpty ||
        sourceInfo['appVersion'] != '1.5' ||
        sourceInfo['storageFormat'] !=
            'shared_preferences_web-localStorage-json-v1' ||
        sourceInfo['captureMethod'] != 'two-identical-reads' ||
        sourceInfo['audioDatabase'] != backupAudioDatabase ||
        sourceInfo['audioStore'] != backupAudioStore ||
        sourceInfo.length != 7 ||
        decoded['snapshot'] is! Map<String, dynamic>) {
      throw const FormatException('バックアップの取得元情報が不正、または未対応です。');
    }
    final backup = QuizBackup._(
      DateTime.parse(createdAt).toUtc(),
      sourceInfo['origin'] as String,
      sourceInfo['deviceLabel'] as String,
      BackupSnapshot.fromJson(decoded['snapshot'] as Map<String, dynamic>),
    );
    // Reject noncanonical metadata that would otherwise change on re-export.
    if (backup.checksum != decoded['sha256']) {
      throw const FormatException('メタデータが現在のバックアップ仕様と一致しません。');
    }
    return backup;
  }
}
