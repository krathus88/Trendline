import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/list_snapshot.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';
import 'package:trendline/domain/food.dart';

/// The user's saved foods, by name, cached in memory and on the device.
final foodsProvider = AsyncNotifierProvider<FoodsNotifier, List<Food>>(
  FoodsNotifier.new,
);

class FoodsNotifier extends AsyncNotifier<List<Food>>
    with ListSnapshotMixin<Food> {
  @override
  String get snapshotKey => SnapshotKeys.foods;

  @override
  Map<String, dynamic> toSnapshotRow(Food item) => foodToRow(item);

  @override
  Food fromSnapshotRow(Map<String, dynamic> row) => foodFromRow(row);

  @override
  Future<List<Food>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];
    final repository = ref.watch(foodRepositoryProvider);
    return await loadWithSnapshot(userId, repository.fetchAll);
  }

  /// A saved food with [barcode], if there is one.
  Food? byBarcode(String barcode) {
    for (final food in state.value ?? const <Food>[]) {
      if (food.barcode == barcode) return food;
    }
    return null;
  }

  /// The saved copy of a basic food, if there is one. CoFID codes aren't
  /// unique on their own, so the name must match too.
  Food? byReference(String code, String name) {
    for (final food in state.value ?? const <Food>[]) {
      if (food.referenceCode == code && food.name == name.trim()) return food;
    }
    return null;
  }

  /// Saves [draft], or returns the already-saved food with the same barcode
  /// or copied from the same basic food.
  Future<Food> save(FoodDraft draft) async {
    final barcode = draft.barcode;
    if (barcode != null) {
      final existing = byBarcode(barcode);
      if (existing != null) return existing;
    }
    final code = draft.referenceCode;
    if (code != null) {
      final existing = byReference(code, draft.name);
      if (existing != null) return existing;
    }
    final saved = await ref.read(foodRepositoryProvider).save(draft);
    final current = state.value ?? const <Food>[];
    if (!current.any((f) => f.id == saved.id)) {
      state = AsyncData(_byName([...current, saved]));
    }
    return saved;
  }

  /// Removes the food straight away; puts it back if the delete fails.
  /// Past log entries keep their own copy of the food's details.
  Future<void> delete(String id) async {
    final before = state.value ?? const <Food>[];
    state = AsyncData([
      for (final f in before)
        if (f.id != id) f,
    ]);
    try {
      await ref.read(foodRepositoryProvider).delete(id);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  static List<Food> _byName(List<Food> list) =>
      list
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
