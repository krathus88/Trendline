import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/goals.dart';

/// The active goal (null until one is set), cached in memory.
final goalProvider = AsyncNotifierProvider<GoalNotifier, Goal?>(
  GoalNotifier.new,
);

class GoalNotifier extends AsyncNotifier<Goal?> {
  @override
  Future<Goal?> build() async {
    if (ref.watch(currentUserIdProvider) == null) return null;
    return await ref.watch(goalRepositoryProvider).fetchActive();
  }

  Future<void> save(Goal goal) async {
    final saved = await ref.read(goalRepositoryProvider).save(goal);
    state = AsyncData(saved);
  }
}
