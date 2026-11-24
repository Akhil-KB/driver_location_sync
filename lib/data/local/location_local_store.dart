import 'dart:convert';
import 'dart:io';

import 'package:driver_location_sync/models/location_record.dart';
import 'package:path_provider/path_provider.dart';

/// JSON file store for location records.
abstract class LocationLocalStore {
  Future<List<LocationRecord>> loadAll();

  Future<void> saveAll(List<LocationRecord> records);

  Future<void> upsert(LocationRecord record);

  Future<void> upsertAll(List<LocationRecord> records);

  Future<List<LocationRecord>> pendingRecords();
}

class FileLocationLocalStore implements LocationLocalStore {
  FileLocationLocalStore({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;
  File? _cachedFile;

  Future<File> _file() async {
    if (_cachedFile != null) {
      return _cachedFile!;
    }

    final directory =
        _overrideDirectory ?? await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/location_records.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
    }
    return _cachedFile = file;
  }

  @override
  Future<List<LocationRecord>> loadAll() async {
    final file = await _file();
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => LocationRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAll(List<LocationRecord> records) async {
    final file = await _file();
    final payload = records.map((record) => record.toJson()).toList();
    await file.writeAsString(jsonEncode(payload));
  }

  @override
  Future<void> upsert(LocationRecord record) async {
    await upsertAll([record]);
  }

  @override
  Future<void> upsertAll(List<LocationRecord> records) async {
    if (records.isEmpty) {
      return;
    }

    final existing = await loadAll();
    final byId = <String, LocationRecord>{
      for (final record in existing) record.id: record,
    };
    for (final record in records) {
      byId[record.id] = record;
    }
    await saveAll(byId.values.toList());
  }

  @override
  Future<List<LocationRecord>> pendingRecords() async {
    final records = await loadAll();
    return records.where((record) => record.isPending).toList();
  }
}
