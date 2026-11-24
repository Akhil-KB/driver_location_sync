import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:driver_location_sync/models/location_record.dart';
import 'package:driver_location_sync/presentation/cubit/tracking_cubit.dart';
import 'package:driver_location_sync/presentation/cubit/tracking_state.dart';

class TrackingPage extends StatelessWidget {
  const TrackingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Location Sync'),
      ),
      body: BlocBuilder<TrackingCubit, TrackingState>(
        builder: (context, state) {
          return Column(
            children: [
              _StatusHeader(state: state),
              _Controls(state: state),
              const Divider(height: 1),
              Expanded(
                child: state.records.isEmpty
                    ? const Center(
                        child: Text(
                          'No locations yet.\nStart tracking to capture points.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: state.records.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _LocationTile(record: state.records[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                label: state.isTracking ? 'Tracking ON' : 'Tracking OFF',
                color: state.isTracking ? Colors.green : Colors.grey,
              ),
              _Chip(
                label: state.isOnline ? 'Online' : 'Offline',
                color: state.isOnline ? Colors.blue : Colors.orange,
              ),
              _Chip(
                label: 'Pending ${state.pendingCount}',
                color: Colors.deepOrange,
              ),
              _Chip(
                label: 'Synced ${state.syncedCount}',
                color: Colors.teal,
              ),
            ],
          ),
          if (state.message != null) ...[
            const SizedBox(height: 12),
            Text(state.message!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TrackingCubit>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SegmentedButton<TrackingMode>(
            segments: const [
              ButtonSegment(
                value: TrackingMode.simulated,
                label: Text('Simulated GPS'),
                icon: Icon(Icons.route),
              ),
              ButtonSegment(
                value: TrackingMode.device,
                label: Text('Device GPS'),
                icon: Icon(Icons.gps_fixed),
              ),
            ],
            selected: {state.mode},
            onSelectionChanged: state.isTracking
                ? null
                : (selection) => cubit.setMode(selection.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isTracking
                      ? null
                      : () => cubit.startTracking(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      state.isTracking ? () => cubit.stopTracking() : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isSyncing ? null : () => cubit.syncNow(),
                  icon: state.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Sync'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.record});

  final LocationRecord record;

  Color _statusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return Colors.orange;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          '${record.latitude.toStringAsFixed(5)}, '
          '${record.longitude.toStringAsFixed(5)}',
        ),
        subtitle: Text(
          [
            'id: ${record.id.substring(0, 8)}…',
            'acc: ${record.accuracyMeters.toStringAsFixed(1)} m',
            'at: ${record.capturedAt.toLocal()}',
            if (record.retryCount > 0) 'retries: ${record.retryCount}',
            if (record.lastError != null) 'error: ${record.lastError}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Text(
          record.status.name.toUpperCase(),
          style: TextStyle(
            color: _statusColor(record.status),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
