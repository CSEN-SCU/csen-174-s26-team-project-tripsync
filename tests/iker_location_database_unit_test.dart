import 'package:test/test.dart';

void main() {
  group('iker: location tracking + database access contract', () {
    test(
      'when user enters a relevant area, app queries Cloud DB for nearby curated POIs using a bounded radius and small candidate limit',
      () async {
        // Arrange
        final fakeDb = _FakeCloudDb();
        final engine = _PendingLocationEngine(cloudDb: fakeDb);

        // Act
        final candidates = await engine.onLocationUpdate(
          latitude: 37.7955,
          longitude: -122.3937,
        );

        // Assert
        expect(candidates, isNotEmpty, reason: 'Nearby candidate list should be returned for ranking');
        expect(fakeDb.queryCallCount, 1, reason: 'A location update should trigger exactly one geo query');
        expect(fakeDb.lastRadiusMeters, lessThanOrEqualTo(1000), reason: 'Architecture requires local, radius-limited queries');
        expect(fakeDb.lastLimit, lessThanOrEqualTo(20), reason: 'Architecture requires a small candidate set for low latency');
      },
    );

    test(
      'when Cloud DB lookup fails, app handles it gracefully and returns no candidates instead of crashing',
      () async {
        // Arrange
        final fakeDb = _FakeCloudDb(shouldThrow: true);
        final engine = _PendingLocationEngine(cloudDb: fakeDb);

        // Act + Assert
        final candidates = await engine.onLocationUpdate(
          latitude: 37.8087,
          longitude: -122.4098,
        );

        expect(candidates, isEmpty, reason: 'On transient DB failures, location loop should degrade safely');
      },
    );
  });
}

class _PoiCandidate {
  _PoiCandidate(this.id);
  final String id;
}

class _FakeCloudDb {
  _FakeCloudDb({this.shouldThrow = false});

  final bool shouldThrow;
  int queryCallCount = 0;
  double? lastRadiusMeters;
  int? lastLimit;

  Future<List<_PoiCandidate>> fetchNearbyPois({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required int limit,
  }) async {
    queryCallCount += 1;
    lastRadiusMeters = radiusMeters;
    lastLimit = limit;

    if (shouldThrow) {
      throw Exception('Cloud DB unavailable');
    }

    return <_PoiCandidate>[
      _PoiCandidate('ferry-building'),
      _PoiCandidate('coit-tower'),
    ];
  }
}

/// Replace this adapter with your real location module implementation.
///
/// Intentionally returns red tests for now:
/// - architecture requires geofence/location-triggered DB lookup
/// - radius-limited nearby POI query
/// - graceful fallback on DB errors
class _PendingLocationEngine {
  _PendingLocationEngine({required _FakeCloudDb cloudDb}) : _cloudDb = cloudDb;

  final _FakeCloudDb _cloudDb;

  Future<List<_PoiCandidate>> onLocationUpdate({
    required double latitude,
    required double longitude,
  }) async {
    // TODO(iker): Replace with real geofence + DB integration call path.
    throw UnimplementedError(
      'Wire this test to the real location tracking + Cloud DB implementation (${_cloudDb.runtimeType}).',
    );

    // Example target behavior:
    // try {
    //   return await _cloudDb.fetchNearbyPois(
    //     latitude: latitude,
    //     longitude: longitude,
    //     radiusMeters: 600,
    //     limit: 10,
    //   );
    // } catch (_) {
    //   return <_PoiCandidate>[];
    // }
  }
}
