import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/planning.dart';
import '../application/planning_providers.dart';
import 'planning_screens.dart';

typedef DueItem = ({String date, String title, String detail, Widget page});

List<DueItem> dueItems(PlanningSnapshot? data) {
  if (data == null) return [];
  final items = <DueItem>[
    for (final d in data.debts.where(
      (d) => d.remainingMinor > 0 && d.dueDate != null,
    ))
      (
        date: d.dueDate!,
        title: d.contact,
        detail:
            '${d.borrowed ? "You owe" : "Owed to you"} · ${Money.format(d.remainingMinor, d.currency)} ${d.currency.code}',
        page: DebtDetailScreen(id: d.id),
      ),
    for (final o in data.occurrences.where((o) => o.status == 'pending'))
      (
        date: o.dueDate,
        title:
            data.rules.where((r) => r.id == o.ruleId).firstOrNull?.name ??
            'Scheduled entry',
        detail: 'Awaiting confirmation',
        page: const RecurringScreen(),
      ),
    for (final r in data.rules.where((r) => r.state == 'active' && !r.finished))
      (
        date: r.nextDate,
        title: r.name,
        detail:
            '${r.automatic ? "Automatic ledger entry" : "Review when due"} · ${Money.format(r.amountMinor, r.currency)} ${r.currency.code}',
        page: const RecurringScreen(),
      ),
  ];
  return items..sort((a, b) => a.date.compareTo(b.date));
}

class DueTile extends StatelessWidget {
  const DueTile(this.item, {super.key});
  final DueItem item;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.event_outlined),
    title: Text(item.title),
    subtitle: Text('${item.date} · ${item.detail}'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => item.page),
    ),
  );
}

class UpcomingScreen extends ConsumerWidget {
  const UpcomingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Upcoming payments')),
    body: ref
        .watch(planningProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => planningError(ref),
          data: (data) {
            final items = dueItems(data);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (items.isEmpty)
                  const ListTile(
                    title: Text('Nothing due'),
                    subtitle: Text(
                      'Dated debts and recurring schedules will appear here.',
                    ),
                  ),
                for (final item in items) DueTile(item),
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const RecurringScreen(),
                    ),
                  ),
                  child: const Text('Manage recurring entries'),
                ),
              ],
            );
          },
        ),
  );
}
