import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:driver_location_sync/models/location_record.dart';
import 'package:http/http.dart' as http;

class LocationUploadException implements Exception {
  LocationUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uploads location points to a mock REST endpoint.
abstract class LocationApiClient {
  Future<void> upload(LocationRecord record);

  Set<String> get acceptedIds;
}

class MockHttpLocationApiClient implements LocationApiClient {
  MockHttpLocationApiClient({
    http.Client? httpClient,
    this.endpoint = 'https://httpbin.org/post',
    this.forceOffline = false,
    this.failureRate = 0.2,
    Random? random,
  })  : _httpClient = httpClient ?? http.Client(),
        _random = random ?? Random();

  final http.Client _httpClient;
  final String endpoint;
  final bool forceOffline;
  final double failureRate;
  final Random _random;
  final Set<String> _acceptedIds = <String>{};

  @override
  Set<String> get acceptedIds => Set.unmodifiable(_acceptedIds);

  @override
  Future<void> upload(LocationRecord record) async {
    if (forceOffline) {
      throw LocationUploadException('Network unavailable');
    }

    // Occasional failures exercise retry handling.
    if (_random.nextDouble() < failureRate) {
      throw LocationUploadException('Simulated upload failure');
    }

    // Same id already accepted -> treat as success.
    if (_acceptedIds.contains(record.id)) {
      return;
    }

    final response = await _httpClient.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Idempotency-Key': record.id,
      },
      body: jsonEncode(record.toApiPayload()),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocationUploadException(
        'Upload failed with status ${response.statusCode}',
      );
    }

    _acceptedIds.add(record.id);
  }

  void dispose() {
    _httpClient.close();
  }
}

/// In-memory client for tests.
class InMemoryLocationApiClient implements LocationApiClient {
  InMemoryLocationApiClient({
    this.failUntilAttempt = 0,
    this.alwaysFail = false,
  });

  final int failUntilAttempt;
  final bool alwaysFail;
  final Map<String, int> _attemptsById = <String, int>{};
  final Set<String> _acceptedIds = <String>{};

  @override
  Set<String> get acceptedIds => Set.unmodifiable(_acceptedIds);

  @override
  Future<void> upload(LocationRecord record) async {
    final attempt = (_attemptsById[record.id] ?? 0) + 1;
    _attemptsById[record.id] = attempt;

    if (alwaysFail || attempt <= failUntilAttempt) {
      throw LocationUploadException('Upload failed on attempt $attempt');
    }

    if (_acceptedIds.contains(record.id)) {
      return;
    }

    _acceptedIds.add(record.id);
  }

  int attemptsFor(String id) => _attemptsById[id] ?? 0;
}
