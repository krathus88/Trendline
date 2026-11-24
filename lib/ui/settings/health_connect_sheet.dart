import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/health/health_sync_notifier.dart';
import 'package:trendline/platform/health_source.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// One line describing the Health Connect connection, for the Settings tile.
String healthConnectSummary(HealthSyncState s) {
  if (s.availability == HealthAvailability.needsInstall) {
    return 'Install or update Health Connect to use it';
  }
  if (!s.connected) return 'Import weigh-ins from your scale';
  if (s.syncing) return 'Syncing…';
  if (s.error case final e?) return userMessage(e);
  if (s.lastSyncedAt case final at?) return 'Synced ${formatDateTime(at)}';
  return 'Connected';
}

/// Connects, syncs and disconnects Health Connect.
class HealthConnectSheet extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final s = ref.watch(healthSyncProvider).value ?? HealthSyncState.off;
    final notifier = ref.read(healthSyncProvider.notifier);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    final body = switch (s) {
      HealthSyncState(availability: HealthAvailability.needsInstall) =>
        'Health Connect needs installing or updating before Trendline can '
            'read from it.',
      HealthSyncState(connected: false) =>
        'Trendline can import your weight, body fat and lean mass from '
            'Health Connect, where most smart scales save their readings. '
            'It only reads: it never adds or changes anything there.\n\n'
            'Imported readings are stored in your Trendline account like '
            'the ones you type in.',
      _ =>
        'New readings are imported when you open Trendline. Readings you '
            "delete here won't be imported again.",
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Health Connect', style: text.titleLarge),
        const SizedBox(height: Space.sm),
        Text(body, style: text.bodyMedium),
        if (s.connected) ...[
          const SizedBox(height: Space.md),
          Text(
            healthConnectSummary(s),
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
        const SizedBox(height: Space.xl),
        ...switch (s) {
          HealthSyncState(availability: HealthAvailability.needsInstall) => [
            FilledButton(
              onPressed: () => run(notifier.install),
              child: const Text('Get Health Connect'),
            ),
          ],
          HealthSyncState(connected: false) => [
            FilledButton(
              onPressed: () => run(() async {
                final granted = await notifier.connect();
                if (!granted && context.mounted) {
                  showMessageSnack(
                    context,
                    'Trendline needs access to weight to import readings.',
                  );
                }
              }),
              child: const Text('Connect'),
            ),
          ],
          _ => [
            FilledButton(
              onPressed: s.syncing ? null : () => run(notifier.sync),
              child: const Text('Sync now'),
            ),
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => run(notifier.disconnect),
              child: const Text('Disconnect'),
            ),
            Text(
              'Disconnecting keeps the readings already imported.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        },
      ],
    );
  }
}
