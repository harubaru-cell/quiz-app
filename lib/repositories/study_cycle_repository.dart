import 'dart:convert';

import '../models/study_cycle.dart';
import '../services/storage_service.dart';

class StudyCycleRepository {
  StudyCycleRepository(this._storageService);

  final StorageService _storageService;

  Future<StudyCycleSnapshot> loadCycles() async {
    final raw = await _storageService.readString(StorageService.studyCyclesKey);

    if (raw == null || raw.isEmpty) {
      return StudyCycleSnapshot.empty();
    }

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw const FormatException('StudyCycle data is invalid.');
    }

    return StudyCycleSnapshot.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  Future<void> saveCycles(StudyCycleSnapshot snapshot) async {
    await _storageService.writeString(
      StorageService.studyCyclesKey,
      jsonEncode(snapshot.toJson()),
    );
  }
}
