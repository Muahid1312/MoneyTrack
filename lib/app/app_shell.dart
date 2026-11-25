import '../core/utils/app_language.dart';
import '../data/storage/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';

import '../core/utils/money.dart';
import '../core/widgets/feedback.dart';
import '../features/explore/explore_screen.dart';
import '../features/budgets/application/budget_providers.dart';
import '../features/budgets/domain/budget_calculator.dart';
import '../features/dashboard/presentation/home_screen.dart';
import '../features/budgets/presentation/budgets_overview_screen.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/wallets/presentation/wallets_screen.dart';

/// Currently selected bottom-navigation tab.
final shellTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Bottom padding screens need so content clears the floating nav bar.
  static double contentBottomInset(BuildContext context) => 24;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _screens = [
    HomeScreen(),
    BudgetsOverviewScreen(),
    WalletsScreen(),
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
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    _visited.add(index);

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
        body: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _visited.contains(i)
                  ? HeroMode(
                      enabled: index == i,
                      child: TickerMode(
                        enabled: index == i,
                        child: _screens[i],
                      ),
                    )
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          height: 60,
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(shellTabProvider.notifier).state = i,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: context.tr('Home', 'خانه'),
            ),
            NavigationDestination(
              icon: Icon(Icons.donut_large_outlined),
              selectedIcon: Icon(Icons.pie_chart),
              label: context.tr('Budgets', 'بودجه‌ها'),
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: context.tr('Accounts', 'حساب‌ها'),
            ),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: context.tr('More', 'بیشتر')),
          ],
        ),
      ),
    );
  }
}
