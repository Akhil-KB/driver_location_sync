import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:driver_location_sync/data/connectivity/connectivity_monitor.dart';
import 'package:driver_location_sync/data/local/location_local_store.dart';
import 'package:driver_location_sync/data/remote/location_api_client.dart';
import 'package:driver_location_sync/domain/location_sync_service.dart';
import 'package:driver_location_sync/models/location_record.dart';

void main() {
  late Directory tempDir;
  late FileLocationLocalStore store;
  late FakeConnectivityMonitor connectivity;

  LocationRecord buildRecord(
    String id, {
    DateTime? capturedAt,
    SyncStatus status = SyncStatus.pending,
  }) {
    return LocationRecord(
      id: id,
      latitude: 12.97,
      longitude: 77.59,
      accuracyMeters: 10,
      capturedAt: capturedAt ?? DateTime.utc(2026, 11, 24, 12, 0, 0),
      status: status,
    );
  }

  Future<LocationSyncService> createService({
    required LocationApiClient api,
    bool online = false,
  }) async {
    connectivity = FakeConnectivityMonitor(initiallyOnline: online);
    store = FileLocationLocalStore(overrideDirectory: tempDir);
    final service = LocationSyncService(
      localStore: store,
      apiClient: api,
      connectivityMonitor: connectivity,
    );
    await service.initialize();
    return service;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('driver_location_sync_');
  });

  tearDown(() async {
    await connectivity.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists pending records offline and survives app restart', () async {
    final api = InMemoryLocationApiClient();
    final service = await createService(api: api, online: false);
    addTearDown(service.dispose);

    await service.ingest(buildRecord('point-1'));
    await service.ingest(buildRecord('point-2'));

    final pending = await store.pendingRecords();
    expect(pending.map((record) => record.id), ['point-1', 'point-2']);
    expect(api.acceptedIds, isEmpty);

    final reloaded = FileLocationLocalStore(overrideDirectory: tempDir);
    final afterRestart = await reloaded.loadAll();
    expect(afterRestart.length, 2);
    expect(afterRestart.every((record) => record.isPending), isTrue);
  });

  test('recovers interrupted syncing records on startup', () async {
    store = FileLocationLocalStore(overrideDirectory: tempDir);
    await store.saveAll([
      buildRecord('stuck', status: SyncStatus.syncing),
    ]);

    final api = InMemoryLocationApiClient();
    final service = await createService(api: api, online: false);
    addTearDown(service.dispose);

    final records = await store.loadAll();
    expect(records.single.status, SyncStatus.pending);
    expect(records.single.lastError, contains('Interrupted'));
  });

  test('retries transient failures then syncs successfully', () async {
    final api = InMemoryLocationApiClient(failUntilAttempt: 1);
    final service = await createService(api: api, online: false);
    addTearDown(service.dispose);

    await service.ingest(buildRecord('retry-point'));
    expect(await store.pendingRecords(), hasLength(1));

    connectivity.setOnline(true);
    await service.syncPending();

    final records = await store.loadAll();
    expect(records.single.status, SyncStatus.synced);
    expect(api.acceptedIds, {'retry-point'});
    expect(api.attemptsFor('retry-point'), greaterThanOrEqualTo(2));
  });

  test('prevents duplicate submissions using stable record ids', () async {
    final api = InMemoryLocationApiClient();
    final service = await createService(api: api, online: true);
    addTearDown(service.dispose);

    final record = buildRecord('stable-id');
    await service.ingest(record);
    await service.ingest(record);
    await service.syncPending();

    expect(api.acceptedIds, {'stable-id'});
    expect(api.attemptsFor('stable-id'), 1);

    final records = await store.loadAll();
    expect(records.where((item) => item.id == 'stable-id'), hasLength(1));
    expect(records.single.status, SyncStatus.synced);
  });

  test('stops sync batch on connectivity loss and keeps remaining pending',
      () async {
    final api = InMemoryLocationApiClient(networkFailOnce: true);
    final service = await createService(api: api, online: true);
    addTearDown(service.dispose);

    await service.ingest(
      buildRecord('a', capturedAt: DateTime.utc(2026, 11, 24, 12, 0, 1)),
    );
    await service.ingest(
      buildRecord('b', capturedAt: DateTime.utc(2026, 11, 24, 12, 0, 2)),
    );

    final records = await store.loadAll();
    expect(records.any((record) => record.status == SyncStatus.failed), isTrue);
    expect(records.any((record) => record.isPending), isTrue);
    expect(api.acceptedIds.length, lessThan(2));
  });

  test('drains points ingested while a sync is already running', () async {
    final api = InMemoryLocationApiClient();
    final service = await createService(api: api, online: true);
    addTearDown(service.dispose);

    final first = service.ingest(buildRecord('first'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await service.ingest(buildRecord('second'));
    await first;
    await service.syncPending();

    final records = await store.loadAll();
    expect(records.every((record) => record.status == SyncStatus.synced), isTrue);
    expect(api.acceptedIds, {'first', 'second'});
  });
}
