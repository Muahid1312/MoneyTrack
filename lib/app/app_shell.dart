import '../data/storage/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/money.dart';
import '../core/widgets/feedback.dart';
import '../features/explore/explore_screen.dart';
import '../features/budgets/application/budget_providers.dart';
import '../features/budgets/domain/budget_calculator.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/statistics/presentation/statistics_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';
import '../features/transactions/application/transaction_filter.dart';

import '../features/transactions/presentation/transaction_actions.dart';

/// Currently selected bottom-navigation tab.
final shellTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Bottom padding screens need so content clears the floating nav bar.
  static double contentBottomInset(BuildContext context) => 24;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
    value: 1,
  );

  static const _screens = [
    DashboardScreen(),
    TransactionsScreen(),
    StatisticsScreen(),
    ExploreScreen(),
  ];

  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = RuntimeNotice.message;
      RuntimeNotice.message = null;
      if (mounted && message != null) showAppSnack(context, message: message);
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    _visited.add(index);

    ref.listen<int>(shellTabProvider, (prev, next) {
      if (prev != next) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _fade.value = 1;
        } else {
          _fade.forward(from: 0);
        }
      }
    });

    // In-app budget warnings when spending crosses a threshold.
    ref.listen<BudgetStatus>(budgetStatusProvider, (prev, next) {
      if (prev == null) return;
      if (next.level.index <= prev.level.index) return;
      final currency = ref.read(currencyProvider);
      if (next.level == BudgetLevel.exceeded) {
        HapticFeedback.heavyImpact();
        showAppSnack(
          context,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.roseSoft,
          duration: const Duration(seconds: 5),
          message:
              'Monthly budget exceeded by ${Money.format(next.overspentMinor, currency)}.',
        );
      } else if (next.level == BudgetLevel.approaching) {
        showAppSnack(
          context,
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.amber,
          duration: const Duration(seconds: 5),
          message:
              "You've used ${(next.ratio * 100).floor()}% of this month's budget.",
        );
      }
    });

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(shellTabProvider.notifier).state = 0;
      },
      child: Scaffold(
        extendBody: false,
        resizeToAvoidBottomInset: true,
        body: FadeTransition(
          opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: _fade, curve: AppCurves.standard),
                ),
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  if (_visited.contains(i))
                    TickerMode(enabled: i == index, child: _screens[i])
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _NavBar(
          index: index,
          onSelect: (i) {
            if (i == index) return;
            HapticFeedback.selectionClick();
            ref.read(shellTabProvider.notifier).state = i;
          },
          onAdd: () => TransactionActions.openEditor(
            context,
            ref,
            preferredCurrency: index == 1
                ? ref.read(activityCurrencyProvider)
                : null,
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.index,
    required this.onSelect,
    required this.onAdd,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBar(
      labelTextStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelMedium,
      ),
      selectedIndex: index < 2 ? index : index + 1,
      onDestinationSelected: (i) {
        if (i == 2) {
          onAdd();
        } else {
          onSelect(i < 2 ? i : i - 1);
        }
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        const NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Activity',
        ),
        NavigationDestination(
          tooltip: 'Add transaction',
          icon: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Icon(Icons.add, color: scheme.onPrimary),
            ),
          ),
          label: 'Add',
        ),
        const NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'Insights',
        ),
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'Explore',
        ),
      ],
    );
  }
}
