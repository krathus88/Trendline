import 'package:material_ui/material_ui.dart';

/// Whether the app runs on a desktop (mouse and keyboard first). Desktop has
/// no pull-to-refresh, since a mouse can't drag a list, so screens offer a
/// [RefreshAction] there instead.
bool isDesktop(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.windows ||
  TargetPlatform.linux ||
  TargetPlatform.macOS => true,
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => false,
};

/// An app bar refresh button for desktop, standing in for pull-to-refresh.
/// Shows nothing on phones. Spins while [onRefresh] runs and ignores taps
/// until it finishes.
class RefreshAction extends StatefulWidget {
  const new({required this.onRefresh, super.key});

  final Future<void> Function() onRefresh;

  @override
  State<RefreshAction> createState() => _RefreshActionState();
}

class _RefreshActionState extends State<RefreshAction> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop(context)) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Refresh',
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }
}
