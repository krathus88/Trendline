import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/meal_rules/meal_rules_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Create or edit a meal rule for one food or recipe.
class MealRuleEditorScreen extends ConsumerStatefulWidget {
  const new({required this.target, super.key, this.existing});

  final RuleTarget target;
  final MealRule? existing;

  @override
  ConsumerState<MealRuleEditorScreen> createState() =>
      _MealRuleEditorScreenState();
}

class _MealRuleEditorScreenState extends ConsumerState<MealRuleEditorScreen> {
  late MealSlot? _slot = widget.existing?.slot;
  late RuleFrequency _frequency =
      widget.existing?.frequency ?? RuleFrequency.daily;
  late final _times = TextEditingController(
    text: '${widget.existing?.timesPerWeek ?? 2}',
  );
  late final _min = TextEditingController(
    text: _plain(widget.existing?.amountMin ?? (_isRecipe ? 1 : 100)),
  );
  late final _max = TextEditingController(
    text:
        widget.existing == null ||
            widget.existing!.amountMax == widget.existing!.amountMin
        ? ''
        : _plain(widget.existing!.amountMax),
  );
  String? _error;
  bool _saving = false;

  bool get _isRecipe => widget.target.recipeId != null;

  @override
  void dispose() {
    for (final c in [_times, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  MealRule? get _draft {
    final min = parseDecimal(_min.text);
    final maxText = _max.text.trim();
    final max = maxText.isEmpty ? min : parseDecimal(maxText);
    final times = int.tryParse(_times.text.trim());
    if (min == null || max == null) return null;
    final weekly = _frequency != RuleFrequency.daily;
    if (weekly && times == null) return null;
    return MealRule(
      id: widget.existing?.id ?? '',
      foodId: widget.target.foodId,
      recipeId: widget.target.recipeId,
      slot: _slot,
      frequency: _frequency,
      timesPerWeek: weekly ? times : null,
      amountMin: min,
      amountMax: max,
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    final problem = draft == null ? 'Check the numbers.' : validateRule(draft);
    setState(() => _error = problem);
    if (problem != null) return;
    setState(() => _saving = true);
    try {
      await ref.read(mealRulesProvider.notifier).save(draft!);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final navigator = Navigator.of(context);
    try {
      await ref.read(mealRulesProvider.notifier).delete(id);
      navigator.pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final unit = _isRecipe ? 'portions' : 'g';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New rule' : 'Edit rule'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete rule',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
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
          Text(widget.target.name, style: text.titleLarge),
          const SizedBox(height: Space.lg),
          Text('How often', style: text.labelMedium),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final (f, label) in const [
                (RuleFrequency.daily, 'Every day'),
                (RuleFrequency.minPerWeek, 'At least'),
                (RuleFrequency.maxPerWeek, 'At most'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _frequency == f,
                  onSelected: (_) => setState(() => _frequency = f),
                ),
            ],
          ),
          if (_frequency != RuleFrequency.daily) ...[
            const SizedBox(height: Space.sm),
            TextField(
              controller: _times,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Times',
                suffixText: 'a week',
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          Text('Meal', style: text.labelMedium),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.sm,
            children: [
              ChoiceChip(
                label: const Text('Any'),
                selected: _slot == null,
                onSelected: (_) => setState(() => _slot = null),
              ),
              for (final s in MealSlot.values)
                ChoiceChip(
                  label: Text(mealSlotLabel(s)),
                  selected: _slot == s,
                  onSelected: (_) => setState(() => _slot = s),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text('Amount each time', style: text.labelMedium),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    suffixText: unit,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Up to (optional)',
                    suffixText: unit,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Leave “Up to” empty for a fixed amount. With a range, the '
            'planner picks the amount that fits the day.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save rule'),
          ),
        ],
      ),
    );
  }
}

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
