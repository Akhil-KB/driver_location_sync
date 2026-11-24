enum SyncStatus { pending, syncing, synced, failed }

class LocationRecord {
  const LocationRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.status,
    this.retryCount = 0,
    this.lastError,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;

  bool get isPending =>
      status == SyncStatus.pending || status == SyncStatus.failed;

  LocationRecord copyWith({
    SyncStatus? status,
    int? retryCount,
    String? lastError,
    bool clearError = false,
  }) {
    return LocationRecord(
      id: id,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      capturedAt: capturedAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'capturedAt': capturedAt.toIso8601String(),
      'status': status.name,
      'retryCount': retryCount,
      'lastError': lastError,
    };
  }

  Map<String, dynamic> toApiPayload() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  factory LocationRecord.fromJson(Map<String, dynamic> json) {
    return LocationRecord(
      id: json['id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      status: SyncStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
    );
  }
}
