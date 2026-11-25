import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/domain/weigh_in.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/schedule/onboarding_schedule_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// Sets the goal: lose, maintain or gain, and for losing or gaining any two
/// of target weight, pace and date. Shows what will actually be planned,
/// including any cap or floor.
class GoalScreen extends ConsumerStatefulWidget {
  const new({super.key, this.existing, this.onboarding = false});

  final Goal? existing;

  /// First run: no back button, and saving continues into the app.
  final bool onboarding;

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

enum _Aim { lose, maintain, gain }

/// Pace entry: the user's weight unit per week, or percent per week.
enum _PaceUnit { weight, percent }

/// The kinds that fix two values (maintenance is chosen with [_Aim]).
const List<GoalKind> _twoOfThree = [
  GoalKind.targetAndPace,
  GoalKind.targetAndDate,
  GoalKind.paceAndDate,
];

class _GoalScreenState extends ConsumerState<GoalScreen> {
  late _Aim _aim;
  late GoalKind _kind;
  late _PaceUnit _paceUnit;
  final _target = TextEditingController(); // kg, lb or stones
  final _targetLb = TextEditingController(); // pounds, for st & lb only
  final _pace = TextEditingController();
  DateTime? _date;
  bool _saving = false;
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _aim = switch (g) {
      null => _Aim.lose,
      Goal(kind: GoalKind.maintain) => _Aim.maintain,
      Goal(direction: GoalDirection.gain) => _Aim.gain,
      _ => _Aim.lose,
    };
    _kind = g == null || g.kind == GoalKind.maintain
        ? GoalKind.targetAndPace
        : g.kind;
    _paceUnit = g?.paceMode == PaceMode.percentPerWeek
        ? _PaceUnit.percent
        : _PaceUnit.weight;
    _date = g?.goalDate;
  }

  /// Fills the fields from the existing goal, once the unit is known.
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

