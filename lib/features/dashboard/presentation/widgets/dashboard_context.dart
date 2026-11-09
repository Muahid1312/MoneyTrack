import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/utils/money.dart';
import '../../../planning/application/planning_providers.dart';
import '../../../planning/presentation/planning_screens.dart';
import '../../../projects/application/project_providers.dart';
import '../../../projects/presentation/projects_screen.dart';
import '../../../settings/application/settings_controller.dart';
import '../../../wallets/application/wallet_providers.dart';
import '../../../wallets/presentation/wallets_screen.dart';

/// Current positions are deliberately separate from period income/expenses.
class DashboardContext extends ConsumerWidget {
  const DashboardContext({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final hidden = ref.watch(settingsProvider).hideBalance;
    final wallets = ref.watch(walletsProvider);
    final projects = ref.watch(projectsProvider);
    final planning = ref.watch(planningProvider);
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: 'Your wallets', subtitle: 'Current positions · ${currency.code}',
        actionLabel: 'Manage', onAction: () => open(const WalletsScreen())),
      const SizedBox(height: 12),
      wallets.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => _Retry(label: 'Wallets unavailable', onTap: () => ref.invalidate(walletsProvider)),
        data: (data) {
          final selected = data?.wallets.where((w) => w.currency == currency).toList() ?? [];
          final reserved = selected.fold<int>(0, (s, w) => s + (data!.reserved[w.id] ?? 0));
          final available = selected.fold<int>(0, (s, w) => s + data!.available(w.id!));
          String money(int amount) => hidden ? '••••' : Money.format(amount, currency);
          return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (selected.isEmpty) const Text('No wallets in this currency. Manage wallets to add one.'),
            for (final wallet in selected.take(3)) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Wrap(
              alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 4, children: [
                Text(wallet.name), Text(money(data!.balances[wallet.id] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
              ])),
            if (selected.length > 3) Text('+${selected.length - 3} more in Manage'),
            if (selected.isNotEmpty) ...[
              const Divider(height: 24), Text('${money(available)} available', style: Theme.of(context).textTheme.titleMedium),
              Text('${money(reserved)} reserved in savings · included in cash', style: Theme.of(context).textTheme.bodySmall),
            ],
          ]));
        }),
      const SizedBox(height: 24),
      SectionHeader(title: 'Projects at a glance', actionLabel: 'View all', onAction: () => open(const ProjectsScreen())),
      const SizedBox(height: 12),
      projects.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => _Retry(label: 'Projects unavailable', onTap: () => ref.invalidate(projectsProvider)),
        data: (data) {
          final active = data?.projects.where((p) => !p.isArchived).toList() ?? [];
          return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(active.isEmpty ? 'Plan your next personal or business project.' : '${active.length} unarchived projects', style: Theme.of(context).textTheme.titleSmall),
            for (final project in active.take(2)) ListTile(contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined), title: Text(project.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${project.type.label} · ${project.status.label} · ${project.currency.code}'),
              trailing: const Icon(Icons.chevron_right), onTap: () => open(ProjectDetailScreen(projectId: project.id!))),
          ]));
        }),
      const SizedBox(height: 24),
      SectionHeader(title: 'Upcoming & to review', actionLabel: 'Planning', onAction: () => open(const PlanningScreen())),
      const SizedBox(height: 12),
      planning.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => _Retry(label: 'Planning unavailable', onTap: () => ref.invalidate(planningProvider)),
        data: (data) {
          final pending = data?.occurrences.where((o) => o.status == 'pending').length ?? 0;
          final rules = data?.rules.where((r) => r.state == 'active' && !r.finished).toList() ?? [];
          rules.sort((a, b) => a.nextDate.compareTo(b.nextDate));
          return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(pending == 0 ? 'No entries awaiting confirmation' : '$pending entries awaiting confirmation', style: Theme.of(context).textTheme.titleSmall),
            for (final rule in rules.take(2)) ListTile(contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat_outlined), title: Text(rule.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('Next ${rule.nextDate} · ${rule.currency.code}${hidden ? '' : ' · ${Money.format(rule.amountMinor, rule.currency)}'}'),
              onTap: () => open(const RecurringScreen())),
            const SizedBox(height: 4), Text('Ledger reminders only. MoneyTrack does not make bank payments.', style: Theme.of(context).textTheme.bodySmall),
          ]));
        }),
    ]);
  }
}
class _Retry extends StatelessWidget {
  const _Retry({required this.label, required this.onTap});
  final String label; final VoidCallback onTap;
  @override Widget build(BuildContext context) => AppCard(child: Column(children: [
    Icon(Icons.error_outline_rounded, color: context.palette.textSecondary), Text(label),
    TextButton(onPressed: onTap, child: const Text('Retry')),
  ]));
}
