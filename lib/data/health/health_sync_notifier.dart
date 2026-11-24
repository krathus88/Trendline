import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/platform/health_source.dart';

@immutable
class HealthSyncState {
  const new({
    required this.availability,
    required this.connected,
    this.syncing = false,
    this.lastSyncedAt,
    this.lastAdded,
    this.error,
  });

  static const off = HealthSyncState(
    availability: HealthAvailability.unavailable,
    connected: false,
  );

  final HealthAvailability availability;
  final bool connected;
  final bool syncing;
  final DateTime? lastSyncedAt;

  /// How many weigh-ins the last sync added.
  final int? lastAdded;

  /// Why the last sync failed, if it did.
  final Object? error;

  HealthSyncState _with({
    HealthAvailability? availability,
    bool? connected,
    bool? syncing,
    DateTime? lastSyncedAt,
    int? lastAdded,
    Object? error,
  }) => HealthSyncState(
    availability: availability ?? this.availability,
    connected: connected ?? this.connected,
    syncing: syncing ?? this.syncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastAdded: lastAdded ?? this.lastAdded,
    error: error,
  );
}

/// Imports weigh-ins from Health Connect: once when the app starts, again
/// when it comes back to the foreground, and on request.
final healthSyncProvider =
    AsyncNotifierProvider<HealthSyncNotifier, HealthSyncState>(
      HealthSyncNotifier.new,
    );

class HealthSyncNotifier extends AsyncNotifier<HealthSyncState> {
  /// Coming back to the app within this long doesn't sync again.
  static const resumeInterval = Duration(minutes: 2);

  HealthSource get _source => ref.read(healthSourceProvider);

  @override
  Future<HealthSyncState> build() async {
    if (ref.watch(currentUserIdProvider) == null) return HealthSyncState.off;
    final status = await _status(HealthSyncState.off);
    if (status.connected) Future(syncQuietly).ignore();
    return status;
  }

  Future<HealthSyncState> _status(HealthSyncState from) async {
    final availability = await _source.availability();
    final connected =
        availability == HealthAvailability.available &&
        await _source.hasAccess();
    return from._with(availability: availability, connected: connected);
  }

  /// Checks again whether the platform is usable and access still granted
  /// (either can change outside the app), then syncs if it's been a while.
  Future<void> recheck() async {
    final current = await future;
    if (ref.read(currentUserIdProvider) == null) return;
    final status = await _status(current);
    state = AsyncData(status);
    final last = status.lastSyncedAt;
    if (status.connected &&
        (last == null || DateTime.now().difference(last) >= resumeInterval)) {
      await syncQuietly();
    }
  }

  /// Asks for access and, if granted, imports straight away.
  Future<bool> connect() async {
    await future;
    final granted = await _source.requestAccess();
    state = AsyncData((await future)._with(connected: granted));
    if (granted) await sync();
    return granted;
  }

  /// Withdraws access. Readings already imported stay.
  Future<void> disconnect() async {
    await _source.disconnect();
    state = AsyncData((await future)._with(connected: false));
  }

  Future<void> install() => _source.install();

  /// Like [sync], but failures only show in the state.
  Future<void> syncQuietly() async {
    try {
      await sync();
    } on Object {
      // Kept in state.error for the UI.
    }
  }

  HealthSyncState _latest(HealthSyncState fallback) => state.value ?? fallback;

  /// Imports new readings. Returns how many weigh-ins were added.
  Future<int> sync() async {
    final current = await future;
    if (!current.connected || current.syncing) return 0;
    state = AsyncData(current._with(syncing: true));
    try {
      final existing = await ref.read(weighInsProvider.future);
      final now = DateTime.now();
      final start = healthSyncStart(
        existing,
        now: now,
        historyDays: WeighInsNotifier.historyDays,
      );
      final readings = await _source.read(start, now);
      final toImport = planHealthImport(readings, existing: existing, now: now);
      final added = toImport.isEmpty
          ? 0
          : await ref
                .read(weighInRepositoryProvider)
                .importHealthConnect(toImport);
      if (added > 0) await ref.read(weighInsProvider.notifier).reload();
      state = AsyncData(
        _latest(current)
            ._with(syncing: false, lastSyncedAt: now, lastAdded: added),
      );
      return added;
    } on Object catch (e) {
      state = AsyncData(_latest(current)._with(syncing: false, error: e));
      rethrow;
    }
  }
}
