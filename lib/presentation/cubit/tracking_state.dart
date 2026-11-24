import 'package:equatable/equatable.dart';

import 'package:driver_location_sync/models/location_record.dart';

enum TrackingMode { simulated, device }

class TrackingState extends Equatable {
  const TrackingState({
    this.isTracking = false,
    this.isOnline = true,
    this.isSyncing = false,
    this.mode = TrackingMode.simulated,
    this.records = const [],
    this.message,
  });

  final bool isTracking;
  final bool isOnline;
  final bool isSyncing;
  final TrackingMode mode;
  final List<LocationRecord> records;
  final String? message;

  int get pendingCount =>
      records.where((record) => record.isPending).length;

  int get syncedCount =>
      records.where((record) => record.status == SyncStatus.synced).length;

  TrackingState copyWith({
    bool? isTracking,
    bool? isOnline,
    bool? isSyncing,
    TrackingMode? mode,
    List<LocationRecord>? records,
    String? message,
    bool clearMessage = false,
  }) {
    return TrackingState(
      isTracking: isTracking ?? this.isTracking,
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      mode: mode ?? this.mode,
      records: records ?? this.records,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  List<Object?> get props =>
      [isTracking, isOnline, isSyncing, mode, records, message];
}
