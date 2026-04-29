import 'dart:math' as math;

enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
}

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class PoiCandidate {
  const PoiCandidate({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.title,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String title;
}

abstract class UserLocationApi {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermissionStatus> checkPermission();
  Future<LocationPermissionStatus> requestPermission();
  Future<GeoPoint> getCurrentPosition();
}

abstract class PoiDatabaseApi {
  Future<List<PoiCandidate>> fetchNearbyPois({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required int limit,
  });
}

class LocationQueryConfig {
  const LocationQueryConfig({
    this.radiusMeters = 600,
    this.limit = 10,
    this.minMovementForRefreshMeters = 100,
  });

  final double radiusMeters;
  final int limit;
  final double minMovementForRefreshMeters;
}

class LocationEngine {
  LocationEngine({
    required UserLocationApi locationApi,
    required PoiDatabaseApi poiDatabase,
    this.config = const LocationQueryConfig(),
  })  : _locationApi = locationApi,
        _poiDatabase = poiDatabase;

  final UserLocationApi _locationApi;
  final PoiDatabaseApi _poiDatabase;
  final LocationQueryConfig config;
  GeoPoint? _lastQueryPoint;

  /// Requests user consent and validates platform location readiness.
  Future<bool> ensureLocationConsent() async {
    final serviceEnabled = await _locationApi.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    final currentPermission = await _locationApi.checkPermission();
    if (currentPermission == LocationPermissionStatus.granted) {
      return true;
    }

    if (currentPermission == LocationPermissionStatus.deniedForever) {
      return false;
    }

    final requestedPermission = await _locationApi.requestPermission();
    return requestedPermission == LocationPermissionStatus.granted;
  }

  /// Reads the user's current location only when consent and OS service checks pass.
  Future<GeoPoint?> getCurrentUserLocation() async {
    final hasConsent = await ensureLocationConsent();
    if (!hasConsent) {
      return null;
    }

    try {
      return await _locationApi.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Handles geofence-like trigger behavior from location updates.
  ///
  /// Returns an empty list when:
  /// - consent/service checks fail
  /// - user has not moved enough since the previous query
  /// - Cloud DB access fails transiently
  Future<List<PoiCandidate>> onLocationUpdate({
    required double latitude,
    required double longitude,
  }) async {
    final hasConsent = await ensureLocationConsent();
    if (!hasConsent) {
      return <PoiCandidate>[];
    }

    final currentPoint = GeoPoint(latitude: latitude, longitude: longitude);
    final shouldQuery = _lastQueryPoint == null ||
        _distanceMeters(_lastQueryPoint!, currentPoint) >= config.minMovementForRefreshMeters;

    if (!shouldQuery) {
      return <PoiCandidate>[];
    }

    try {
      final results = await _poiDatabase.fetchNearbyPois(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: config.radiusMeters,
        limit: config.limit,
      );
      _lastQueryPoint = currentPoint;
      return results;
    } catch (_) {
      return <PoiCandidate>[];
    }
  }
}

double _distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _toRadians(b.latitude - a.latitude);
  final dLon = _toRadians(b.longitude - a.longitude);
  final lat1 = _toRadians(a.latitude);
  final lat2 = _toRadians(b.latitude);

  final haversine = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  final centralAngle = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMeters * centralAngle;
}

double _toRadians(double degrees) {
  return degrees * (math.pi / 180.0);
}
