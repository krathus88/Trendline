import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/account/consent_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/privacy_policy.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/privacy/privacy_policy_screen.dart';
import 'package:trendline/ui/privacy/your_data_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Asks for explicit consent to process health data, before onboarding and
/// again whenever the privacy policy changes. Nothing else in the app opens
/// until the user agrees.
class ConsentScreen extends ConsumerStatefulWidget {
  const new({super.key, this.updated = false});

  /// True when the user agreed to an earlier version of the policy.
  final bool updated;

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await ref.read(consentProvider.notifier).agree();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.updated ? 'Privacy policy updated' : 'Your data'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          Text(
            widget.updated
                ? 'The privacy policy has changed. Please read it and agree '
                      'again to carry on.'
                : 'Trendline works with health data, so it needs your '
                      'explicit agreement first.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: Space.lg),
          const PolicyBulletList(items: privacySummary),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacyPolicyScreen(),
                ),
              ),
              child: const Text('Read the full privacy policy'),
            ),
          ),
          const SizedBox(height: Space.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agreed,
            onChanged: _saving
                ? null
                : (v) => setState(() => _agreed = v ?? false),
            title: const Text(
              'I agree to Trendline using my health data (weight, body '
              'measurements and food log) as the privacy policy '
              'describes',
            ),
          ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _agreed && !_saving ? _continue : null,
            child: const Text('Continue'),
          ),
          const SizedBox(height: Space.sm),
          if (widget.updated)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const YourDataScreen(),
                      ),
                    ),
              child: const Text('Export or delete my data instead'),
            ),
          TextButton(
            onPressed: _saving ? null : _signOut,
            child: const Text('Not now, sign out'),
          ),
          const SizedBox(height: Space.md),
          Text(
            'You can withdraw your agreement at any time by deleting your '
            'account in Settings → Privacy and your data.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
