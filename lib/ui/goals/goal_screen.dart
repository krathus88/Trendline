import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/domain/weigh_in.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// Sets the goal: any two of target weight, pace and date, or maintenance.
/// Shows what will actually be planned, including any cap or floor.
class GoalScreen extends ConsumerStatefulWidget {
  const new({super.key, this.existing, this.onboarding = false});

  final Goal? existing;

  /// First run: no back button, and saving continues into the app.
  final bool onboarding;

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

/// Pace entry: the user's weight unit per week, or percent per week.
enum _PaceUnit { weight, percent }

class _GoalScreenState extends ConsumerState<GoalScreen> {
  late GoalKind _kind;
  late _PaceUnit _paceUnit;
  final _target = TextEditingController(); // kg, lb or stones
  final _targetLb = TextEditingController(); // pounds, for st & lb only
  final _pace = TextEditingController();
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _kind = g?.kind ?? GoalKind.targetAndPace;
    _paceUnit = g?.paceMode == PaceMode.percentPerWeek
        ? _PaceUnit.percent
        : _PaceUnit.weight;
    _date = g?.goalDate;
    // Filled in once the profile's unit is known (first build).
  }

  bool _filled = false;

  void _fill(WeightUnit unit) {
    if (_filled) return;
    _filled = true;
    final g = widget.existing;
    if (g?.targetWeightKg case final kg?) {
      switch (unit) {
        case WeightUnit.kg:
          _target.text = kg.toStringAsFixed(1);
        case WeightUnit.lb:
          _target.text = kgToLb(kg).toStringAsFixed(1);
        case WeightUnit.stLb:
          final (:stones, :pounds) = kgToStLb(kg);
          _target.text = '$stones';
          _targetLb.text = pounds.toStringAsFixed(1);
      }
    }
    if (g?.paceValue case final v?) {
      _pace.text =
          g!.paceMode == PaceMode.percentPerWeek || unit == WeightUnit.kg
          ? _trim(v)
          : _trim(kgToLb(v));
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _targetLb.dispose();
    _pace.dispose();
    super.dispose();
  }

  bool get _usesTarget =>
      _kind == GoalKind.targetAndPace || _kind == GoalKind.targetAndDate;
  bool get _usesPace =>
      _kind == GoalKind.targetAndPace || _kind == GoalKind.paceAndDate;
  bool get _usesDate =>
      _kind == GoalKind.targetAndDate || _kind == GoalKind.paceAndDate;

  double? _targetKg(WeightUnit unit) {
    switch (unit) {
      case WeightUnit.kg:
        return parseDecimal(_target.text);
      case WeightUnit.lb:
        final lb = parseDecimal(_target.text);
        return lb == null ? null : lbToKg(lb);
      case WeightUnit.stLb:
        final st = int.tryParse(_target.text.trim());
        final lb = _targetLb.text.trim().isEmpty
            ? 0.0
            : parseDecimal(_targetLb.text);
        if (st == null || lb == null || lb < 0 || lb >= lbPerStone) {
          return null;
        }
        return stLbToKg(st, lb);
    }
  }

  /// The stored pace value: kg per week, or percent per week.
  double? _paceValue(WeightUnit unit) {
    final v = parseDecimal(_pace.text);
    if (v == null || v < 0) return null;
    if (_paceUnit == _PaceUnit.percent) return v > maxPacePercent ? null : v;
    final kg = unit == WeightUnit.kg ? v : lbToKg(v);
    return kg > 4 ? null : kg;
  }

  /// The goal as entered, or null with the reason it can't be saved.
  (Goal?, String?) _goal(WeightUnit unit) {
    final target = _usesTarget ? _targetKg(unit) : null;
    final pace = _usesPace ? _paceValue(unit) : null;
    if (_usesTarget && (target == null || !WeighIn.isValidWeight(target))) {
      return (null, 'Enter a target weight.');
    }
    if (_usesPace && pace == null) {
      return (
        null,
        _paceUnit == _PaceUnit.percent
            ? 'Enter a pace up to 1% a week.'
            : 'Enter a weekly pace.',
      );
    }
    if (_usesDate && _date == null) return (null, 'Pick a goal date.');
    return (
      Goal(
        kind: _kind,
        targetWeightKg: target,
        paceMode: _paceUnit == _PaceUnit.percent
            ? PaceMode.percentPerWeek
            : PaceMode.kgPerWeek,
        paceValue: pace,
        goalDate: _usesDate ? _date : null,
      ),
      null,
    );
  }

  Future<void> _pickDate() async {
    final today = dayOf(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? addDays(today, 84),
      firstDate: addDays(today, 7),
      lastDate: addDays(today, 365 * 5),
    );
    if (picked != null) setState(() => _date = dayOf(picked));
  }

  Future<void> _save(Goal goal) async {
    setState(() => _saving = true);
    try {
      await ref.read(goalProvider.notifier).save(goal);
      if (mounted && !widget.onboarding) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider).value;
    final unit = profile?.weightUnit ?? WeightUnit.kg;
    _fill(unit);
    final (goal, problem) = _goal(unit);
    final weightUnitLabel = unit == WeightUnit.kg ? 'kg' : 'lb';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your goal'),
        automaticallyImplyLeading: !widget.onboarding,
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
            'Set any two of target weight, pace and date. Trendline works '
            'out the third, and your daily calories.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          RadioGroup<GoalKind>(
            groupValue: _kind,
            onChanged: (v) => setState(() => _kind = v ?? _kind),
            child: Column(
              children: [
                for (final kind in GoalKind.values)
                  RadioListTile<GoalKind>(
                    value: kind,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_kindTitle(kind)),
                    subtitle: Text(_kindDetail(kind), style: text.bodySmall),
                  ),
              ],
            ),
          ),
          if (_usesTarget) ...[
            const SizedBox(height: Space.lg),
            if (unit == WeightUnit.stLb)
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _target,
                      label: 'Target',
                      suffix: 'st',
                      decimal: false,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: _NumberField(
                      controller: _targetLb,
                      label: '',
                      suffix: 'lb',
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              )
            else
              _NumberField(
                controller: _target,
                label: 'Target weight',
                suffix: weightUnitLabel,
                onChanged: () => setState(() {}),
              ),
          ],
          if (_usesPace) ...[
            const SizedBox(height: Space.lg),
            SegmentedButton<_PaceUnit>(
              segments: [
                ButtonSegment(
                  value: _PaceUnit.weight,
                  label: Text('$weightUnitLabel a week'),
                ),
                const ButtonSegment(
                  value: _PaceUnit.percent,
                  label: Text('% a week'),
                ),
              ],
              selected: {_paceUnit},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _paceUnit = s.first;
                _pace.clear();
              }),
            ),
            const SizedBox(height: Space.md),
            _NumberField(
              controller: _pace,
              label: 'Pace',
              suffix: _paceUnit == _PaceUnit.percent
                  ? '% of body weight a week'
                  : '$weightUnitLabel a week',
              helper: _paceUnit == _PaceUnit.percent
                  ? 'Up to 1%. A percentage slows down as you lose weight.'
                  : 'Plans above 1% of your weight a week are capped.',
              onChanged: () => setState(() {}),
            ),
          ],
          if (_usesDate) ...[
            const SizedBox(height: Space.lg),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _date == null ? 'Pick a goal date' : formatLongDate(_date!),
              ),
            ),
          ],
          const SizedBox(height: Space.xl),
          if (goal != null && profile != null)
            _Preview(goal: goal, profile: profile)
          else if (problem != null)
            Text(
              problem,
              style: text.bodySmall?.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: goal == null || _saving ? null : () => _save(goal),
            child: Text(widget.onboarding ? 'Continue' : 'Save goal'),
          ),
        ],
      ),
    );
  }

  static String _kindTitle(GoalKind k) => switch (k) {
    GoalKind.targetAndPace => 'Target weight and pace',
    GoalKind.targetAndDate => 'Target weight and date',
    GoalKind.paceAndDate => 'Pace and date',
    GoalKind.maintain => 'Maintain my weight',
  };

  static String _kindDetail(GoalKind k) => switch (k) {
    GoalKind.targetAndPace => 'Trendline works out when you get there.',
    GoalKind.targetAndDate => 'Trendline works out the weekly pace.',
    GoalKind.paceAndDate => 'Trendline works out where you end up.',
    GoalKind.maintain => 'Eat at your estimated burn. Good for a diet break.',
  };
}

