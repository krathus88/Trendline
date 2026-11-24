import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/domain/weigh_in.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Adds a manual weigh-in, entered in the user's preferred unit.
class WeighInSheet extends ConsumerStatefulWidget {
  const new({required this.unit, super.key});

  final WeightUnit unit;

  @override
  ConsumerState<WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends ConsumerState<WeighInSheet> {
  final _formKey = GlobalKey<FormState>();
  final _main = TextEditingController(); // kg, lb, or stones
  final _pounds = TextEditingController(); // only for st & lb
  final _bodyFat = TextEditingController();
  DateTime _measuredAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _main.dispose();
    _pounds.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  /// The entered weight in kg, or null if incomplete or out of range.
  double? get _weightKg {
    switch (widget.unit) {
      case WeightUnit.kg:
        return parseDecimal(_main.text);
      case WeightUnit.lb:
        final lb = parseDecimal(_main.text);
        return lb == null ? null : lbToKg(lb);
      case WeightUnit.stLb:
        final st = int.tryParse(_main.text.trim());
        final lb = _pounds.text.trim().isEmpty ? 0 : parseDecimal(_pounds.text);
        if (st == null || lb == null || lb < 0 || lb >= lbPerStone) {
          return null;
        }
        return stLbToKg(st, lb.toDouble());
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final isToday =
        picked.year == now.year &&
        picked.month == now.month &&
        picked.day == now.day;
    // Past days default to the morning, when people usually weigh in.
    setState(
      () => _measuredAt = isToday
          ? now
          : DateTime(picked.year, picked.month, picked.day, 8),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final kg = _weightKg!;
    final fat = parseDecimal(_bodyFat.text);
    setState(() => _saving = true);
    try {
      await ref
          .read(weighInsProvider.notifier)
          .add(measuredAt: _measuredAt, weightKg: kg, bodyFatPct: fat);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateWeight(String? _) {
    final kg = _weightKg;
    if (kg == null || !WeighIn.isValidWeight(kg)) {
      return 'Enter a weight between '
          '${formatWeight(WeighIn.minWeightKg, widget.unit)} and '
          '${formatWeight(WeighIn.maxWeightKg, widget.unit)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const decimal = TextInputType.numberWithOptions(decimal: true);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add weigh-in', style: text.titleLarge),
          const SizedBox(height: Space.lg),
          if (widget.unit == WeightUnit.stLb)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _main,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(suffixText: 'st'),
                    validator: _validateWeight,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextFormField(
                    controller: _pounds,
                    keyboardType: decimal,
                    decoration: const InputDecoration(suffixText: 'lb'),
                  ),
                ),
              ],
            )
          else
            TextFormField(
              controller: _main,
              autofocus: true,
              keyboardType: decimal,
              decoration: InputDecoration(
                suffixText: widget.unit == WeightUnit.kg ? 'kg' : 'lb',
              ),
              validator: _validateWeight,
            ),
          const SizedBox(height: Space.md),
          TextFormField(
            controller: _bodyFat,
            keyboardType: decimal,
            decoration: const InputDecoration(
              labelText: 'Body fat (optional)',
              suffixText: '%',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final pct = parseDecimal(v);
              if (pct == null || !WeighIn.isValidBodyFat(pct)) {
                return 'Between 2 and 75%';
              }
              return null;
            },
          ),
          const SizedBox(height: Space.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(formatDateTime(_measuredAt)),
            trailing: TextButton(
              onPressed: _pickDate,
              child: const Text('Change'),
            ),
          ),
          const SizedBox(height: Space.sm),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
