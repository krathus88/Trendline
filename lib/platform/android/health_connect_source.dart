import 'package:health/health.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/platform/health_source.dart';

/// Health Connect on Android. This is the only file that may import
/// `health`, so other platforms build without it being used.
///
/// Requests read access only, to the types the app uses. The matching
/// permissions are declared in AndroidManifest.xml; keep the two in step.
class HealthConnectSource implements HealthSource {
  new() : _health = Health();

  final Health _health;
  bool _configured = false;

  static const List<HealthDataType> _types = [
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.LEAN_BODY_MASS,
  ];

  @override
  String get name => 'Health Connect';

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<HealthAvailability> availability() async {
    await _configure();
    return switch (await _health.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        HealthAvailability.needsInstall,
      _ => HealthAvailability.unavailable,
    };
  }

  @override
  Future<void> install() => _health.installHealthConnect();

  @override
  Future<bool> hasAccess() async {
    await _configure();
    try {
      return await _health.hasPermissions(const [HealthDataType.WEIGHT]) ??
          false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> requestAccess() async {
    await _configure();
    final granted = await _health.requestAuthorization(
      _types,
      permissions: List.filled(_types.length, HealthDataAccess.READ),
    );
    // Without this, Health Connect only shares the 30 days before access
    // was first granted. Optional: the sync works either way.
    if (granted &&
        await _health.isHealthDataHistoryAvailable() &&
        !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }
    return await hasAccess();
  }

  @override
  Future<void> disconnect() => _health.revokePermissions();

  @override
  Future<BodyReadings> read(DateTime start, DateTime end) async {
    await _configure();
    final List<HealthDataPoint> points;
    try {
      points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: start,
        endTime: end,
      );
    } on HealthPlatformException catch (e) {
      throw HealthSourceException(
        e.isRetryable
            ? 'Health Connect is busy. Try again in a few minutes.'
            : "Couldn't read from Health Connect.",
      );
    } on HealthException {
      throw const HealthSourceException(
        "This phone's Health Connect can't share body measurements.",
      );
      // The plugin throws an Error, not an Exception, when Health Connect is
      // missing; it can be uninstalled while the app runs.
      // ignore: avoid_catching_errors
    } on UnsupportedError {
      throw const HealthSourceException('Health Connect is not available.');
    }

    List<HealthReading> of(HealthDataType type) => [
      for (final p in points)
        if (p.type == type && p.value is NumericHealthValue)
          HealthReading(
            id: p.uuid,
            at: p.dateFrom,
            value: (p.value as NumericHealthValue).numericValue.toDouble(),
          ),
    ];

    return BodyReadings(
      weightKg: of(HealthDataType.WEIGHT),
      bodyFatPct: of(HealthDataType.BODY_FAT_PERCENTAGE),
      leanMassKg: of(HealthDataType.LEAN_BODY_MASS),
    );
  }
}
