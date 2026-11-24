import 'dart:io' show Platform;

import 'package:trendline/domain/health_import.dart';
import 'package:trendline/platform/android/health_connect_source.dart';

/// Whether the phone's health platform can be used.
enum HealthAvailability {
  /// Ready to ask for access.
  available,

  /// Installed but too old, or not installed (Android 13 and lower).
  needsInstall,

  /// Not on this device or platform. The UI hides the feature.
  unavailable,
}

/// A failure the user can act on, with a message to show them.
class HealthSourceException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'HealthSourceException: $message';
}

/// Reads body measurements from the phone's health platform (Health Connect
/// on Android). Read-only: Trendline never writes health data.
abstract interface class HealthSource {
  /// The platform's display name, for the UI.
  String get name;

  Future<HealthAvailability> availability();

  /// Opens the store page to install or update the platform.
  Future<void> install();

  /// Whether the user has granted read access to weight. Body fat and lean
  /// mass are optional: without them, those values are simply empty.
  Future<bool> hasAccess();

  /// Asks for read access to weight, body fat and lean mass, plus older
  /// history where the platform supports it. Returns whether weight access
  /// was granted.
  Future<bool> requestAccess();

  /// Withdraws all access the user granted.
  Future<void> disconnect();

  /// Readings from [start] to [end]. Throws [HealthSourceException].
  Future<BodyReadings> read(DateTime start, DateTime end);
}

class UnavailableHealthSource implements HealthSource {
  const new();

  @override
  String get name => 'Health Connect';

  @override
  Future<HealthAvailability> availability() async =>
      HealthAvailability.unavailable;

  @override
  Future<void> install() async {}

  @override
  Future<bool> hasAccess() async => false;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<BodyReadings> read(DateTime start, DateTime end) async =>
      const BodyReadings();
}

HealthSource createHealthSource() => Platform.isAndroid
    ? HealthConnectSource()
    : const UnavailableHealthSource();
