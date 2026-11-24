import 'package:flutter_test/flutter_test.dart';

import 'package:driver_location_sync/models/location_record.dart';

void main() {
  test('LocationRecord json round-trip keeps stable id and pending status', () {
    final record = LocationRecord(
      id: 'stable-id',
      latitude: 12.97,
      longitude: 77.59,
      accuracyMeters: 5,
      capturedAt: DateTime.utc(2026, 11, 24),
      status: SyncStatus.pending,
    );

    final restored = LocationRecord.fromJson(record.toJson());

    expect(restored.id, 'stable-id');
    expect(restored.isPending, isTrue);
    expect(restored.toApiPayload()['id'], 'stable-id');
  });
}
