import 'package:material_ui/material_ui.dart';
import 'package:trendline/ui/auth/auth_gate.dart';
import 'package:trendline/ui/setup/missing_config_screen.dart';
import 'package:trendline/ui/theme/app_theme.dart';

class TrendlineApp extends StatelessWidget {
  /// The normal app: sign-in, then the main screens.
  const new({super.key}) : _configured = true;

  /// Shown when the build has no Supabase settings.
  const new missingConfig({super.key}) : _configured = false;

  final bool _configured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trendline',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _configured ? const AuthGate() : const MissingConfigScreen(),
    );
  }
}
