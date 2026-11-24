import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Conditions where calorie and protein targets need medical supervision.
const List<String> screenedConditions = [
  'Pregnant or breastfeeding',
  'An eating disorder, now or in the past',
  'Kidney disease',
  _diabetes,
];

const String _diabetes =
    'Diabetes treated with insulin, or with tablets that can cause low blood '
    'sugar (such as gliclazide)';

/// A one-time check before setting a goal. The answer is a single choice:
/// "none apply" (its date is saved) or "one or more apply" (nothing is
/// saved, and the app goes no further). Which condition applies is never
/// asked or stored.
class HealthScreenScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HealthScreenScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreenScreen> {
  bool _saving = false;
  bool _notSuitable = false;

  Future<void> _noneApply() async {
    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).confirmHealthScreen();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Before you start'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: _notSuitable
            ? [
                Text(
                  "Trendline isn't suitable for you right now",
                  style: text.titleLarge,
                ),
                const SizedBox(height: Space.md),
                Text(
                  'These conditions change what and how much is safe to eat, '
                  'and Trendline sets calorie and protein targets without '
                  'knowing your medical situation. Please plan any changes '
                  'to your eating with your GP, dietitian or care team.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: Space.md),
                Text(
                  'Nothing about your answer has been saved. If things '
                  'change, sign in again and you will be asked again.',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: Space.xl),
                FilledButton(
                  onPressed: _signOut,
                  child: const Text('Sign out'),
                ),
                const SizedBox(height: Space.sm),
                TextButton(
                  onPressed: () => setState(() => _notSuitable = false),
                  child: const Text('Go back'),
                ),
              ]
            : [
                Text('Do any of these apply to you?', style: text.titleLarge),
                const SizedBox(height: Space.md),
                for (final c in screenedConditions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(child: Text(c, style: text.bodyMedium)),
                      ],
                    ),
                  ),
                const SizedBox(height: Space.md),
                Text(
                  "Your answer isn't stored, only that you confirmed none "
                  'apply.',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: Space.xl),
                FilledButton(
                  onPressed: _saving ? null : _noneApply,
                  child: const Text('None of these apply'),
                ),
                const SizedBox(height: Space.sm),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _notSuitable = true),
                  child: const Text('One or more apply'),
                ),
              ],
      ),
    );
  }
}
