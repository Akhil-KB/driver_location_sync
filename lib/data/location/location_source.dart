import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'package:driver_location_sync/models/location_record.dart';

abstract class LocationSource {
  Stream<LocationRecord> watchLocations();

  Future<void> stop();
}

/// Device GPS source.
class GeolocatorLocationSource implements LocationSource {
  GeolocatorLocationSource({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  StreamSubscription<Position>? _subscription;
  StreamController<LocationRecord>? _controller;

  @override
  Stream<LocationRecord> watchLocations() {
    _controller?.close();
    final controller = StreamController<LocationRecord>.broadcast();
    _controller = controller;

    () async {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        controller.addError(
          StateError('Location services are disabled on this device.'),
        );
        await controller.close();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        controller.addError(
          StateError('Location permission was denied.'),
        );
        await controller.close();
        return;
      }

      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (position) {
          controller.add(
            LocationRecord(
              id: _uuid.v4(),
              latitude: position.latitude,
              longitude: position.longitude,
              accuracyMeters: position.accuracy,
              capturedAt: position.timestamp,
              status: SyncStatus.pending,
            ),
          );
        },
        onError: controller.addError,
      );
    }();

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller?.close();
    _controller = null;
  }
}

/// Simulated GPS path for desktop / demo use.
class SimulatedLocationSource implements LocationSource {
  SimulatedLocationSource({
    Uuid? uuid,
    this.interval = const Duration(seconds: 2),
    Random? random,
  })  : _uuid = uuid ?? const Uuid(),
        _random = random ?? Random();

  final Uuid _uuid;
  final Duration interval;
  final Random _random;

  Timer? _timer;
  StreamController<LocationRecord>? _controller;
  int _tick = 0;

  // Demo starting point (Bengaluru).
  static const double _baseLat = 12.9716;
  static const double _baseLng = 77.5946;

  @override
  Stream<LocationRecord> watchLocations() {
    stop();
    final controller = StreamController<LocationRecord>.broadcast();
    _controller = controller;
    _tick = 0;

    _timer = Timer.periodic(interval, (_) {
      final offset = _tick * 0.00012;
      final jitterLat = (_random.nextDouble() - 0.5) * 0.00005;
      final jitterLng = (_random.nextDouble() - 0.5) * 0.00005;
      _tick += 1;

      controller.add(
        LocationRecord(
          id: _uuid.v4(),
          latitude: _baseLat + offset + jitterLat,
          longitude: _baseLng + offset + jitterLng,
          accuracyMeters: 8 + _random.nextDouble() * 4,
          capturedAt: DateTime.now().toUtc(),
          status: SyncStatus.pending,
        ),
      );
    });

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller?.close();
    _controller = null;
  }
}
