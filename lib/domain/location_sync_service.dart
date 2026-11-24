import 'dart:async';

import 'package:driver_location_sync/data/connectivity/connectivity_monitor.dart';
import 'package:driver_location_sync/data/local/location_local_store.dart';
import 'package:driver_location_sync/data/remote/location_api_client.dart';
import 'package:driver_location_sync/models/location_record.dart';

/// Offline-first sync:
/// 1) persist every point locally
/// 2) upload only after disk write succeeds
/// 3) retry with the same id until acknowledged
class LocationSyncService {
  LocationSyncService({
    required LocationLocalStore localStore,
    required LocationApiClient apiClient,
    required ConnectivityMonitor connectivityMonitor,
    this.maxRetries = 5,
  })  : _localStore = localStore,
        _apiClient = apiClient,
        _connectivityMonitor = connectivityMonitor;

  final LocationLocalStore _localStore;
  final LocationApiClient _apiClient;
  final ConnectivityMonitor _connectivityMonitor;
  final int maxRetries;

  final _recordsController =
      StreamController<List<LocationRecord>>.broadcast();
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _activeSync;
  bool _isOnline = true;
  bool _dirtyDuringSync = false;

  Stream<List<LocationRecord>> get recordsStream => _recordsController.stream;

  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    await _localStore.recoverInterruptedSyncs();
    _isOnline = await _connectivityMonitor.isOnline;
    await _emitRecords();

    _connectivitySubscription =
        _connectivityMonitor.onStatusChanged.listen((online) async {
      _isOnline = online;
      if (online) {
        await syncPending();
      } else {
        await _emitRecords();
      }
    });

    if (_isOnline) {
      await syncPending();
    }
  }

  Future<void> ingest(LocationRecord record) async {
    final existing = await _localStore.loadAll();
    if (existing.any((item) => item.id == record.id)) {
      return;
    }

    final pending =
        record.copyWith(status: SyncStatus.pending, clearError: true);
    await _localStore.upsert(pending);
    await _emitRecords();

    if (_isOnline) {
      if (_activeSync != null) {
        _dirtyDuringSync = true;
      } else {
        await syncPending();
      }
    }
  }

  Future<void> syncPending() {
    return _activeSync ??= _runSync().whenComplete(() {
      _activeSync = null;
    });
  }

  Future<void> _runSync() async {
    do {
      _dirtyDuringSync = false;

      if (!await _connectivityMonitor.isOnline) {
        _isOnline = false;
        await _emitRecords();
        return;
      }

      _isOnline = true;
      final pending = await _localStore.pendingRecords();
      for (final original in pending) {
        var current = original;

        while (current.isPending && current.retryCount < maxRetries) {
          if (!await _connectivityMonitor.isOnline) {
            _isOnline = false;
            await _emitRecords();
            return;
          }

          final syncing =
              current.copyWith(status: SyncStatus.syncing, clearError: true);
          await _localStore.upsert(syncing);
          await _emitRecords();

          try {
            await _apiClient.upload(syncing);
            current =
                syncing.copyWith(status: SyncStatus.synced, clearError: true);
            await _localStore.upsert(current);
            await _emitRecords();
            break;
          } catch (error) {
            final failure = error is LocationUploadException
                ? error
                : LocationUploadException(error.toString());

            current = current.copyWith(
              status: SyncStatus.failed,
              retryCount: current.retryCount + 1,
              lastError: failure.message,
            );
            await _localStore.upsert(current);
            await _emitRecords();

            if (failure.isConnectivityIssue) {
              _isOnline = false;
              return;
            }

            if (current.retryCount < maxRetries) {
              final delayMs = (150 * (1 << (current.retryCount - 1))).clamp(
                150,
                2000,
              );
              await Future<void>.delayed(Duration(milliseconds: delayMs));
            }
          }
        }
      }
    } while (_dirtyDuringSync);

    await _emitRecords();
  }

  Future<List<LocationRecord>> currentRecords() => _localStore.loadAll();

  Future<void> _emitRecords() async {
    final records = await _localStore.loadAll();
    records.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    if (!_recordsController.isClosed) {
      _recordsController.add(List<LocationRecord>.unmodifiable(records));
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _recordsController.close();
  }
}
