import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  AuthFailure? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithDiscord();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Failures that arrive after the browser returns (e.g. not invited).
    ref.listen(authFailuresProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        setState(() {
          _error = value;
          _busy = false;
        });
      }
    });

    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Trendline', style: text.displaySmall),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Plan your week of food. Follow the trend, not the '
                    'scale.',
                    style: text.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.xxl),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: AnimatedSwitcher(
                      duration: Motion.fast,
                      child: _busy
                          ? SizedBox.square(
                              key: const ValueKey('busy'),
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onAccent,
                              ),
                            )
                          : const Text(
                              'Continue with Discord',
                              key: ValueKey('label'),
                            ),
                    ),
                  ),
                  AnimatedSize(
                    duration: Motion.medium,
                    curve: Motion.standard,
                    child: error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: Space.lg),
                            child: Text(
                              error.message,
                              style: text.bodyMedium?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: Space.xl),
                  Text(
                    'Invite only. Ask the app owner to add your Discord '
                    'account.',
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
