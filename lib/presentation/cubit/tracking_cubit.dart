import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:driver_location_sync/data/location/location_source.dart';
import 'package:driver_location_sync/domain/location_sync_service.dart';
import 'package:driver_location_sync/models/location_record.dart';
import 'package:driver_location_sync/presentation/cubit/tracking_state.dart';

class TrackingCubit extends Cubit<TrackingState> {
  TrackingCubit({
    required LocationSyncService syncService,
    required LocationSource simulatedSource,
    required LocationSource deviceSource,
  })  : _syncService = syncService,
        _simulatedSource = simulatedSource,
        _deviceSource = deviceSource,
        super(const TrackingState());

  final LocationSyncService _syncService;
  final LocationSource _simulatedSource;
  final LocationSource _deviceSource;

  StreamSubscription<List<LocationRecord>>? _recordsSubscription;
  StreamSubscription<LocationRecord>? _locationSubscription;
  LocationSource? _activeSource;
  Future<void> _ingestQueue = Future<void>.value();

  Future<void> initialize() async {
    await _syncService.initialize();
    _recordsSubscription = _syncService.recordsStream.listen((records) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          records: records,
          isOnline: _syncService.isOnline,
        ),
      );
    });

    final initial = await _syncService.currentRecords();
    if (!isClosed) {
      emit(
        state.copyWith(
          records: initial,
          isOnline: _syncService.isOnline,
        ),
      );
    }
  }

  void setMode(TrackingMode mode) {
    if (state.isTracking) {
      emit(
        state.copyWith(
          message: 'Stop tracking before switching GPS mode.',
        ),
      );
      return;
    }
    emit(state.copyWith(mode: mode, clearMessage: true));
  }

  Future<void> startTracking() async {
    if (state.isTracking) {
      return;
    }

    await _stopLocationStream();
    final source = state.mode == TrackingMode.simulated
        ? _simulatedSource
        : _deviceSource;
    _activeSource = source;

    emit(
      state.copyWith(
        isTracking: true,
        clearMessage: true,
        message: state.mode == TrackingMode.simulated
            ? 'Simulated GPS tracking started.'
            : 'Device GPS tracking started.',
      ),
    );

    _locationSubscription = source.watchLocations().listen(
      (record) {
        _ingestQueue = _ingestQueue.then((_) async {
          await _syncService.ingest(record);
        });
      },
      onError: (Object error) {
        emit(
          state.copyWith(
            isTracking: false,
            message: error.toString(),
          ),
        );
      },
    );
  }

  Future<void> stopTracking() async {
    await _stopLocationStream();
    emit(
      state.copyWith(
        isTracking: false,
        message: 'Tracking stopped. Pending points remain stored offline.',
      ),
    );
  }

  Future<void> syncNow() async {
    emit(state.copyWith(isSyncing: true, clearMessage: true));
    try {
      await _syncService.syncPending();
      if (!isClosed) {
        emit(
          state.copyWith(
            isSyncing: false,
            isOnline: _syncService.isOnline,
            message: 'Manual sync completed.',
          ),
        );
      }
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            isSyncing: false,
            message: 'Sync failed: $error',
          ),
        );
      }
    }
  }

  Future<void> _stopLocationStream() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    await _activeSource?.stop();
    _activeSource = null;
    await _ingestQueue;
  }

  @override
  Future<void> close() async {
    await _stopLocationStream();
    await _recordsSubscription?.cancel();
    await _syncService.dispose();
    return super.close();
  }
}
