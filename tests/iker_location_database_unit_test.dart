import 'package:test/test.dart';
import 'package:location_engine/location_engine.dart';

void main() {
  group('iker: location tracking + database access contract', () {
    test(
      'when user enters a relevant area, app queries Cloud DB for nearby curated POIs using a bounded radius and small candidate limit',
      () async {
        // Arrange
        final fakeDb = _FakeCloudDb();
        final fakeLocationApi = _FakeUserLocationApi();
        final engine = LocationEngine(
          locationApi: fakeLocationApi,
          poiDatabase: fakeDb,
        );

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
        final fakeLocationApi = _FakeUserLocationApi();
        final engine = LocationEngine(
          locationApi: fakeLocationApi,
          poiDatabase: fakeDb,
        );

        // Act + Assert
        final candidates = await engine.onLocationUpdate(
          latitude: 37.8087,
          longitude: -122.4098,
        );

        expect(candidates, isEmpty, reason: 'On transient DB failures, location loop should degrade safely');
      },
    );

    test(
      'when location permission is denied, app requests consent and avoids DB query if user still does not allow',
      () async {
        // Arrange
        final fakeDb = _FakeCloudDb();
        final fakeLocationApi = _FakeUserLocationApi(
          initialPermission: LocationPermissionStatus.denied,
          requestPermissionResult: LocationPermissionStatus.denied,
        );
        final engine = LocationEngine(
          locationApi: fakeLocationApi,
          poiDatabase: fakeDb,
        );

        // Act
        final candidates = await engine.onLocationUpdate(
          latitude: 37.7946,
          longitude: -122.3999,
        );

        // Assert
        expect(candidates, isEmpty, reason: 'No consent means no location-driven POI lookup');
        expect(fakeLocationApi.requestCount, 1, reason: 'App should explicitly ask user for consent');
        expect(fakeDb.queryCallCount, 0, reason: 'DB should not be queried without location permission');
      },
    );

    test(
      'when location services are disabled on device, app returns empty candidates without prompting DB',
      () async {
        // Arrange
        final fakeDb = _FakeCloudDb();
        final fakeLocationApi = _FakeUserLocationApi(locationServiceEnabled: false);
        final engine = LocationEngine(
          locationApi: fakeLocationApi,
          poiDatabase: fakeDb,
        );

        // Act
        final candidates = await engine.onLocationUpdate(
          latitude: 37.7929,
          longitude: -122.3969,
        );

        // Assert
        expect(candidates, isEmpty, reason: 'App should not continue while OS location services are off');
        expect(fakeLocationApi.requestCount, 0, reason: 'Permission prompt is pointless when service is disabled');
        expect(fakeDb.queryCallCount, 0, reason: 'DB should not be queried before location services are available');
      },
    );

    test(
      'when consent is granted, app can read current user location from location API',
      () async {
        // Arrange
        final fakeDb = _FakeCloudDb();
        final fakeLocationApi = _FakeUserLocationApi(
          currentPosition: const GeoPoint(latitude: 37.7749, longitude: -122.4194),
        );
        final engine = LocationEngine(
          locationApi: fakeLocationApi,
          poiDatabase: fakeDb,
        );

        // Act
        final currentLocation = await engine.getCurrentUserLocation();

        // Assert
        expect(currentLocation, isNotNull);
        expect(currentLocation!.latitude, closeTo(37.7749, 0.00001));
        expect(currentLocation.longitude, closeTo(-122.4194, 0.00001));
      },
    );
  });
}

class _FakeCloudDb implements PoiDatabaseApi {
  _FakeCloudDb({this.shouldThrow = false});

  final bool shouldThrow;
  int queryCallCount = 0;
  double? lastRadiusMeters;
  int? lastLimit;

  @override
  Future<List<PoiCandidate>> fetchNearbyPois({
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

    return <PoiCandidate>[
      const PoiCandidate(
        id: 'ferry-building',
        latitude: 37.7955,
        longitude: -122.3937,
        title: 'Ferry Building',
      ),
      const PoiCandidate(
        id: 'coit-tower',
        latitude: 37.8024,
        longitude: -122.4058,
        title: 'Coit Tower',
      ),
    ];
  }
}

class _FakeUserLocationApi implements UserLocationApi {
  _FakeUserLocationApi({
    this.locationServiceEnabled = true,
    this.initialPermission = LocationPermissionStatus.granted,
    this.requestPermissionResult = LocationPermissionStatus.granted,
    this.currentPosition = const GeoPoint(latitude: 37.7955, longitude: -122.3937),
  });

  final bool locationServiceEnabled;
  final LocationPermissionStatus initialPermission;
  final LocationPermissionStatus requestPermissionResult;
  final GeoPoint currentPosition;
  int requestCount = 0;

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    return initialPermission;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return locationServiceEnabled;
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    requestCount += 1;
    return requestPermissionResult;
  }

  @override
  Future<GeoPoint> getCurrentPosition() async {
    return currentPosition;
  }
}
