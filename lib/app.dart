import 'package:material_ui/material_ui.dart';
import 'package:trendline/ui/auth/auth_gate.dart';
import 'package:trendline/ui/privacy/privacy_policy_screen.dart';
import 'package:trendline/ui/setup/missing_config_screen.dart';
import 'package:trendline/ui/theme/app_theme.dart';

/// The route Android opens the app on when Health Connect asks why it
/// wants access (set by MainActivity).
const String privacyPolicyRoute = '/privacy-policy';

enum _Mode { app, missingConfig, privacyPolicy }

class TrendlineApp extends StatelessWidget {
  /// The normal app: sign-in, then the main screens.
  const new({super.key}) : _mode = _Mode.app;

  /// Shown when the build has no Supabase settings.
  const new missingConfig({super.key}) : _mode = _Mode.missingConfig;

  /// Just the privacy policy, for Health Connect's permission screen. Needs
  /// no sign-in and no connection.
  const new privacyPolicy({super.key}) : _mode = _Mode.privacyPolicy;

  final _Mode _mode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trendline',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: switch (_mode) {
        _Mode.app => const AuthGate(),
        _Mode.missingConfig => const MissingConfigScreen(),
        _Mode.privacyPolicy => const PrivacyPolicyScreen(standalone: true),
      },
    );
  }
}
