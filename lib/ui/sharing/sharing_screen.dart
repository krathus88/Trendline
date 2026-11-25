import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/sharing/sharing_notifier.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/domain/sharing.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/sharing/shared_view_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// What sharing means, shown before making a code.
const sharingPrivacyNote =
    'Nothing is shared until you make a code. Whoever uses it sees only '
    'what you choose, can’t change anything, and you can switch each part '
    'off or stop sharing at any time. The weight trend shares dates and '
    'weights only, never body fat.';

/// Who the user shares with and who shares with them.
class SharingScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing = ref.watch(sharingProvider);
    return Scaffold(
      // New viewers appear when someone accepts a code on their phone.
      appBar: AppBar(
        title: const Text('Sharing'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sharingProvider),
          ),
        ],
      ),
      body: switch (sharing) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(sharingProvider),
        ),
        AsyncLoading() when !sharing.hasValue => const CenteredProgress(),
        _ => RefreshIndicator(
          onRefresh: () => ref.refresh(sharingProvider.future),
          child: _SharingList(state: sharing.value!),
        ),
      },
    );
  }
}

class _SharingList extends ConsumerWidget {
  const new({required this.state});

  final SharingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final notifier = ref.read(sharingProvider.notifier);

    void report(Object e) {
      if (context.mounted) showErrorSnack(context, e);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        const _Heading('You share with'),
        if (state.outgoing.isEmpty && state.invites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text(
              sharingPrivacyNote,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        for (final share in state.outgoing)
          Card(
            margin: const EdgeInsets.symmetric(
              horizontal: Space.gutter,
              vertical: Space.xs,
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: Text(share.viewerName),
                  subtitle: share.kinds.isEmpty
                      ? const Text('Sees nothing right now')
                      : null,
                  trailing: IconButton(
                    tooltip: 'Stop sharing with ${share.viewerName}',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () async {
                      final sure = await _confirm(
                        context,
                        title: 'Stop sharing with ${share.viewerName}?',
                        body:
                            'They lose access straight away. You can share '
                            'again with a new code.',
                        action: 'Stop sharing',
                      );
                      if (sure) await notifier.end(share).catchError(report);
                    },
                  ),
                ),
                for (final kind in ShareKind.values)
                  SwitchListTile(
                    dense: true,
                    title: Text(kind.label),
                    value: share.includes(kind),
                    onChanged: (on) => notifier
                        .setKind(share, kind, on: on)
                        .catchError(report),
                  ),
              ],
            ),
          ),
        for (final invite in state.invites)
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(
              formatInviteCode(invite.code),
              style: text.titleMedium?.copyWith(letterSpacing: 1.5),
            ),
            subtitle: Text(
              '${_kindsSummary(invite.kinds)} · works once, until '
              '${formatDateTime(invite.expiresAt)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: invite.code));
                    if (context.mounted) {
                      showMessageSnack(context, 'Code copied');
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Withdraw code',
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      notifier.withdrawInvite(invite.code).catchError(report),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _invite(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Share with someone'),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        const Divider(),
        const _Heading('Shared with you'),
        if (state.incoming.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text(
              'When someone gives you a code, enter it here to see what '
              'they share.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        for (final share in state.incoming)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(share.ownerName),
            subtitle: Text(_kindsSummary(share.kinds)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SharedViewScreen(share: share),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _accept(context, ref),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Enter a code'),
            ),
          ),
        ),
      ],
    );
  }

  static String _kindsSummary(Set<ShareKind> kinds) => kinds.isEmpty
      ? 'Nothing shared right now'
      : [
          for (final k in ShareKind.values)
            if (kinds.contains(k)) k.label,
        ].join(', ');

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, Set<ShareKind>)>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(sharingProvider.notifier)
          .invite(ownerName: result.$1, kinds: result.$2);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AcceptDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(sharingProvider.notifier)
          .accept(code: result.$1, viewerName: result.$2);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Asks for the name to show and what to share.
class _InviteDialog extends StatefulWidget {
  const new();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _name = TextEditingController();
  final _kinds = <ShareKind>{};
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final problem =
        validateDisplayName(_name.text) ??
        (_kinds.isEmpty ? 'Choose at least one thing to share.' : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop((_name.text, {..._kinds}));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Share with someone'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sharingPrivacyNote, style: text.bodySmall),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Your name',
                helperText: 'What they see',
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: Household.maxDisplayNameLength,
            ),
            for (final kind in ShareKind.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(kind.label),
                value: _kinds.contains(kind),
                onChanged: (on) => setState(
                  () => on == true ? _kinds.add(kind) : _kinds.remove(kind),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: text.bodySmall?.copyWith(color: context.colors.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Make a code')),
      ],
    );
  }
}

/// Asks for a code and the name the owner will see.
class _AcceptDialog extends StatefulWidget {
  const new();

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final problem =
        (normaliseInviteCode(_code.text) == null
            ? 'Enter the 10-character code.'
            : null) ??
        validateDisplayName(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop((_code.text, _name.text));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Enter a code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Code'),
              textCapitalization: TextCapitalization.characters,
              maxLength: 11,
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Your name',
                helperText: 'What they see',
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: Household.maxDisplayNameLength,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: text.bodySmall?.copyWith(color: context.colors.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('View')),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.md,
      Space.gutter,
      Space.xs,
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}
