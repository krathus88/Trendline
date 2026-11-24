import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/app_info.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/profile/profile_form_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        children: [
          if (profile != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              subtitle: Text(_summary(profile)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfileFormScreen(existing: profile),
                ),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
              } on Object catch (e) {
                if (context.mounted) showErrorSnack(context, e);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Text(
              'Trendline gives estimates, not medical advice. Talk to your '
              'GP if you have a health condition.\n\n'
              'Contains information from Open Food Facts '
              '(openfoodfacts.org), made available under the Open '
              'Database License (ODbL).\n\nVersion $appVersion',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  static String _summary(Profile p) {
    final unit = switch (p.weightUnit) {
      WeightUnit.kg => 'kg',
      WeightUnit.lb => 'lb',
      WeightUnit.stLb => 'st & lb',
    };
    return '${p.heightCm.toStringAsFixed(0)} cm · born ${p.birthYear} · $unit';
  }
}
