import 'package:meta/meta.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

/// Where a cooked portion is kept.
enum PrepStorage { fridge, freezer }

/// What became of a cooked portion. A leftover is kept for no meal in
/// particular (for example after it was frozen).
enum PortionStatus { planned, eaten, leftover, discarded }

/// How long frozen portions are best eaten within. Frozen food stays safe,
/// but its quality drops after about three months.
const int freezerKeepsDays = 90;

/// One portion of a batch: a share of its cooked weight, for one meal.
@immutable
class PrepPortion {
  const new({
    required this.id,
    required this.sessionId,
    required this.amount,
    required this.useBy,
    this.day,
    this.slot,
    this.storage = PrepStorage.fridge,
    this.status = PortionStatus.planned,
    this.foodLogId,
  });

  final String id;
  final String sessionId;

  /// The meal it's planned for; null for a leftover.
  final DateTime? day;
  final MealSlot? slot;

  /// Portions of the recipe.
  final double amount;
  final DateTime useBy;
  final PrepStorage storage;
  final PortionStatus status;

  /// The log entry made when it was eaten.
  final String? foodLogId;

  /// Still to be eaten (planned or kept as a leftover).
  bool get isOpen =>
      status == PortionStatus.planned || status == PortionStatus.leftover;

  PrepPortion copyWith({
    DateTime? Function()? day,
    MealSlot? Function()? slot,
    DateTime? useBy,
    PrepStorage? storage,
    PortionStatus? status,
    String? Function()? foodLogId,
  }) => PrepPortion(
    id: id,
    sessionId: sessionId,
    amount: amount,
    day: day == null ? this.day : day(),
    slot: slot == null ? this.slot : slot(),
    useBy: useBy ?? this.useBy,
    storage: storage ?? this.storage,
    status: status ?? this.status,
    foodLogId: foodLogId == null ? this.foodLogId : foodLogId(),
  );
}

/// A batch cook: the recipe scaled to [portionCount] portions, cooked on
/// [cookOn], split into [portions].
@immutable
class PrepSession {
  const new({
    required this.id,
    required this.recipeId,
    required this.cookOn,
    required this.portionCount,
    required this.portions,
    this.planId,
    this.cookedAt,
    this.cookedWeightG,
  });

  final String id;
  final String? planId;
  final String recipeId;
  final DateTime cookOn;

  /// How many of the recipe's portions are cooked.
  final double portionCount;

  /// When it was marked cooked, and the batch's measured weight then.
  final DateTime? cookedAt;
  final double? cookedWeightG;

  final List<PrepPortion> portions;

  bool get cooked => cookedAt != null;

  /// Portions still to be eaten.
  List<PrepPortion> get openPortions => [
    for (final p in portions)
      if (p.isOpen) p,
  ];

  /// [portion]'s cooked weight, once the batch has been weighed.
  double? gramsOf(PrepPortion portion) {
    final weight = cookedWeightG;
    if (weight == null || portionCount <= 0) return null;
    return weight * portion.amount / portionCount;
  }

  PrepSession copyWith({
    DateTime? Function()? cookedAt,
    double? Function()? cookedWeightG,
    List<PrepPortion>? portions,
  }) => PrepSession(
    id: id,
    planId: planId,
    recipeId: recipeId,
    cookOn: cookOn,
    portionCount: portionCount,
    cookedAt: cookedAt == null ? this.cookedAt : cookedAt(),
    cookedWeightG: cookedWeightG == null ? this.cookedWeightG : cookedWeightG(),
    portions: portions ?? this.portions,
  );
}

/// Raw grams to weigh out, rounded to what a kitchen scale shows: half
/// grams under 10 g (spices), whole grams above.
double roundIngredientGrams(double grams) =>
    grams < 10 ? (grams * 2).round() / 2 : grams.roundToDouble();

/// [recipe]'s ingredients scaled to cook [portions] portions.
List<RecipeIngredient> scaledIngredients(Recipe recipe, double portions) {
  final factor = portions / recipe.portions;
  return [
    for (final i in recipe.ingredients)
      RecipeIngredient(
        foodId: i.foodId,
        rawGrams: roundIngredientGrams(i.rawGrams * factor),
      ),
  ];
}

/// Roughly what the batch should weigh after cooking: the recipe's
/// measured weight, or else the planner's estimate, scaled. Guidance only.
double? expectedCookedWeightG(Recipe recipe, double portions) {
  final whole = recipe.cookedWeightG ?? recipe.estimatedCookedWeightG;
  return whole == null ? null : whole * portions / recipe.portions;
}

/// Nutrition per 100 g of the cooked batch, from its measured weight, or
/// null until it's weighed or while any ingredient's food is missing.
Nutrition? sessionPer100gCooked(
  PrepSession session,
  Recipe recipe,
  Map<String, Food> foods,
) {
  final weight = session.cookedWeightG;
  if (weight == null || weight <= 0) return null;
  final n = recipeNutrition(recipe, foods);
  if (!n.complete) return null;
  final f = session.portionCount / recipe.portions * 100 / weight;
  final b = n.batch;
  return Nutrition(
    kcal: b.kcal * f,
    proteinG: b.proteinG * f,
    carbsG: b.carbsG * f,
    fatG: b.fatG * f,
    fibreG: b.fibreG * f,
    fibreUnknown: b.fibreUnknown,
  );
}

/// A cooked batch's weight looks wrong next to its raw ingredients, or
/// null if it looks fine. Same bounds as for recipes.
String? sessionWeightWarning(Recipe recipe, PrepSession session, double grams) {
  final scaled = Recipe(
    id: recipe.id,
    name: recipe.name,
    ingredients: scaledIngredients(recipe, session.portionCount),
    portions: recipe.portions,
    cookedWeightG: grams,
  );
  return cookedWeightWarning(scaled);
}

/// The use-by date of a portion frozen on [day].
DateTime freezerUseBy(DateTime day) => addDays(day, freezerKeepsDays);

/// Where an open portion stands on [today].
enum PortionTiming {
  /// Its meal is still to come.
  upcoming,

  /// Its meal is today.
  today,

  /// Its meal has passed but it's still within its use-by date: a leftover
  /// to eat another time or freeze.
  missed,

  /// Past its use-by date.
  expired,
}

PortionTiming portionTiming(PrepPortion portion, DateTime today) {
  if (today.isAfter(portion.useBy)) return PortionTiming.expired;
  final day = portion.day;
  if (day == null || day.isBefore(today)) return PortionTiming.missed;
  return day == today ? PortionTiming.today : PortionTiming.upcoming;
}

/// Sessions worth showing on [today]: those still to cook (including any
/// overdue in the last week) and cooked ones with portions left.
List<PrepSession> activeSessions(List<PrepSession> all, DateTime today) {
  final overdueFrom = addDays(today, -7);
  final active = [
    for (final s in all)
      if (s.cooked
          ? s.openPortions.isNotEmpty
          : !s.cookOn.isBefore(overdueFrom) && s.openPortions.isNotEmpty)
        s,
  ];
  return active..sort((a, b) => a.cookOn.compareTo(b.cookOn));
}
