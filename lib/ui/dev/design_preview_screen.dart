import 'package:material_ui/material_ui.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// A static mock of the Today screen, used to judge the design system on a
/// real device. All values are made up. Replaced by real screens in M1.
class DesignPreviewScreen extends StatelessWidget {
  const new({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          if (onSignOut != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          Text('Tuesday 24 November', style: text.bodySmall),
          const SizedBox(height: Space.lg),
          const _CalorieSummary(eaten: 1240, target: 2050),
          const SizedBox(height: Space.lg),
          _MacroBar(
            label: 'Protein',
            grams: 96,
            target: 150,
            color: colors.protein,
          ),
          _MacroBar(
            label: 'Carbs',
            grams: 118,
            target: 210,
            color: colors.carbs,
          ),
          _MacroBar(label: 'Fat', grams: 41, target: 65, color: colors.fat),
          _MacroBar(label: 'Fibre', grams: 17, target: 30, color: colors.fibre),
          const SizedBox(height: Space.xl),
          Text('Plan', style: text.titleMedium),
          const SizedBox(height: Space.sm),
          const _SlotCard(
            time: '07:30',
            slot: 'Breakfast',
            items: [
              ('Cappuccino, sugar free', '1 sachet + 200 ml milk'),
              ('Greek yoghurt 0%', '170 g'),
            ],
            done: true,
          ),
          const SizedBox(height: Space.sm),
          const _SlotCard(
            time: '12:30',
            slot: 'Lunch',
            items: [('Chicken & rice (prep, Sun)', '380 g cooked')],
            done: true,
          ),
          const SizedBox(height: Space.sm),
          const _SlotCard(
            time: '16:00',
            slot: 'Snack',
            items: [('Apple', '1 medium')],
          ),
          const SizedBox(height: Space.sm),
          const _SlotCard(
            time: '19:00',
            slot: 'Dinner',
            items: [
              ('Salmon fillet', '120 g'),
              ('New potatoes', '200 g'),
              ('Green beans', '100 g'),
            ],
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () {},
            child: const Text('Re-plan rest of day'),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton(
            onPressed: () {},
            child: const Text('Mark day complete'),
          ),
          const SizedBox(height: Space.xl),
          const TextField(
            decoration: InputDecoration(hintText: 'Search foods'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            label: 'Prep',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Progress',
          ),
        ],
      ),
    );
  }
}

class _CalorieSummary extends StatelessWidget {
  const new({required this.eaten, required this.target});

  final int eaten;
  final int target;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final remaining = target - eaten;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remaining', style: text.bodySmall),
            const SizedBox(height: Space.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$remaining', style: text.displayMedium?.tabular),
                const SizedBox(width: Space.sm),
                Text('kcal', style: text.bodySmall),
              ],
            ),
            const SizedBox(height: Space.md),
            ClipRRect(
              borderRadius: Radii.smAll,
              child: LinearProgressIndicator(
                value: eaten / target,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(
              '$eaten eaten · $target target',
              style: text.bodySmall?.tabular.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const new({
    required this.label,
    required this.grams,
    required this.target,
    required this.color,
  });

  final String label;
  final int grams;
  final int target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: text.labelMedium)),
          Expanded(
            child: ClipRRect(
              borderRadius: Radii.smAll,
              child: LinearProgressIndicator(
                value: (grams / target).clamp(0, 1),
                minHeight: 4,
                color: color,
                backgroundColor: colors.surfaceMuted,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '$grams / $target g',
              textAlign: TextAlign.end,
              style: text.labelMedium?.tabular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const new({
    required this.time,
    required this.slot,
    required this.items,
    this.done = false,
  });

  final String time;
  final String slot;
  final List<(String, String)> items;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  time,
                  style: text.labelMedium?.tabular.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(slot, style: text.titleSmall)),
                AnimatedSwitcher(
                  duration: Motion.fast,
                  child: Icon(
                    done ? Icons.check_circle : Icons.radio_button_unchecked,
                    key: ValueKey(done),
                    size: 20,
                    color: done ? colors.accent : colors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            for (final (name, amount) in items)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  children: [
                    Expanded(child: Text(name, style: text.bodyMedium)),
                    Text(amount, style: text.bodySmall?.tabular),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
