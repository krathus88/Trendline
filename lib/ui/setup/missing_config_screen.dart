import 'package:material_ui/material_ui.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Shown when the app was built without Supabase settings, instead of
/// crashing on start-up.
class MissingConfigScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Supabase is not configured', style: text.titleLarge),
              const SizedBox(height: Space.md),
              Text(
                'Copy dart_defines.example.json to dart_defines.json, fill in '
                'the project URL and publishable key, then run:',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: Radii.smAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: SelectableText(
                    'flutter run --dart-define-from-file=dart_defines.json',
                    style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