  GoalDirection get _direction =>
      _aim == _Aim.gain ? GoalDirection.gain : GoalDirection.lose;
  bool get _maintaining => _aim == _Aim.maintain;
  bool get _usesTarget =>
      !_maintaining &&
      (_kind == GoalKind.targetAndPace || _kind == GoalKind.targetAndDate);
  bool get _usesPace =>
      !_maintaining &&
      (_kind == GoalKind.targetAndPace || _kind == GoalKind.paceAndDate);
  bool get _usesDate =>
      !_maintaining &&
      (_kind == GoalKind.targetAndDate || _kind == GoalKind.paceAndDate);
  double get _capPercent => maxPacePercent(_direction);

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
    if (_paceUnit == _PaceUnit.percent) return v > _capPercent ? null : v;
    final kg = unit == WeightUnit.kg ? v : lbToKg(v);
    return kg > 4 ? null : kg;
  }

  /// The goal as entered, or null with the reason it can't be saved.
  (Goal?, String?) _goal(WeightUnit unit, double? trendKg) {
    if (_maintaining) return (Goal.maintenance, null);
    final target = _usesTarget ? _targetKg(unit) : null;
    final pace = _usesPace ? _paceValue(unit) : null;
    if (_usesTarget && (target == null || !WeighIn.isValidWeight(target))) {
      return (null, 'Enter a target weight.');
    }
    if (target != null && trendKg != null) {
      final now = formatWeight(trendKg, unit);
      if (_aim == _Aim.lose && target >= trendKg) {
        return (null, 'To lose weight, aim below your trend weight ($now).');
      }
      if (_aim == _Aim.gain && target <= trendKg) {
        return (null, 'To gain weight, aim above your trend weight ($now).');
      }
    }
    if (_usesPace && pace == null) {
      final cap = _trim(_capPercent);
      return (
        null,
        _paceUnit == _PaceUnit.percent
            ? 'Enter a pace up to $cap% a week.'
            : 'Enter a weekly pace.',
      );
    }
    if (_usesDate && _date == null) return (null, 'Pick a goal date.');
    return (
      Goal(
        kind: _kind,
        direction: _direction,
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
    // In onboarding, saving the goal swaps this screen for the app, so the
    // day schedule step goes on the navigator above it.
    final navigator = Navigator.of(context);
    final scheduleSet =
        ref.read(scheduleProvider).value?.any((d) => d.isSet) ?? false;
    try {
      await ref.read(goalProvider.notifier).save(goal);
      if (widget.onboarding) {
        if (!scheduleSet) {
          navigator
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScheduleScreen(),
                ),
              )
              .ignore();
        }
      } else if (mounted) {
        navigator.pop();
      }
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
    final energy = ref.watch(energyProvider).value;
    // Loaded in onboarding so saving knows whether the day schedule step
    // is still to do.
    if (widget.onboarding) ref.watch(scheduleProvider);
    final unit = profile?.weightUnit ?? WeightUnit.kg;
    _fill(unit);
    final (goal, problem) = _goal(unit, energy?.trendKg);
    final weightUnitLabel = unit == WeightUnit.kg ? 'kg' : 'lb';
    final verb = _aim == _Aim.gain ? 'gain' : 'lose';
    final cap = _trim(_capPercent);

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
          SegmentedButton<_Aim>(
            segments: const [
              ButtonSegment(value: _Aim.lose, label: Text('Lose')),
              ButtonSegment(value: _Aim.maintain, label: Text('Maintain')),
              ButtonSegment(value: _Aim.gain, label: Text('Gain')),
            ],
            selected: {_aim},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _aim = s.first),
          ),
          const SizedBox(height: Space.lg),
          if (_maintaining)
            Text(
              'Eat at your estimated burn. Good for holding a new weight or '
              'a break from dieting.',
              style: text.bodyMedium,
            )
          else ...[
            Text(
              'Set any two of target weight, pace and date. Trendline works '
              'out the third, and your daily calories.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.sm),
            RadioGroup<GoalKind>(
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v ?? _kind),
              child: Column(
                children: [
                  for (final kind in _twoOfThree)
                    RadioListTile<GoalKind>(
                      value: kind,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_kindTitle(kind)),
                      subtitle: Text(
                        _kindDetail(kind, verb),
                        style: text.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                  ? 'Up to $cap%. A percentage changes with your weight.'
                  : 'Plans above $cap% of your weight a week are capped.',
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
    GoalKind.maintain => 'Maintain',
  };

  static String _kindDetail(GoalKind k, String verb) => switch (k) {
    GoalKind.targetAndPace => 'Trendline works out when you get there.',
    GoalKind.targetAndDate => 'Trendline works out how fast to $verb.',
    GoalKind.paceAndDate => 'Trendline works out where you end up.',
    GoalKind.maintain => '',
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

    final outlook = outlookFor(
      goal: goal,
      profile: profile,
      tdeeKcal: energy.tdeeKcal,
      bmrKcal: energy.bmrKcal,
      trendKg: energy.trendKg,
      leanMassKg: energy.leanMassKg,
      today: DateTime.now(),
    );
    final target = outlook.plan.targetWeightKg;
    final date = outlook.projectedDate;
    final notes = <String>[
      ...goalNotes(
        outlook.plan,
        outlook.targets,
        unit,
        strengthTraining: profile.strengthTraining,
      ),
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
              '${formatKcal(outlook.targets.kcal)} kcal',
              style: text.headlineSmall?.tabular,
            ),
            const SizedBox(height: Space.xs),
            Text(
              changeLabel(outlook.targets.weeklyChangeKg, unit),
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.sm),
            Text(proteinLabel(outlook.targets), style: text.bodySmall),
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

/// "Losing 0.5 kg/week", "Gaining 0.25 kg/week" or "Maintaining".
String changeLabel(double weeklyChangeKg, WeightUnit unit) {
  if (weeklyChangeKg.abs() < 1e-6) return 'Maintaining';
  final pace = formatPace(weeklyChangeKg.abs(), unit);
  return weeklyChangeKg < 0 ? 'Losing $pace' : 'Gaining $pace';
}

/// "Protein: at least 130 g a day, based on your lean mass".
String proteinLabel(DailyTargets t) {
  final basis = switch (t.proteinBasis) {
    ProteinBasis.leanMass => 'your lean mass from your scale',
    ProteinBasis.bodyWeight => 'your weight',
  };
  return 'Protein: at least ${t.proteinG.round()} g a day, based on $basis.';
}

/// Plain-language notes on how the plan differs from what was asked, and
/// anything worth knowing about it.
List<String> goalNotes(
  GoalPlan plan,
  DailyTargets t,
  WeightUnit unit, {
  required bool strengthTraining,
}) {
  final capped = formatPace(plan.kgPerWeek, unit);
  final cap = _trim(maxPacePercent(plan.direction));
  final cappedNote =
      'That pace is over $cap% of your weight a week, so it is capped at '
      '$capped.';
  final floored = changeLabel(t.weeklyChangeKg, unit).toLowerCase();
  final floor = formatKcal(t.floorKcal);
  return [
    if (plan.status == GoalStatus.reached)
      "You've reached your target weight, so this plans maintenance.",
    if (plan.status == GoalStatus.datePassed)
      'The goal date has passed, so this plans maintenance. Set a new date.',
    if (plan.cappedByPace) cappedNote,
    if (t.limitedByFloor)
      "Calories can't go below $floor kcal, so you'll be $floored.",
    if (plan.direction == GoalDirection.gain &&
        plan.status == GoalStatus.gaining) ...[
      if (!strengthTraining) _gainWithoutTraining,
      _gainWhenExperienced,
    ],
  ];
}

const String _gainWithoutTraining =
    'Without strength training, most of the weight gained will be fat. '
    'Training is what turns the extra food into muscle.';

const String _gainWhenExperienced =
    'If you have been lifting for years, gain more slowly than this: '
    'about 0.25% a week.';
