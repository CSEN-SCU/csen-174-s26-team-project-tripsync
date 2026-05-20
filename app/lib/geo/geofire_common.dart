import 'dart:math' as math;

/// Geohash helpers compatible with [geofire-common] (used when seeding `pois`).
///
/// Ported from geofire-common v6 so Firestore `orderBy('geo.geohash')` queries
/// match the Node seed script and integration tests.
class GeofireCommon {
  GeofireCommon._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const int _geohashPrecision = 10;
  static const double _earthMeriCircumference = 40007860;
  static const double _metersPerDegreeLatitude = 110574;
  static const int _bitsPerChar = 5;
  static const int _maximumBitsPrecision = 22 * _bitsPerChar;
  static const double _earthEqRadius = 6378137.0;
  static const double _e2 = 0.00669447819799;
  static const double _epsilon = 1e-12;

  /// Encodes [latitude], [longitude] into a geohash string.
  static String geohashForLocation(double latitude, double longitude,
      {int precision = _geohashPrecision}) {
    var latitudeRange = (-90.0, 90.0);
    var longitudeRange = (-180.0, 180.0);
    var hash = '';
    var hashVal = 0;
    var bits = 0;
    var even = true;

    while (hash.length < precision) {
      final val = even ? longitude : latitude;
      final range = even ? longitudeRange : latitudeRange;
      final mid = (range.$1 + range.$2) / 2;

      if (val > mid) {
        hashVal = (hashVal << 1) + 1;
        if (even) {
          longitudeRange = (mid, longitudeRange.$2);
        } else {
          latitudeRange = (mid, latitudeRange.$2);
        }
      } else {
        hashVal = hashVal << 1;
        if (even) {
          longitudeRange = (longitudeRange.$1, mid);
        } else {
          latitudeRange = (latitudeRange.$1, mid);
        }
      }

      even = !even;
      if (bits < 4) {
        bits++;
      } else {
        bits = 0;
        hash += _base32[hashVal];
        hashVal = 0;
      }
    }

    return hash;
  }

  /// Returns `[start, end]` geohash pairs that cover a circle around [center].
  static List<(String start, String end)> geohashQueryBounds(
    (double latitude, double longitude) center,
    double radiusMeters,
  ) {
    final queryBits = math.max(1, _boundingBoxBits(center, radiusMeters));
    final geohashPrecision = (queryBits / _bitsPerChar).ceil();
    final coordinates = _boundingBoxCoordinates(center, radiusMeters);
    final queries = coordinates
        .map(
          (coordinate) => _geohashQuery(
            geohashForLocation(
              coordinate.$1,
              coordinate.$2,
              precision: geohashPrecision,
            ),
            queryBits,
          ),
        )
        .toList();

    final seen = <String>{};
    final unique = <(String start, String end)>[];
    for (final query in queries) {
      final key = '${query.$1}|${query.$2}';
      if (seen.add(key)) {
        unique.add(query);
      }
    }
    return unique;
  }

  /// Haversine distance in meters between two lat/lng pairs.
  static double distanceMeters(
    (double latitude, double longitude) a,
    (double latitude, double longitude) b,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(b.$1 - a.$1);
    final dLon = _degreesToRadians(b.$2 - a.$2);
    final lat1 = _degreesToRadians(a.$1);
    final lat2 = _degreesToRadians(b.$1);

    final haversine = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.pow(math.sin(dLon / 2), 2);
    final centralAngle =
        2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadiusMeters * centralAngle;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  static double _log2(double x) => math.log(x) / math.ln2;

  static double _metersToLongitudeDegrees(double distance, double latitude) {
    final radians = _degreesToRadians(latitude);
    final num =
        math.cos(radians) * _earthEqRadius * math.pi / 180;
    final denom =
        1 / math.sqrt(1 - _e2 * math.sin(radians) * math.sin(radians));
    final deltaDeg = num * denom;
    if (deltaDeg < _epsilon) {
      return distance > 0 ? 360 : 0;
    }
    return math.min(360, distance / deltaDeg);
  }

  static double _longitudeBitsForResolution(
    double resolution,
    double latitude,
  ) {
    final degs = _metersToLongitudeDegrees(resolution, latitude);
    return (degs.abs() > 0.000001) ? math.max(1, _log2(360 / degs)) : 1;
  }

  static double _latitudeBitsForResolution(double resolution) {
    return math.min(
      _log2(_earthMeriCircumference / 2 / resolution),
      _maximumBitsPrecision.toDouble(),
    );
  }

  static double _wrapLongitude(double longitude) {
    if (longitude <= 180 && longitude >= -180) {
      return longitude;
    }
    final adjusted = longitude + 180;
    if (adjusted > 0) {
      return (adjusted % 360) - 180;
    }
    return 180 - (-adjusted % 360);
  }

  static int _boundingBoxBits(
    (double latitude, double longitude) coordinate,
    double size,
  ) {
    final latDeltaDegrees = size / _metersPerDegreeLatitude;
    final latitudeNorth =
        math.min(90.0, coordinate.$1 + latDeltaDegrees).toDouble();
    final latitudeSouth =
        math.max(-90.0, coordinate.$1 - latDeltaDegrees).toDouble();
    final bitsLat = (_latitudeBitsForResolution(size) * 2).floor();
    final bitsLongNorth =
        (_longitudeBitsForResolution(size, latitudeNorth) * 2).floor() - 1;
    final bitsLongSouth =
        (_longitudeBitsForResolution(size, latitudeSouth) * 2).floor() - 1;
    return math.min(
      bitsLat,
      math.min(bitsLongNorth, math.min(bitsLongSouth, _maximumBitsPrecision)),
    ).toInt();
  }

  static List<(double latitude, double longitude)> _boundingBoxCoordinates(
    (double latitude, double longitude) center,
    double radius,
  ) {
    final latDegrees = radius / _metersPerDegreeLatitude;
    final latitudeNorth = math.min(90.0, center.$1 + latDegrees).toDouble();
    final latitudeSouth = math.max(-90.0, center.$1 - latDegrees).toDouble();
    final longDegsNorth = _metersToLongitudeDegrees(radius, latitudeNorth);
    final longDegsSouth = _metersToLongitudeDegrees(radius, latitudeSouth);
    final longDegs = math.max(longDegsNorth, longDegsSouth);

    return [
      center,
      (center.$1, _wrapLongitude(center.$2 - longDegs)),
      (center.$1, _wrapLongitude(center.$2 + longDegs)),
      (latitudeNorth, center.$2),
      (latitudeNorth, _wrapLongitude(center.$2 - longDegs)),
      (latitudeNorth, _wrapLongitude(center.$2 + longDegs)),
      (latitudeSouth, center.$2),
      (latitudeSouth, _wrapLongitude(center.$2 - longDegs)),
      (latitudeSouth, _wrapLongitude(center.$2 + longDegs)),
    ];
  }

  static (String start, String end) _geohashQuery(String geohash, int bits) {
    final precision = (bits / _bitsPerChar).ceil();
    if (geohash.length < precision) {
      return (geohash, '$geohash~');
    }

    geohash = geohash.substring(0, precision);
    final base = geohash.substring(0, geohash.length - 1);
    final lastValue = _base32.indexOf(geohash[geohash.length - 1]);
    final significantBits = bits - (base.length * _bitsPerChar);
    final unusedBits = _bitsPerChar - significantBits;
    final startValue = (lastValue >> unusedBits) << unusedBits;
    final endValue = startValue + (1 << unusedBits);

    if (endValue > 31) {
      return (base + _base32[startValue], '$base~');
    }
    return (base + _base32[startValue], base + _base32[endValue]);
  }
}
