import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/add_transaction_sheet.dart';
import 'account_screen.dart';
import 'ai_financial_assistant_screen.dart';
import 'analytics_screen.dart';
import 'home_screen.dart';

/// Publishes how much bottom padding scrollable tab content needs so it clears
/// the docked FAB. Screens read this instead of hard-coding magic numbers.
class NavShellInsets extends InheritedWidget {
  final double contentBottom;

  const NavShellInsets({
    super.key,
    required this.contentBottom,
    required super.child,
  });

  /// Bottom inset for tab content. Falls back to a plain gutter when the screen
  /// is pushed as a standalone route rather than hosted in the tab shell.
  static double of(BuildContext context) {
    final insets = context
        .dependOnInheritedWidgetOfExactType<NavShellInsets>();
    return insets?.contentBottom ?? AppTokens.gapLg;
  }

  @override
  bool updateShouldNotify(NavShellInsets oldWidget) =>
      oldWidget.contentBottom != contentBottom;
}

class MainNavigation extends StatefulWidget {
  final int initialIndex;

  const MainNavigation({super.key, this.initialIndex = 0});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  static const _destinations = <_NavDestination>[
    _NavDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavDestination(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
      label: 'Analytics',
    ),
    _NavDestination(
      icon: Icons.smart_toy_outlined,
      selectedIcon: Icons.smart_toy_rounded,
      label: 'Assistant',
    ),
    _NavDestination(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Account',
    ),
  ];

  late int _selectedIndex;
  late final AnimationController _pageFade;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, _destinations.length - 1);
    _pageFade = AnimationController(
      vsync: this,
      duration: AppTokens.motionFast,
      value: 1,
    );
  }

  @override
  void dispose() {
    _pageFade.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _selectedIndex) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
    _pageFade
      ..reset()
      ..forward();
  }

  bool get _showsFab => _selectedIndex == 0;

  /// The assistant tab manages its own docked composer, so it must not receive
  /// extra bottom padding.
  bool get _isChatTab => _selectedIndex == 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // The Scaffold already reserves room for the bottom bar; the only thing
    // that overlaps content is the docked FAB.
    final contentBottom = _isChatTab
        ? 0.0
        : (_showsFab
              ? AppTokens.fabClearance + AppTokens.gapLg
              : AppTokens.gapLg);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(colorScheme),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: NavShellInsets(
            contentBottom: contentBottom,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _pageFade,
                curve: Curves.easeOut,
              ),
              child: IndexedStack(
                index: _selectedIndex,
                children: const [
                  HomeScreen(),
                  AnalyticsScreen(),
                  AiFinancialAssistantScreen(),
                  AccountScreen(),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: AnimatedScale(
          scale: _showsFab ? 1 : 0,
          duration: AppTokens.motionFast,
          curve: Curves.easeOutBack,
          child: FloatingActionButton(
            onPressed: _showsFab ? _openAddTransaction : null,
            tooltip: 'Add transaction',
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, size: 30),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _BottomNavBar(
          destinations: _destinations,
          selectedIndex: _selectedIndex,
          onSelected: _select,
        ),
      ),
    );
  }

  void _openAddTransaction() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddTransactionSheet(),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _BottomNavBar extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _BottomNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: colorScheme.appCard,
      elevation: 0,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.appBorder)),
        ),
        child: Row(
          children: [
            for (var index = 0; index < destinations.length; index++) ...[
              // Reserve the middle slot for the docked FAB.
              if (index == destinations.length ~/ 2)
                const SizedBox(width: 64),
              Expanded(
                child: _NavItem(
                  destination: destinations[index],
                  isSelected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        containedInkWell: false,
        child: SizedBox(
          height: AppTokens.navBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppTokens.motionFast,
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.gapMd,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Icon(
                  isSelected ? destination.selectedIcon : destination.icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  height: 1,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
