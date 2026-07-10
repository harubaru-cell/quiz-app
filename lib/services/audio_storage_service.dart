import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

class AudioStorageService {
  AudioStorageService._();

  static final AudioStorageService instance = AudioStorageService._();

  static const String storedAudioPrefix = 'stored-audio:';

  static const String _databaseName = 'quiz_study_audio_database';
  static const int _databaseVersion = 1;
  static const String _storeName = 'audio_files';

  Database? _database;

  Future<Database> _openDatabase() async {
    final existingDatabase = _database;

    if (existingDatabase != null) {
      return existingDatabase;
    }

    final database = await idbFactoryBrowser.open(
      _databaseName,
      version: _databaseVersion,
      onUpgradeNeeded: (event) {
        final database = event.database;

        if (!database.objectStoreNames.contains(_storeName)) {
          database.createObjectStore(_storeName);
        }
      },
    );

    _database = database;
    return database;
  }

  Future<void> saveAudio({
    required String storageKey,
    required Uint8List bytes,
  }) async {
    final database = await _openDatabase();

    final transaction = database.transaction(
      _storeName,
      idbModeReadWrite,
    );

    final store = transaction.objectStore(_storeName);

    await store.put(bytes, storageKey);
    await transaction.completed;
  }

  Future<Uint8List?> loadAudio(String storageKey) async {
    final database = await _openDatabase();

    final transaction = database.transaction(
      _storeName,
      idbModeReadOnly,
    );

    final store = transaction.objectStore(_storeName);
    final value = await store.getObject(storageKey);

    await transaction.completed;

    if (value == null) {
      return null;
    }

    if (value is Uint8List) {
      return value;
    }

    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    throw StateError(
      '保存されている音声データの形式が不正です。',
    );
  }

  Future<void> deleteAudio(String storageKey) async {
    final database = await _openDatabase();

    final transaction = database.transaction(
      _storeName,
      idbModeReadWrite,
    );

    final store = transaction.objectStore(_storeName);

    await store.delete(storageKey);
    await transaction.completed;
  }

  String createReference(String storageKey) {
    return '$storedAudioPrefix$storageKey';
  }

  bool isStoredAudioReference(String value) {
    return value.startsWith(storedAudioPrefix);
  }

  String getStorageKeyFromReference(String reference) {
    if (!isStoredAudioReference(reference)) {
      throw const FormatException(
        '端末内音声の参照形式が不正です。',
      );
    }

    return reference.substring(storedAudioPrefix.length);
  }
}
