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

  LocationRecord buildRecord(String id) {
    return LocationRecord(
      id: id,
      latitude: 12.97,
      longitude: 77.59,
      accuracyMeters: 10,
      capturedAt: DateTime.utc(2026, 11, 24, 12, 0, 0),
      status: SyncStatus.pending,
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

  test('persists pending records offline and survives store reload', () async {
    final api = InMemoryLocationApiClient();
    final service = await createService(api: api, online: false);
    addTearDown(service.dispose);

    await service.ingest(buildRecord('point-1'));
    await service.ingest(buildRecord('point-2'));

    final pending = await store.pendingRecords();
    expect(pending.map((record) => record.id), ['point-1', 'point-2']);
    expect(api.acceptedIds, isEmpty);

    // New store instance reading the same file after "restart".
    final reloaded = FileLocationLocalStore(overrideDirectory: tempDir);
    final afterRestart = await reloaded.loadAll();
    expect(afterRestart.length, 2);
    expect(afterRestart.every((record) => record.isPending), isTrue);
  });

  test('syncs pending records when connectivity returns and retries failures',
      () async {
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
    await service.ingest(record); // duplicate ingest ignored
    await service.syncPending(); // second sync should be idempotent

    expect(api.acceptedIds, {'stable-id'});
    expect(api.attemptsFor('stable-id'), 1);

    final records = await store.loadAll();
    expect(records.where((item) => item.id == 'stable-id'), hasLength(1));
    expect(records.single.status, SyncStatus.synced);
  });
}
