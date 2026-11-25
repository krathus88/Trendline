import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/account/account_actions.dart';
import 'package:trendline/data/account/consent_notifier.dart';
import 'package:trendline/data/account/data_export.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/privacy/privacy_policy_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Settings → Privacy and your data: the policy, what was agreed, the data
/// export and account deletion.
class YourDataScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<YourDataScreen> createState() => _YourDataScreenState();
}

class _YourDataScreenState extends ConsumerState<YourDataScreen> {
  /// The export being saved, if any.
  ExportFile? _exporting;
  bool _deleting = false;

  bool get _busy => _exporting != null || _deleting;

  Future<void> _export(ExportFile file) async {
    setState(() => _exporting = file);
    try {
      final saved = await ref.read(accountActionsProvider).export(file);
      if (saved && mounted) showMessageSnack(context, 'Saved');
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(accountActionsProvider).deleteAccount();
      // Signed out: back to the sign-in screen underneath.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        showErrorSnack(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(consentProvider).value;
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy and your data')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        children: [
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy policy'),
            subtitle: Text(
              consent == null
                  ? 'What Trendline stores and why'
                  : 'You agreed on ${formatLongDate(consent.consentedAt)} '
                        '(version ${consent.policyVersion})',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacyPolicyScreen(),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.md,
              Space.gutter,
              Space.xs,
            ),
            child: Text('Export my data', style: text.titleSmall),
          ),
          for (final file in ExportFile.values)
            ListTile(
              leading: _exporting == file
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              title: Text(file.label),
              subtitle: Text(file.description),
              enabled: !_busy,
              onTap: () => _export(file),
            ),
          const Divider(),
          ListTile(
            leading: _deleting
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.delete_forever_outlined, color: colors.error),
            title: Text(
              'Delete my account',
              style: TextStyle(color: colors.error),
            ),
            subtitle: const Text(
              'Deletes everything for good and withdraws your consent',
            ),
            enabled: !_busy,
            onTap: _delete,
          ),
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Text(
              'Readings stay in Health Connect on your phone: deleting your '
              'account removes only Trendline’s copy. To stop Trendline '
              'reading them, turn its access off in Health Connect.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Makes sure deleting the account is meant: the user types DELETE.
class _DeleteAccountDialog extends StatefulWidget {
  const new();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _word = 'DELETE';
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This deletes your profile, weigh-ins, food log, goals, '
              'foods, recipes, plans, prep and shares straight away, and '
              'takes you off the invite list. It can’t be undone. Recipes '
              'you shared with a household stay with the household.\n\n'
              'Export your data first if you want a copy.',
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _typed,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Type $_word to confirm',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _typed.text.trim().toUpperCase() == _word
              ? () => Navigator.of(context).pop(true)
              : null,
          style: TextButton.styleFrom(foregroundColor: colors.error),
          child: const Text('Delete for good'),
        ),
      ],
    );
  }
}
