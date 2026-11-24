import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:driver_location_sync/data/connectivity/connectivity_monitor.dart';
import 'package:driver_location_sync/data/local/location_local_store.dart';
import 'package:driver_location_sync/data/location/location_source.dart';
import 'package:driver_location_sync/data/remote/location_api_client.dart';
import 'package:driver_location_sync/domain/location_sync_service.dart';
import 'package:driver_location_sync/presentation/cubit/tracking_cubit.dart';
import 'package:driver_location_sync/presentation/pages/tracking_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localStore = FileLocationLocalStore();
  final apiClient = MockHttpLocationApiClient(failureRate: 0.15);
  final connectivity = ConnectivityPlusMonitor();
  final syncService = LocationSyncService(
    localStore: localStore,
    apiClient: apiClient,
    connectivityMonitor: connectivity,
  );

  runApp(DriverLocationSyncApp(syncService: syncService));
}

class DriverLocationSyncApp extends StatelessWidget {
  const DriverLocationSyncApp({
    required this.syncService,
    super.key,
  });

  final LocationSyncService syncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Location Sync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (_) => TrackingCubit(
          syncService: syncService,
          simulatedSource: SimulatedLocationSource(),
          deviceSource: GeolocatorLocationSource(),
        )..initialize(),
        child: const TrackingPage(),
      ),
    );
  }
}
