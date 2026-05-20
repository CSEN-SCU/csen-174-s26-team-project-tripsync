import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../geo/geofire_common.dart';
import '../models/trip_poi.dart';
import 'poi_query_result.dart';

/// Reads nearby POIs from Firestore using geohash bounds (geofire-common compatible).
class PoiRepository {
  PoiRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// ~1.5 miles — enough to cover dense SF neighborhoods from SoMa.
  static const double defaultRadiusMeters = 2414.0;

  /// Finds the best matching POI for [latitude]/[longitude] and [interestTags].
  Future<PoiQueryResult> findBestNearby({
    required double latitude,
    required double longitude,
    required List<String> interestTags,
    double radiusMeters = defaultRadiusMeters,
  }) async {
    final normalizedTags =
        interestTags.map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toSet();
    if (normalizedTags.isEmpty) {
      return const PoiQueryResult(
        errorMessage: 'No interest tags configured.',
      );
    }

    final center = (latitude, longitude);

    try {
      var uniquePois = await _queryByGeohash(center, radiusMeters);
      var usedTagFallback = false;

      if (uniquePois.isEmpty) {
        uniquePois = await _queryByTags(normalizedTags.toList());
        usedTagFallback = true;
      }

      if (uniquePois.isEmpty) {
        return PoiQueryResult(
          nearbyCount: 0,
          taggedCount: 0,
          usedTagFallback: usedTagFallback,
          errorMessage: _auth.currentUser == null
              ? 'Sign in (or continue as guest after updating the app) to load places from Firestore.'
              : 'Firestore returned no POI documents. Confirm the pois collection is seeded.',
        );
      }

      final withinRadius = uniquePois.values
          .map((poi) => _withDistanceAndScore(poi, center, normalizedTags))
          .where(
            (poi) => (poi.distanceMeters ?? double.infinity) <= radiusMeters,
          )
          .toList();

      final tagged = withinRadius.where((poi) => poi.preferenceScore > 0).toList()
        ..sort(_comparePois);

      if (tagged.isNotEmpty) {
        return PoiQueryResult(
          poi: tagged.first,
          nearbyCount: withinRadius.length,
          taggedCount: tagged.length,
          usedTagFallback: usedTagFallback,
        );
      }

      if (withinRadius.isEmpty) {
        return PoiQueryResult(
          nearbyCount: 0,
          taggedCount: 0,
          usedTagFallback: usedTagFallback,
          errorMessage:
              'No places within ${(radiusMeters / 1609.344).toStringAsFixed(1)} mi. Try again when you are closer to seeded POIs.',
        );
      }

      withinRadius.sort(
        (a, b) => (a.distanceMeters ?? double.infinity)
            .compareTo(b.distanceMeters ?? double.infinity),
      );

      return PoiQueryResult(
        poi: withinRadius.first,
        nearbyCount: withinRadius.length,
        taggedCount: 0,
        usedTagFallback: usedTagFallback,
        usedNearestFallback: true,
      );
    } on FirebaseException catch (e) {
      return PoiQueryResult(
        errorMessage: e.code == 'permission-denied'
            ? 'Firestore denied POI access. Deploy updated firestore.rules or sign in.'
            : 'Firestore error (${e.code}): ${e.message ?? e.toString()}',
      );
    } catch (e) {
      return PoiQueryResult(errorMessage: e.toString());
    }
  }

  Future<Map<String, TripPoi>> _queryByGeohash(
    (double, double) center,
    double radiusMeters,
  ) async {
    final bounds = GeofireCommon.geohashQueryBounds(center, radiusMeters);
    final seenBounds = <String>{};
    final uniquePois = <String, TripPoi>{};

    for (final (start, end) in bounds) {
      final boundKey = '$start|$end';
      if (!seenBounds.add(boundKey)) continue;

      final snapshot = await _db
          .collection('pois')
          .orderBy('geo.geohash')
          .startAt([start])
          .endAt([end])
          .get();

      for (final doc in snapshot.docs) {
        final poi = _parseDoc(doc);
        if (poi != null) {
          uniquePois[doc.id] = poi;
        }
      }
    }

    return uniquePois;
  }

  /// Fallback for small catalogs when geohash queries return nothing.
  Future<Map<String, TripPoi>> _queryByTags(List<String> tags) async {
    final uniquePois = <String, TripPoi>{};
    final snapshot = await _db
        .collection('pois')
        .where('tags', arrayContainsAny: tags)
        .get();

    for (final doc in snapshot.docs) {
      final poi = _parseDoc(doc);
      if (poi != null) {
        uniquePois[doc.id] = poi;
      }
    }

    return uniquePois;
  }

  TripPoi _withDistanceAndScore(
    TripPoi poi,
    (double, double) center,
    Set<String> normalizedTags,
  ) {
    final distanceMeters = GeofireCommon.distanceMeters(
      center,
      (poi.latitude, poi.longitude),
    );
    final preferenceScore = poi.tags
        .where((tag) => normalizedTags.contains(tag.toLowerCase()))
        .length;

    return TripPoi(
      id: poi.id,
      name: poi.name,
      description: poi.description,
      city: poi.city,
      category: poi.category,
      tags: poi.tags,
      latitude: poi.latitude,
      longitude: poi.longitude,
      distanceMeters: distanceMeters,
      preferenceScore: preferenceScore,
    );
  }

  int _comparePois(TripPoi a, TripPoi b) {
    final scoreCompare = b.preferenceScore.compareTo(a.preferenceScore);
    if (scoreCompare != 0) return scoreCompare;
    return (a.distanceMeters ?? double.infinity)
        .compareTo(b.distanceMeters ?? double.infinity);
  }

  TripPoi? _parseDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final geo = data['geo'];
    if (geo is! Map) return null;

    final geopoint = geo['geopoint'];
    double? latitude;
    double? longitude;

    if (geopoint is GeoPoint) {
      latitude = geopoint.latitude;
      longitude = geopoint.longitude;
    } else if (geopoint is Map) {
      final lat = geopoint['latitude'] ?? geopoint['_latitude'];
      final lng = geopoint['longitude'] ?? geopoint['_longitude'];
      if (lat is num && lng is num) {
        latitude = lat.toDouble();
        longitude = lng.toDouble();
      }
    }

    if (latitude == null || longitude == null) return null;

    final rawTags = data['tags'];
    final tags = rawTags is List
        ? rawTags.whereType<String>().toList()
        : <String>[];

    return TripPoi(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? doc.id,
      description: (data['description'] as String?)?.trim() ?? '',
      city: (data['city'] as String?)?.trim() ?? '',
      category: (data['category'] as String?)?.trim() ?? '',
      tags: tags,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
