import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:driver_location_sync/models/location_record.dart';
import 'package:path_provider/path_provider.dart';

abstract class LocationLocalStore {
  Future<List<LocationRecord>> loadAll();

  Future<void> saveAll(List<LocationRecord> records);

  Future<void> upsert(LocationRecord record);

  Future<void> upsertAll(List<LocationRecord> records);

  Future<List<LocationRecord>> pendingRecords();

  /// Records left in [SyncStatus.syncing] after a crash/restart.
  Future<int> recoverInterruptedSyncs();
}

class FileLocationLocalStore implements LocationLocalStore {
  FileLocationLocalStore({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;
  File? _cachedFile;
  Future<void> _writeChain = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeChain = _writeChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

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

  Future<List<LocationRecord>> _readRecords(File file) async {
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const <LocationRecord>[];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => LocationRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeRecords(File file, List<LocationRecord> records) async {
    final payload = records.map((record) => record.toJson()).toList();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  @override
  Future<List<LocationRecord>> loadAll() {
    return _serialized(() async {
      final file = await _file();
      return _readRecords(file);
    });
  }

  @override
  Future<void> saveAll(List<LocationRecord> records) {
    return _serialized(() async {
      final file = await _file();
      await _writeRecords(file, records);
    });
  }

  @override
  Future<void> upsert(LocationRecord record) => upsertAll([record]);

  @override
  Future<void> upsertAll(List<LocationRecord> records) {
    if (records.isEmpty) {
      return Future<void>.value();
    }

    return _serialized(() async {
      final file = await _file();
      final existing = await _readRecords(file);
      final byId = <String, LocationRecord>{
        for (final record in existing) record.id: record,
      };
      for (final record in records) {
        byId[record.id] = record;
      }
      await _writeRecords(file, byId.values.toList());
    });
  }

  @override
  Future<List<LocationRecord>> pendingRecords() async {
    final records = await loadAll();
    final pending = records.where((record) => record.isPending).toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return pending;
  }

  @override
  Future<int> recoverInterruptedSyncs() {
    return _serialized(() async {
      final file = await _file();
      final records = await _readRecords(file);
      var recovered = 0;
      final updated = <LocationRecord>[];

      for (final record in records) {
        if (record.status == SyncStatus.syncing) {
          recovered += 1;
          updated.add(
            record.copyWith(
              status: SyncStatus.pending,
              lastError: 'Interrupted before upload confirmation',
            ),
          );
        } else {
          updated.add(record);
        }
      }

      if (recovered > 0) {
        await _writeRecords(file, updated);
      }
      return recovered;
    });
  }
}
