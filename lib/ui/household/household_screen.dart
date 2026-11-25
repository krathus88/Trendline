import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// What joining means, shown before creating or joining.
const householdPrivacyNote =
    'A household shares recipes with the people you live with. Members '
    'will see each other’s portion sizes once plans are shared, which '
    'roughly shows calorie targets. Your weight, goal and food log are '
    'never shared. You can leave at any time.';

/// Create or join a household, or manage the one the user is in.
class HouseholdScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: switch (household) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(householdProvider),
        ),
        AsyncLoading() when !household.hasValue => const CenteredProgress(),
        _ => switch (household.value) {
          final h? => _Members(household: h),
          null => const _NoHousehold(),
        },
      },
    );
  }
}

class _NoHousehold extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        Text('You’re not in a household', style: text.titleMedium),
        const SizedBox(height: Space.sm),
        Text(householdPrivacyNote, style: text.bodyMedium),
        const SizedBox(height: Space.xl),
        FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add_home_outlined),
          label: const Text('Create a household'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: () => _join(context, ref),
          icon: const Icon(Icons.vpn_key_outlined),
          label: const Text('Join with a code'),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _NamesDialog(
        title: 'Create a household',
        firstLabel: 'Household name',
        firstHint: 'e.g. Flat 2',
        action: 'Create',
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(householdProvider.notifier)
          .create(name: result.$1, displayName: result.$2);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _NamesDialog(
        title: 'Join a household',
        firstLabel: 'Invite code',
        firstHint: 'From the household’s owner',
        action: 'Join',
        isCode: true,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(householdProvider.notifier)
          .join(code: result.$1, displayName: result.$2);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }
}

/// Asks for a household name (or an invite code) and the name the others
/// will see.
class _NamesDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.firstLabel,
    required this.firstHint,
    required this.action,
    this.isCode = false,
  });

  final String title;
  final String firstLabel;
  final String firstHint;
  final String action;
  final bool isCode;

  @override
  State<_NamesDialog> createState() => _NamesDialogState();
}

class _NamesDialogState extends State<_NamesDialog> {
  final _first = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final firstProblem = widget.isCode
        ? (normaliseInviteCode(_first.text) == null
              ? 'Enter the 10-character code.'
              : null)
        : validateHouseholdName(_first.text, label: 'a household name');
    final problem = firstProblem ?? validateDisplayName(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop((_first.text, _name.text));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _first,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.firstLabel,
                hintText: widget.firstHint,
              ),
              textCapitalization: widget.isCode
                  ? TextCapitalization.characters
                  : TextCapitalization.words,
              maxLength: widget.isCode ? 11 : Household.maxNameLength,
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Your name',
                helperText: 'What the others see',
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: Household.maxDisplayNameLength,
              onSubmitted: (_) => _submit(),
            ),
            if (widget.isCode) ...[
              const SizedBox(height: Space.sm),
              Text(householdPrivacyNote, style: text.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                style: text.bodySmall?.copyWith(color: context.colors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

class _Members extends ConsumerWidget {
  const new({required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final me = ref.watch(currentUserIdProvider);
    final owner = me != null && household.isOwner(me);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xs,
          ),
          child: Text(household.name, style: text.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Text(
            'Recipes shared here show in everyone’s Recipes tab.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ),
        const SizedBox(height: Space.md),
        _Heading(
          'Members (${household.members.length} of '
          '${Household.maxMembers})',
        ),
        for (final m in household.members)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              m.userId == me ? '${m.displayName} (you)' : m.displayName,
            ),
            subtitle: m.isOwner ? const Text('Owner') : null,
            trailing: owner && m.userId != me
                ? IconButton(
                    tooltip: 'Remove ${m.displayName}',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _remove(context, ref, m),
                  )
                : null,
          ),
        if (owner) ...[
          const SizedBox(height: Space.md),
          const _Heading('Invite codes'),
          for (final i in household.invites)
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: Text(
                formatInviteCode(i.code),
                style: text.titleMedium?.copyWith(letterSpacing: 1.5),
              ),
              subtitle: Text(
                'Works once, until ${_when(context, i.expiresAt)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Copy code',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: i.code));
                      if (context.mounted) {
                        showMessageSnack(context, 'Code copied');
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Withdraw code',
                    icon: const Icon(Icons.close),
                    onPressed: () => ref
                        .read(householdProvider.notifier)
                        .withdrawInvite(i.code)
                        .catchError((Object e) {
                          if (context.mounted) showErrorSnack(context, e);
                        }),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: household.isFull
                    ? null
                    : () => ref
                          .read(householdProvider.notifier)
                          .invite()
                          .then(
                            (_) {},
                            onError: (Object e) {
                              if (context.mounted) showErrorSnack(context, e);
                            },
                          ),
                icon: const Icon(Icons.add),
                label: Text(
                  household.isFull
                      ? 'The household is full'
                      : 'New invite code',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Text(
              'Give a code to someone you live with. It works once and '
              'lasts 2 days.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
        const SizedBox(height: Space.lg),
        const Divider(),
        ListTile(
          leading: Icon(Icons.logout, color: colors.error),
          title: Text('Leave household', style: TextStyle(color: colors.error)),
          subtitle: Text(
            household.members.length == 1
                ? 'You’re the last member: the household and its shared '
                      'recipes will be deleted'
                : 'What you shared stays with the household',
          ),
          onTap: () => _leave(context, ref),
        ),
      ],
    );
  }

  static String _when(BuildContext context, DateTime t) {
    final local = t.toLocal();
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '${local.day}/${local.month} $time';
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    HouseholdMember member,
  ) async {
    final sure = await _confirm(
      context,
      title: 'Remove ${member.displayName}?',
      body:
          'They lose access to the household’s recipes straight away. '
          'What they shared stays.',
      action: 'Remove',
    );
    if (!sure || !context.mounted) return;
    try {
      await ref.read(householdProvider.notifier).remove(member.userId);
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final last = household.members.length == 1;
    final sure = await _confirm(
      context,
      title: 'Leave ${household.name}?',
      body: last
          ? 'You’re the last member, so the household and its shared '
                'recipes will be deleted. Copy any you want to keep to your '
                'own recipes first.'
          : 'You lose access to its shared recipes straight away. Copy any '
                'you want to keep to your own recipes first.',
      action: 'Leave',
    );
    if (!sure || !context.mounted) return;
    try {
      await ref.read(householdProvider.notifier).leave();
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  static Future<bool> _confirm(
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
}

class _Heading extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.sm,
      Space.gutter,
      Space.xs,
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}
