import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/health/health_sync_notifier.dart';
import 'package:trendline/data/plans/household_plan_notifier.dart';
import 'package:trendline/data/sharing/sharing_notifier.dart';
import 'package:trendline/data/sync/change_sync.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/food/food_screen.dart';
import 'package:trendline/ui/plan/plan_screen.dart';
import 'package:trendline/ui/progress/progress_screen.dart';
import 'package:trendline/ui/settings/settings_screen.dart';
import 'package:trendline/ui/today/today_screen.dart';

/// The main app: bottom navigation between the top-level screens (a side
/// rail on wide windows). Each tab
/// keeps its state (scroll position, chosen day) when you switch away.
///
/// Also keeps the Health Connect sync running: it syncs on start and again
/// whenever the app comes back to the foreground, when it also fetches
/// what other household members changed.
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
      onResume: () {
        ref.read(healthSyncProvider.notifier).recheck().ignore();
        // Another member may have changed the household's week.
        ref.read(householdRefreshProvider)();
      },
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
    // Publishes the targets while a share includes them. Failures are left
    // for the next change: the viewer sees when they were last updated.
    ref.listen(targetsPublisherProvider, (_, _) {});
    // Changes made on another device, or by the household, show up live.
    ref.listen(changeSyncProvider, (_, _) {});
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

    final tabs = IndexedStack(index: _index, children: _tabs);
    void select(int i) => setState(() => _index = i);

    // Wide windows (desktop, tablets): a side rail, with the screens kept to
    // a readable column instead of stretched across the window.
    if (MediaQuery.sizeOf(context).width >= wideLayoutMinWidth) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -1,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: wideContentMaxWidth,
                  ),
                  child: tabs,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: tabs,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// From this window width, the side rail replaces the bottom bar (Material's
/// "expanded" size class).
const double wideLayoutMinWidth = 840;

/// The widest the screens get in the wide layout.
const double wideContentMaxWidth = 760;

typedef _Destination = ({IconData icon, IconData selectedIcon, String label});

const List<_Destination> _destinations = [
  (icon: Icons.today_outlined, selectedIcon: Icons.today, label: 'Today'),
  (
    icon: Icons.calendar_view_week_outlined,
    selectedIcon: Icons.calendar_view_week,
    label: 'Plan',
  ),
  (
    icon: Icons.restaurant_outlined,
    selectedIcon: Icons.restaurant,
    label: 'Food',
  ),
  (icon: Icons.show_chart, selectedIcon: Icons.show_chart, label: 'Progress'),
  (
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  ),
];
