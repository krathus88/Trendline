import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/health/health_sync_notifier.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/food/food_screen.dart';
import 'package:trendline/ui/plan/plan_screen.dart';
import 'package:trendline/ui/progress/progress_screen.dart';
import 'package:trendline/ui/settings/settings_screen.dart';
import 'package:trendline/ui/today/today_screen.dart';

/// The main app: bottom navigation between the top-level screens. Each tab
/// keeps its state (scroll position, chosen day) when you switch away.
///
/// Also keeps the Health Connect sync running: it syncs on start and again
/// whenever the app comes back to the foreground.
class HomeShell extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(healthSyncProvider.notifier).recheck().ignore(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  static const _tabs = <Widget>[
    TodayScreen(),
    PlanScreen(),
    FoodScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(healthSyncProvider, (previous, next) {
      final before = previous?.value?.lastSyncedAt;
      final now = next.value;
      final added = now?.lastAdded ?? 0;
      if (now?.lastSyncedAt != before && added > 0) {
        showMessageSnack(
          context,
          added == 1
              ? 'Added 1 weigh-in from Health Connect'
              : 'Added $added weigh-ins from Health Connect',
        );
      }
    });

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Food',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
