import 'dart:async';
import 'package:geolocator/geolocator.dart';

enum LocationFailure { serviceOff, denied, deniedForever, timeout, unavailable }

class DeviceLocation {
  final double? lat, lng;
  final LocationFailure? failure;
  const DeviceLocation.ok(this.lat, this.lng) : failure = null;
  const DeviceLocation.fail(this.failure) : lat = null, lng = null;
  bool get isOk => failure == null;

  /// Plain-language reason, shown to the user. Always paired with a manual alternative in the UI.
  String get message => switch (failure) {
        LocationFailure.serviceOff => 'Location is switched off on this device.',
        LocationFailure.denied => 'Location permission was not granted.',
        LocationFailure.deniedForever =>
          'Location permission is blocked. You can enable it in your browser or device settings.',
        LocationFailure.timeout => 'Could not get your location in time.',
        _ => 'Your location is not available right now.',
      };
}

/// One-shot, permission-based device location. Never guesses: any failure is reported as a failure.
/// Call only after the user taps something that explains why the location is needed.
Future<DeviceLocation> getDeviceLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const DeviceLocation.fail(LocationFailure.serviceOff);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      return const DeviceLocation.fail(LocationFailure.deniedForever);
    }
    if (perm == LocationPermission.denied) return const DeviceLocation.fail(LocationFailure.denied);
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    ).timeout(const Duration(seconds: 15));
    return DeviceLocation.ok(p.latitude, p.longitude);
  } on TimeoutException {
    return const DeviceLocation.fail(LocationFailure.timeout);
  } catch (_) {
    return const DeviceLocation.fail(LocationFailure.unavailable);
  }
}
