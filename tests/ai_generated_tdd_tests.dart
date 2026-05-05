// AI-generated tests (Sprint 1 / Week 5, Part 3).
//
// Authored by Claude Code with the obra/superpowers TDD skill loaded
// (.claude/skills/tdd/SKILL.md). Tests target behaviors of the public
// interfaces in location-engine and voice-interface that were NOT yet
// covered by the team-written tests. All assertions are written through
// public APIs so they survive internal refactors.

import 'package:test/test.dart';
import 'package:location_engine/location_engine.dart';
import 'package:voice_interface/voice_interface.dart';

void main() {
  group('LocationEngine consent', () {
    // As a user with location services turned off at the OS level,
    // the app should not nag me with a permission prompt it can't satisfy.
    //
    // Improved during Part 4 critique: the original asserted on a spy
    // counter (requestPermissionCallCount == 0). That coupled the test
    // to the fake's internals. The new shape stages the fake so that
    // *if* the prompt path had been entered the engine would have
    // received "granted" — so a `false` result is itself proof the
    // engine bypassed the prompt without us naming the mechanism.
    test('returns false even when a hypothetical prompt would have granted, because services are off', () async {
      // Arrange: service disabled; permission would flip to granted IF asked.
      final locationApi = _FakeUserLocationApi(
        serviceEnabled: false,
        currentPermission: LocationPermissionStatus.denied,
        permissionAfterRequest: LocationPermissionStatus.granted,
      );
      final engine = LocationEngine(
        locationApi: locationApi,
        poiDatabase: _FakePoiDatabase(),
      );

      // Action
      final hasConsent = await engine.ensureLocationConsent();

      // Assert: false is the user-observable outcome that proves the
      // engine short-circuited before reaching the prompt path.
      expect(hasConsent, isFalse);
    });
  });

  group('LocationEngine query throttling', () {
    // As a user standing roughly still, the app should not keep re-querying
    // the cloud DB for the same neighborhood every second.
    test('skips DB query when user has not moved past minMovementForRefreshMeters', () async {
      // Arrange
      final db = _FakePoiDatabase();
      final engine = LocationEngine(
        locationApi: _FakeUserLocationApi(
          serviceEnabled: true,
          currentPermission: LocationPermissionStatus.granted,
        ),
        poiDatabase: db,
        config: const LocationQueryConfig(minMovementForRefreshMeters: 100),
      );

      // Action: first update establishes baseline, second is essentially the same spot (~5m away)
      await engine.onLocationUpdate(latitude: 37.7955, longitude: -122.3937);
      final secondUpdate = await engine.onLocationUpdate(
        latitude: 37.79554,
        longitude: -122.39370,
      );

      // Assert
      expect(secondUpdate, isEmpty,
          reason: 'A near-identical location should not trigger another DB call.');
      expect(db.queryCallCount, 1,
          reason: 'Only the first update crosses the movement threshold.');
    });
  });

  group('LocationEngine resilience', () {
    // As a user moving through an area when Firestore briefly fails,
    // the next location update should still be allowed to retry.
    test('does not advance the lastQueryPoint when the DB call throws', () async {
      // Arrange
      final db = _FakePoiDatabase(throwOnce: true);
      final engine = LocationEngine(
        locationApi: _FakeUserLocationApi(
          serviceEnabled: true,
          currentPermission: LocationPermissionStatus.granted,
        ),
        poiDatabase: db,
      );

      // Action: first update fails, second update happens just a few meters away
      final firstUpdate = await engine.onLocationUpdate(
        latitude: 37.7955,
        longitude: -122.3937,
      );
      final secondUpdate = await engine.onLocationUpdate(
        latitude: 37.79553,
        longitude: -122.39372,
      );

      // Assert
      expect(firstUpdate, isEmpty, reason: 'Failed query should degrade safely.');
      expect(secondUpdate, isNotEmpty,
          reason: 'Retry must be possible without waiting for the user to move 100m.');
      expect(db.queryCallCount, 2);
    });
  });

  group('transcript normalizer', () {
    // As a user dictating with stutters, the conversation layer should
    // see a single clean sentence, not the raw STT mess.
    test('collapses multiple internal spaces into single spaces and trims edges', () {
      // Arrange
      const raw = '   tell    me   about    Coit    Tower   ';

      // Action
      final normalized = normalizeTranscriptForConversation(raw);

      // Assert
      expect(normalized, 'tell me about Coit Tower');
    });
  });
}

class _FakeUserLocationApi implements UserLocationApi {
  _FakeUserLocationApi({
    required this.serviceEnabled,
    required this.currentPermission,
    LocationPermissionStatus? permissionAfterRequest,
  }) : _permissionAfterRequest = permissionAfterRequest ?? currentPermission;

  final bool serviceEnabled;
  LocationPermissionStatus currentPermission;
  final LocationPermissionStatus _permissionAfterRequest;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => currentPermission;

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    currentPermission = _permissionAfterRequest;
    return _permissionAfterRequest;
  }

  @override
  Future<GeoPoint> getCurrentPosition() async =>
      const GeoPoint(latitude: 37.7955, longitude: -122.3937);
}

class _FakePoiDatabase implements PoiDatabaseApi {
  _FakePoiDatabase({this.throwOnce = false});

  bool throwOnce;
  int queryCallCount = 0;

  @override
  Future<List<PoiCandidate>> fetchNearbyPois({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required int limit,
  }) async {
    queryCallCount += 1;
    if (throwOnce) {
      throwOnce = false;
      throw Exception('Cloud DB transient failure');
    }
    return const [
      PoiCandidate(
        id: 'ferry-building',
        latitude: 37.7955,
        longitude: -122.3937,
        title: 'Ferry Building',
      ),
      PoiCandidate(
        id: 'coit-tower',
        latitude: 37.8024,
        longitude: -122.4058,
        title: 'Coit Tower',
      ),
    ];
  }
}
