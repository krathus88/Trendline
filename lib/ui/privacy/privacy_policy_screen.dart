import 'package:flutter/services.dart' show SystemNavigator;
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/privacy_policy.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// The full privacy policy.
///
/// Also opened on its own by Health Connect's permission screen, without
/// signing in ([standalone]): then the close button leaves the app.
class PrivacyPolicyScreen extends StatelessWidget {
  const new({super.key, this.standalone = false});

  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy policy'),
        leading: standalone
            ? const IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close),
                onPressed: SystemNavigator.pop,
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          Text(
            'Version $privacyPolicyVersion, $privacyPolicyDate',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          Text('In short', style: text.titleMedium),
          const SizedBox(height: Space.sm),
          const PolicyBulletList(items: privacySummary),
          for (final section in privacyPolicy) ...[
            const SizedBox(height: Space.xl),
            Text(section.heading, style: text.titleMedium),
            for (final block in section.blocks) ...[
              const SizedBox(height: Space.sm),
              switch (block) {
                Paragraph(text: final body) => Text(
                  body,
                  style: text.bodyMedium,
                ),
                Bullets(:final items) => PolicyBulletList(items: items),
              },
            ],
          ],
        ],
      ),
    );
  }
}

/// Bulleted lines of policy text.
class PolicyBulletList extends StatelessWidget {
  const new({required this.items, super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(child: Text(item, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
