import '../models/trip_poi.dart';

/// Outcome of a nearby POI lookup, including debug stats for the UI.
class PoiQueryResult {
  const PoiQueryResult({
    this.poi,
    this.nearbyCount = 0,
    this.taggedCount = 0,
    this.usedTagFallback = false,
    this.usedNearestFallback = false,
    this.errorMessage,
  });

  final TripPoi? poi;
  final int nearbyCount;
  final int taggedCount;
  final bool usedTagFallback;
  final bool usedNearestFallback;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}
