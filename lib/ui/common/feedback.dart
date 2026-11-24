import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/off/off_client.dart';
import 'package:trendline/data/plans/plan_notifier.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/platform/health_source.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// A message that's safe to show for [error]. Database and network errors
/// are never shown raw: they can contain internal details.
String userMessage(Object error) => switch (error) {
  OffException(:final message) => message,
  AuthFailure(:final message) => message,
  HealthSourceException(:final message) => message,
  FoodInUse(:final message) => message,
  LibraryFoodMissing(:final message) => message,
  PlanNeedsTargets(:final message) => message,
  PlanNotSaved(:final message) => message,
  PrepNotWeighed(:final message) => message,
  _ => 'Something went wrong. Check your connection and try again.',
};

void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(userMessage(error))));
}

void showMessageSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A full-area error with a retry button.
class ErrorView extends StatelessWidget {
  const new({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              userMessage(error),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: Space.lg),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// A quiet message for an empty list.
class EmptyState extends StatelessWidget {
  const new({required this.title, this.message, super.key});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xxl,
      ),
      child: Column(
        children: [
          Text(title, style: text.titleSmall, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class CenteredProgress extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Opens a bottom sheet that moves up with the keyboard.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.colors.surface,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        child: builder(sheetContext),
      ),
    ),
  ),
);
