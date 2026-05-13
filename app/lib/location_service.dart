import 'package:geolocator/geolocator.dart';

/// What the UI needs to know after asking for location.
///
/// We keep this enum (rather than passing the raw `LocationPermission` or
/// throwing) so the home screen renders the same panel for every outcome
/// without leaking plugin types into the view layer.
enum LocationOutcome {
  /// User granted while-in-use (or always) and we got a fix.
  granted,

  /// User said no, OS will not ask again, or we don't have permission yet.
  denied,

  /// User said no and ticked "Don't ask again" / iOS denied-forever path.
  /// The UI should explain that they need to flip the switch in Settings.
  deniedForever,

  /// Device-wide location services are off; permission doesn't matter until
  /// the user turns them on.
  servicesDisabled,

  /// Something else went wrong (timeout, plugin error). Treat as recoverable.
  error,
}

/// Result of a single "ask + read" attempt.
class LocationReading {
  const LocationReading({
    required this.outcome,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.errorMessage,
  });

  final LocationOutcome outcome;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? errorMessage;

  bool get isGranted => outcome == LocationOutcome.granted;
}

/// Thin Flutter-side wrapper around `geolocator` that owns the consent +
/// single-read flow. Sprint 2 can either keep using this directly or wire
/// the same outcomes into the tested `LocationEngine` package by writing a
/// `UserLocationApi` adapter; nothing in the UI has to change for that.
class LocationService {
  const LocationService();

  Future<LocationReading> ensureConsentAndRead() async {
    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      return const LocationReading(outcome: LocationOutcome.servicesDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationReading(outcome: LocationOutcome.deniedForever);
    }

    if (permission == LocationPermission.denied) {
      return const LocationReading(outcome: LocationOutcome.denied);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationReading(
        outcome: LocationOutcome.granted,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } catch (e) {
      return LocationReading(
        outcome: LocationOutcome.error,
        errorMessage: e.toString(),
      );
    }
  }
}
