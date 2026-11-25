import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';

/// What a read-only share can include. Each is switched on per viewer.
enum ShareKind {
  /// Weigh-in dates and weights (never body fat or lean mass), for the
  /// trend.
  weight,

  /// The daily calorie, protein, carb, fat and fibre targets.
  targets,

  /// The week's meal plans: what's planned, how much, and its kcal.
  plans;

  String get label => switch (this) {
    weight => 'Weight trend',
    targets => 'Daily targets',
    plans => 'Meal plans',
  };
}

/// One person letting another see some of their data. The owner chooses
/// what; either side can end it.
@immutable
class Share {
  const new({
    required this.id,
    required this.ownerId,
    required this.viewerId,
    required this.ownerName,
    required this.viewerName,
    required this.kinds,
  });

  final String id;
  final String ownerId;
  final String viewerId;

  /// The names each side chose to show the other.
  final String ownerName;
  final String viewerName;
  final Set<ShareKind> kinds;

  bool includes(ShareKind kind) => kinds.contains(kind);

  Share withKinds(Set<ShareKind> kinds) => Share(
    id: id,
    ownerId: ownerId,
    viewerId: viewerId,
    ownerName: ownerName,
    viewerName: viewerName,
    kinds: kinds,
  );
}

/// A single-use code that makes a share of [kinds] when someone accepts it.
@immutable
class ShareInvite {
  const new({
    required this.code,
    required this.ownerName,
    required this.kinds,
    required this.expiresAt,
  });

  final String code;
  final String ownerName;
  final Set<ShareKind> kinds;
  final DateTime expiresAt;
}

/// The user's shares both ways, and their open invites.
@immutable
class SharingState {
  const new({
    required this.outgoing,
    required this.incoming,
    this.invites = const [],
  });

  static const empty = SharingState(outgoing: [], incoming: []);

  /// People the user shares with.
  final List<Share> outgoing;

  /// People who share with the user.
  final List<Share> incoming;
  final List<ShareInvite> invites;

  bool get sharesTargets => outgoing.any((s) => s.includes(ShareKind.targets));
}

/// The daily targets as a viewer sees them: the numbers only.
@immutable
class SharedTargets {
  const new({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fibreG,
    this.updatedAt,
  });

  /// The numbers an owner publishes, rounded as the database stores them.
  factory of(DailyTargets t) => SharedTargets(
    kcal: _round1(t.kcal),
    proteinG: _round1(t.proteinG),
    carbsG: _round1(t.carbsG),
    fatG: _round1(t.fatG),
    fibreG: _round1(t.fibreG),
  );

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fibreG;

  /// When the owner's app last published them.
  final DateTime? updatedAt;

  /// Within the database's ranges, so it can be published.
  bool get isValid =>
      kcal >= 800 &&
      kcal <= 6000 &&
      proteinG >= 0 &&
      proteinG <= 500 &&
      carbsG >= 0 &&
      carbsG <= 1000 &&
      fatG >= 0 &&
      fatG <= 500 &&
      fibreG >= 0 &&
      fibreG <= 200;

  bool sameNumbers(SharedTargets other) =>
      kcal == other.kcal &&
      proteinG == other.proteinG &&
      carbsG == other.carbsG &&
      fatG == other.fatG &&
      fibreG == other.fibreG;

  static double _round1(double v) => (v * 10).round() / 10;
}

/// One item of a shared plan.
@immutable
class SharedPlanItem {
  const new({
    required this.day,
    required this.slot,
    required this.name,
    required this.amount,
    required this.isRecipe,
    required this.kcal,
    required this.proteinG,
  });

  final DateTime day;
  final MealSlot slot;
  final String name;

  /// Portions of a recipe, or grams of a food.
  final double amount;
  final bool isRecipe;
  final double kcal;
  final double proteinG;
}
