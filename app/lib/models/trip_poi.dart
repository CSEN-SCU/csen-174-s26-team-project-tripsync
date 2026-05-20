/// A point of interest loaded from Firestore `pois/{id}`.
class TripPoi {
  const TripPoi({
    required this.id,
    required this.name,
    required this.description,
    required this.city,
    required this.category,
    required this.tags,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.preferenceScore = 0,
  });

  final String id;
  final String name;
  final String description;
  final String city;
  final String category;
  final List<String> tags;
  final double latitude;
  final double longitude;
  final double? distanceMeters;
  final int preferenceScore;

  /// Short spoken / on-screen blurb for the home voice loop.
  String get recommendationBlurb {
    final trimmedDescription = description.trim();
    if (trimmedDescription.isEmpty) {
      final citySuffix = city.trim().isEmpty ? '' : ' in ${city.trim()}';
      return '$name — a ${category.trim().isEmpty ? 'nearby' : category} spot$citySuffix. Worth a look if you are in the area.';
    }
    return '$name — $trimmedDescription';
  }
}
