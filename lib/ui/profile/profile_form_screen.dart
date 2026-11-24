import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// First-run setup (with the medical disclaimer), or editing the profile
/// later from Settings when [existing] is given.
class ProfileFormScreen extends ConsumerStatefulWidget {
  const new({super.key, this.existing});

  final Profile? existing;

  bool get isOnboarding => existing == null;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _birthYear;
  late final TextEditingController _height;
  Sex? _sex;
  ActivityLevel _activity = ActivityLevel.light;
  WeightUnit _unit = WeightUnit.kg;
  bool _acceptedDisclaimer = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _birthYear = TextEditingController(text: p?.birthYear.toString() ?? '');
    _height = TextEditingController(
      text: p == null ? '' : p.heightCm.toStringAsFixed(0),
    );
    _sex = p?.sex;
    _activity = p?.activityLevel ?? ActivityLevel.light;
    _unit = p?.weightUnit ?? WeightUnit.kg;
    _acceptedDisclaimer = p != null;
  }

  @override
  void dispose() {
    _birthYear.dispose();
    _height.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_sex == null || !_acceptedDisclaimer) return;

    final profile = Profile(
      sex: _sex!,
      birthYear: int.parse(_birthYear.text.trim()),
      heightCm: parseDecimal(_height.text)!,
      activityLevel: _activity,
      weightUnit: _unit,
      useLeanMass: widget.existing?.useLeanMass ?? false,
      disclaimerAcceptedAt:
          widget.existing?.disclaimerAcceptedAt ?? DateTime.now(),
    );

    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).save(profile);
      if (mounted && !widget.isOnboarding) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final canSave = _sex != null && _acceptedDisclaimer && !_saving;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOnboarding ? 'About you' : 'Profile'),
        automaticallyImplyLeading: !widget.isOnboarding,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxl,
          ),
          children: [
            if (widget.isOnboarding) ...[
              Text(
                'Trendline uses these to estimate your energy needs. You can '
                'change them later.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.xl),
            ],
            const _Label('Sex (for the energy formula)'),
            SegmentedButton<Sex>(
              segments: const [
                ButtonSegment(value: Sex.female, label: Text('Female')),
                ButtonSegment(value: Sex.male, label: Text('Male')),
              ],
              emptySelectionAllowed: true,
              selected: {?_sex},
              onSelectionChanged: (s) =>
                  setState(() => _sex = s.isEmpty ? null : s.first),
            ),
            const SizedBox(height: Space.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _birthYear,
                    decoration: const InputDecoration(labelText: 'Birth year'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final year = int.tryParse(v?.trim() ?? '');
                      final now = DateTime.now().year;
                      if (year == null ||
                          !Profile.isValidBirthYear(year, currentYear: now)) {
                        return 'Enter a year (18+ only)';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextFormField(
                    controller: _height,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      suffixText: 'cm',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final cm = parseDecimal(v ?? '');
                      if (cm == null || !Profile.isValidHeight(cm)) {
                        return '100–250 cm';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            const _Label('Activity outside exercise'),
            RadioGroup<ActivityLevel>(
              groupValue: _activity,
              onChanged: (v) => setState(() => _activity = v ?? _activity),
              child: Column(
                children: [
                  for (final level in ActivityLevel.values)
                    RadioListTile<ActivityLevel>(
                      value: level,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_activityTitle(level)),
                      subtitle: Text(
                        _activityDetail(level),
                        style: text.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            const _Label('Show weights in'),
            SegmentedButton<WeightUnit>(
              segments: const [
                ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                ButtonSegment(value: WeightUnit.stLb, label: Text('st & lb')),
                ButtonSegment(value: WeightUnit.lb, label: Text('lb')),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            if (widget.isOnboarding) ...[
              const SizedBox(height: Space.xl),
              // A Material (not a DecoratedBox) so the checkbox's ripple is
              // drawn on top of the coloured background.
              Material(
                color: colors.surfaceMuted,
                borderRadius: Radii.mdAll,
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Not medical advice', style: text.titleSmall),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Trendline gives estimates, not medical advice. If '
                        'you have a health condition, are pregnant or '
                        'breastfeeding, or have a history of disordered '
                        'eating, talk to your GP before changing how you '
                        'eat.',
                        style: text.bodySmall,
                      ),
                      CheckboxListTile(
                        value: _acceptedDisclaimer,
                        onChanged: (v) =>
                            setState(() => _acceptedDisclaimer = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('I understand', style: text.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: canSave ? _save : null,
              child: Text(widget.isOnboarding ? 'Continue' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

String _activityTitle(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => 'Mostly sitting',
  ActivityLevel.light => 'Lightly active',
  ActivityLevel.moderate => 'Moderately active',
  ActivityLevel.very => 'Very active',
};

String _activityDetail(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => 'Desk job, little walking',
  ActivityLevel.light => 'Some walking most days',
  ActivityLevel.moderate => 'On your feet a lot, or regular exercise',
  ActivityLevel.very => 'Physical job or hard training most days',
};