String _trim(double v) => v == v.roundToDouble()
    ? v.toStringAsFixed(0)
    : '${(v * 100).round() / 100}';

class _NumberField extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onChanged,
    this.helper,
    this.decimal = true,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final String? helper;
  final bool decimal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    decoration: InputDecoration(
      labelText: label.isEmpty ? null : label,
      suffixText: suffix,
      helperText: helper,
      helperMaxLines: 2,
    ),
    onChanged: (_) => onChanged(),
  );
}

/// What the goal works out to with today's trend weight and estimate.
class _Preview extends ConsumerWidget {
  const new({required this.goal, required this.profile});

  final Goal goal;
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final energy = ref.watch(energyProvider).value;
    final unit = profile.weightUnit;

    if (energy == null) {
      return Text(
        'Add a weigh-in to see your daily calories.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      );
    }

    final now = DateTime.now();
    final plan = resolveGoal(goal, trendKg: energy.trendKg, today: now);
    final targets = computeTargets(
      profile: profile,
      tdeeKcal: energy.tdeeKcal,
      bmrKcal: energy.bmrKcal,
      trendKg: energy.trendKg,
      kgPerWeek: plan.kgPerWeek,
      leanMassKg: energy.leanMassKg,
    );
    final target = plan.targetWeightKg;
    final date = target != null && targets.kgPerWeek > 0
        ? (targets.limitedByFloor
              ? projectDate(
                  trendKg: energy.trendKg,
                  targetKg: target,
                  mode: PaceMode.kgPerWeek,
                  kgPerWeekNow: targets.kgPerWeek,
                  from: now,
                )
              : plan.projectedDate)
        : null;

    final notes = <String>[
      ...goalNotes(plan, targets, unit),
      if (date != null && target != null)
        'Reach ${formatWeight(target, unit)} around ${formatLongDate(date)}.',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily target', style: text.bodySmall),
            const SizedBox(height: Space.xs),
            Text(
              '${formatKcal(targets.kcal)} kcal',
              style: text.headlineSmall?.tabular,
            ),
            const SizedBox(height: Space.xs),
            Text(
              targets.kgPerWeek > 0
                  ? 'Losing ${formatPace(targets.kgPerWeek, unit)}'
                  : 'Maintaining',
              style: text.bodyMedium,
            ),
            for (final n in notes) ...[
              const SizedBox(height: Space.sm),
              Text(n, style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plain-language notes on how the plan differs from what was asked.
List<String> goalNotes(GoalPlan plan, DailyTargets t, WeightUnit unit) {
  final capped = formatPace(plan.kgPerWeek, unit);
  final floored = formatPace(t.kgPerWeek, unit);
  final floor = formatKcal(t.floorKcal);
  return [
    if (plan.status == GoalStatus.reached)
      "You're at your target weight, so this plans maintenance.",
    if (plan.status == GoalStatus.datePassed)
      'The goal date has passed, so this plans maintenance. Set a new date.',
    if (plan.cappedByPace)
      'That pace is over 1% of your weight a week, so it is capped at $capped.',
    if (t.limitedByFloor)
      "Calories can't go below $floor kcal, so the pace is $floored.",
  ];
}
