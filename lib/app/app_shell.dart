import '../data/storage/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/money.dart';
import '../core/widgets/feedback.dart';
import '../core/widgets/pressable.dart';
import '../features/budgets/application/budget_providers.dart';
import '../features/budgets/domain/budget_calculator.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/transactions/presentation/transaction_actions.dart';


/// Currently selected bottom-navigation tab.
final shellTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Bottom padding screens need so content clears the floating nav bar.
  static double contentBottomInset(BuildContext context) =>
      _NavBar.height + 28 + MediaQuery.paddingOf(context).bottom;

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
    ProjectsScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message=RuntimeNotice.message;RuntimeNotice.message=null;
      if(mounted && message!=null)showAppSnack(context,message:message);
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
        if (MediaQuery.disableAnimationsOf(context)) { _fade.value = 1; }
        else { _fade.forward(from: 0); }
      }
    });

    // In-app budget warnings when spending crosses a threshold.
    ref.listen<BudgetStatus>(budgetStatusProvider, (prev, next) {
      if (prev == null) return;
      if (next.level.index <= prev.level.index) return;
      final currency = ref.read(currencyProvider);
      if (next.level == BudgetLevel.exceeded) {
        HapticFeedback.heavyImpact();
        showAppSnack(context,
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.roseSoft,
            duration: const Duration(seconds: 5),
            message:
                'Monthly budget exceeded by ${Money.format(next.overspentMinor, currency)}.');
      } else if (next.level == BudgetLevel.approaching) {
        showAppSnack(context,
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.amber,
            duration: const Duration(seconds: 5),
            message:
                "You've used ${(next.ratio * 100).floor()}% of this month's budget.");
      }
    });

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(shellTabProvider.notifier).state = 0;
      },
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: FadeTransition(
          opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
                .animate(CurvedAnimation(parent: _fade, curve: AppCurves.standard)),
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  if (_visited.contains(i)) TickerMode(enabled: i == index,
                    child: i == 1 || i == 2
                      ? Padding(padding: EdgeInsets.only(bottom: AppShell.contentBottomInset(context)), child: _screens[i])
                      : _screens[i])
                  else const SizedBox.shrink(),
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
          onAdd: () => TransactionActions.openEditor(context, ref),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect, required this.onAdd});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  static const height = 70.0;

  static const _items = [
    _NavItem('Home', Icons.home_outlined, Icons.home_rounded),
    _NavItem('Projects', Icons.folder_outlined, Icons.folder_rounded),
    _NavItem('Reports', Icons.insights_outlined, Icons.insights_rounded),
    _NavItem('More', Icons.grid_view_outlined, Icons.grid_view_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom : 14),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: p.navBar,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: p.border.withValues(alpha: context.isDark ? 1 : 0.7)),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: context.isDark ? 0.4 : 0.10),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < 2; i++) _tab(context, i),
            SizedBox(width: 70, child: Center(child: _AddButton(onTap: onAdd))),
            for (var i = 2; i < 4; i++) _tab(context, i),
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final selected = i == index;
    final item = _items[i];
    final activeColor = context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        excludeSemantics: true,
        onTap: () => onSelect(i),
        child: Pressable(
          onTap: () => onSelect(i),
          scale: 0.9,
          child: SizedBox(
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: AppDurations.medium,
                  curve: AppCurves.standard,
                  width: selected ? 46 : 36,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.emerald.withValues(alpha: context.isDark ? 0.16 : 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: AnimatedSwitcher(
                    duration: AppDurations.fast,
                    child: Icon(
                      selected ? item.activeIcon : item.icon,
                      key: ValueKey(selected),
                      size: 22,
                      color: selected ? activeColor : p.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: AppDurations.medium,
                  style: t.labelSmall!.copyWith(
                    color: selected ? p.textPrimary : p.textTertiary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(item.label, maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add transaction',
      child: Pressable(
        onTap: onTap,
        haptic: true,
        scale: 0.88,
        semanticLabel: 'Add transaction',
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.emeraldDeep, Color(0xFF065F46)],
            ),
            boxShadow: AppShadows.glow(AppColors.emerald, strength: 0.45),
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
