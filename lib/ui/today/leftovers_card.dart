import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/prep.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/prep/prep_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// On Today: cooked food to eat before it's wasted, and frozen portions to
/// move to the fridge so they thaw in time. Nothing when there's neither,
/// or while Prep can't be loaded.
class LeftoversCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(prepProvider).value;
    if (sessions == null) return const SizedBox.shrink();
    final today = dayOf(DateTime.now());
    final nudges = leftoverNudges(
      sessions,
      ref.watch(currentUserIdProvider),
      today,
    );
    if (nudges.isEmpty) return const SizedBox.shrink();
    final names = {
      for (final r in [
        ...?ref.watch(recipesProvider).value,
        ...?ref.watch(sharedRecipesProvider).value,
      ])
        r.id: r.name,
    };
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    String when(DateTime day) => day == today ? 'today' : 'tomorrow';
    String thawAdvice(DateTime day) =>
        day == today ? 'thaw it now' : 'move it to the fridge tonight';

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.sm,
            Space.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Leftovers', style: text.titleMedium),
              for (final (:session, :portion, :nudge) in nudges)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    names[session.recipeId] ?? 'A cooked batch',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    switch (nudge) {
                      LeftoverNudge.useSoon =>
                        '${portionsLabel(portion.amount)} in the fridge · '
                            'use by ${when(portion.useBy)}',
                      LeftoverNudge.thaw =>
                        'Frozen · '
                            '${mealSlotLabel(portion.slot!).toLowerCase()} '
                            '${when(portion.day!)} · '
                            '${thawAdvice(portion.day!)}',
                    },
                    style: text.bodySmall?.copyWith(
                      color: nudge == LeftoverNudge.thaw
                          ? colors.warning
                          : colors.textSecondary,
                    ),
                  ),
                  trailing: switch (nudge) {
                    LeftoverNudge.thaw => TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(prepProvider.notifier).thaw(portion);
                        } on Object catch (e) {
                          if (context.mounted) showErrorSnack(context, e);
                        }
                      },
                      child: const Text('In the fridge'),
                    ),
                    LeftoverNudge.useSoon => const Icon(Icons.chevron_right),
                  },
                  // Eating, freezing or throwing it away happen in Prep.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PrepScreen()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
