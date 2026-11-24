import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/app_info.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/energy/energy_repository.dart';
import 'package:trendline/data/food_logs/food_log_repository.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/foods/reference_food_repository.dart';
import 'package:trendline/data/goals/goal_repository.dart';
import 'package:trendline/data/off/off_client.dart';
import 'package:trendline/data/profile/profile_repository.dart';
import 'package:trendline/data/recipes/recipe_repository.dart';
import 'package:trendline/data/weigh_ins/weigh_in_repository.dart';
import 'package:trendline/platform/barcode_scanner.dart';
import 'package:trendline/platform/health_source.dart';

// ---------------------------------------------------------------------------
// Infrastructure. Overridden in main.dart (real) and in tests (fakes).
// ---------------------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => throw UnimplementedError('supabaseClientProvider not overridden'),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider).auth),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);

final weighInRepositoryProvider = Provider<WeighInRepository>(
  (ref) => SupabaseWeighInRepository(ref.watch(supabaseClientProvider)),
);

final foodRepositoryProvider = Provider<FoodRepository>(
  (ref) => SupabaseFoodRepository(ref.watch(supabaseClientProvider)),
);

final referenceFoodRepositoryProvider = Provider<ReferenceFoodRepository>(
  (ref) => SupabaseReferenceFoodRepository(ref.watch(supabaseClientProvider)),
);

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => SupabaseRecipeRepository(ref.watch(supabaseClientProvider)),
);

final foodLogRepositoryProvider = Provider<FoodLogRepository>(
  (ref) => SupabaseFoodLogRepository(ref.watch(supabaseClientProvider)),
);

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => SupabaseGoalRepository(ref.watch(supabaseClientProvider)),
);

final energyRepositoryProvider = Provider<EnergyRepository>(
  (ref) => SupabaseEnergyRepository(ref.watch(supabaseClientProvider)),
);

final offClientProvider = Provider<OffClient>((ref) {
  final client = OffClient(userAgent: offUserAgent(appVersion, appContact));
  ref.onDispose(client.close);
  return client;
});

final barcodeScannerProvider = Provider<BarcodeScanner>(
  (ref) => createBarcodeScanner(),
);

final healthSourceProvider = Provider<HealthSource>(
  (ref) => createHealthSource(),
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

final authStatusProvider = StreamProvider<AuthStatus>(
  (ref) => ref.watch(authRepositoryProvider).watchStatus(),
);

final authFailuresProvider = StreamProvider<AuthFailure>(
  (ref) => ref.watch(authRepositoryProvider).watchFailures(),
);

/// The signed-in user's ID, or null. Every data provider watches this, so
/// switching accounts drops everything cached for the previous one.
final currentUserIdProvider = Provider<String?>(
  (ref) => switch (ref.watch(authStatusProvider)) {
    AsyncData(value: SignedIn(:final userId)) => userId,
    _ => null,
  },
);
