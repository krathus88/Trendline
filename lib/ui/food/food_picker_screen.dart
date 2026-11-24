import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/food_browser.dart';
import 'package:trendline/ui/food/portion_sheet.dart';

/// Pick a food and portion to log into [slot] on [day].
class FoodPickerScreen extends ConsumerStatefulWidget {
  const new({required this.day, required this.slot, super.key});

  final DateTime day;
  final MealSlot slot;

  @override
  ConsumerState<FoodPickerScreen> createState() => _FoodPickerScreenState();
}

class _FoodPickerScreenState extends ConsumerState<FoodPickerScreen> {
  bool _logging = false;

  Future<void> _onChosen(FoodChoice choice) async {
    if (_logging) return;
    final result = await showAppSheet<PortionResult>(
      context,
      builder: (_) => PortionSheet(
        title: choice.name,
        subtitle: choice.brand,
        per100g: choice.per100g,
        servingG: choice.servingG,
        actionLabel: 'Add to ${mealSlotLabel(widget.slot).toLowerCase()}',
      ),
    );
    if (result is! PortionGrams || !mounted) return;

    setState(() => _logging = true);
    try {
      // New foods are saved first, so they're quick to find next time.
      final food = switch (choice) {
        SavedFood(:final food) => food,
        NewFood(:final draft) =>
          await ref.read(foodsProvider.notifier).save(draft),
      };
      await ref
          .read(foodLogProvider(widget.day).notifier)
          .add(slot: widget.slot, food: food, grams: result.grams);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${mealSlotLabel(widget.slot).toLowerCase()}'),
        bottom: _logging
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: FoodBrowser(onChosen: _onChosen),
    );
  }
}
