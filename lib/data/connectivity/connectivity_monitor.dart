import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

abstract class ConnectivityMonitor {
  Future<bool> get isOnline;

  Stream<bool> get onStatusChanged;
}

class ConnectivityPlusMonitor implements ConnectivityMonitor {
  ConnectivityPlusMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  bool _hasConnection(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return false;
    }
    return results.any((result) => result != ConnectivityResult.none);
  }

  @override
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return _hasConnection(results);
  }

  @override
  Stream<bool> get onStatusChanged {
    return _connectivity.onConnectivityChanged.map(_hasConnection);
  }
}

class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor({bool initiallyOnline = true})
      : _isOnline = initiallyOnline;

  bool _isOnline;
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _isOnline;

  @override
  Stream<bool> get onStatusChanged => _controller.stream;

  void setOnline(bool value) {
    _isOnline = value;
    _controller.add(value);
  }

  Future<void> dispose() => _controller.close();
}
