import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money.dart';
import '../../../data/models/project.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../application/project_providers.dart';
import '../domain/project_finance.dart';
import 'project_editor_screen.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});
  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsState();
}
class _ProjectsState extends ConsumerState<ProjectsScreen> {
  String _query = '', _type = 'all', _status = 'current';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Projects')),
    floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.add),
      label: const Text('New project'), onPressed: () => Navigator.push(context,
        MaterialPageRoute<void>(builder: (_) => const ProjectEditorScreen()))),
    body: ref.watch(projectsProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ProjectError(onRetry: () => ref.invalidate(projectsProvider)),
      data: (data) {
        if (data == null) return const Center(child: Text('Project storage unavailable'));
        final projects = data.projects.where((p) =>
          (_type == 'all' || p.type.name == _type) &&
          (_status == 'all' || (_status == 'current' ? !p.isArchived : p.status.name == _status)) &&
          '${p.name} ${p.description} ${p.clientName}'.toLowerCase().contains(_query.trim().toLowerCase())).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
          TextField(decoration: const InputDecoration(labelText: 'Search projects or clients', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(isExpanded: true, initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [const DropdownMenuItem(value: 'all', child: Text('All types')),
                for (final t in ProjectType.values) DropdownMenuItem(value: t.name, child: Text(t.label))],
              onChanged: (v) => setState(() => _type = v!))),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonFormField<String>(isExpanded: true, initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [const DropdownMenuItem(value: 'current', child: Text('Unarchived')),
                const DropdownMenuItem(value: 'all', child: Text('All statuses')),
                for (final s in ProjectStatus.values) DropdownMenuItem(value: s.name, child: Text(s.label))],
              onChanged: (v) => setState(() => _status = v!))),
          ]),
          const SizedBox(height: 20),
          if (projects.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 40),
            child: Text('No matching projects. Create a personal or business project to get started.', textAlign: TextAlign.center)),
          for (final project in projects) _ProjectCard(project: project,
            summary: ProjectFinance.calculate(project, data.transactions, data.allocations, data.categories)),
        ]);
      },
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.summary});
  final Project project;
  final ProjectSummary summary;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 12),
    child: InkWell(borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProjectDetailScreen(projectId: project.id!))),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(projectIcons[project.icon] ?? Icons.folder_outlined, color: Color(project.color)),
          const SizedBox(width: 12), Expanded(child: Text(project.name, style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.chevron_right)]),
        const SizedBox(height: 8),
        Text('${project.type.label} · ${project.status.label} · ${project.currency.code}'),
        if (project.clientName.isNotEmpty) Text(project.clientName),
        const SizedBox(height: 16),
        Text('Spent ${Money.format(summary.expenses, project.currency)}'),
        Text(project.budgetMinor == null ? 'No planned budget' : 'Budget ${Money.format(project.budgetMinor!, project.currency)}'),
        const SizedBox(height: 8),
        _BudgetProgress(summary: summary),
      ])),
    ));
}

class _BudgetProgress extends StatelessWidget {
  const _BudgetProgress({required this.summary});
  final ProjectSummary summary;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (summary.usage != null) ...[
      LinearProgressIndicator(value: summary.usage!.clamp(0.0, 1.0).toDouble(),
        color: summary.overspent ? Theme.of(context).colorScheme.error : null),
      const SizedBox(height: 6), Text('${(summary.usage! * 100).toStringAsFixed(1)}% of planned budget'),
    ] else Text(summary.budgetMinor == null ? 'Budget not set' : 'Zero budget'),
    if (summary.overspent) Text('Over budget', style: TextStyle(color: Theme.of(context).colorScheme.error)),
  ]);
}

class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final int projectId;

  Future<void> _archive(BuildContext context, WidgetRef ref, Project project) async {
    try {
      await ref.read(projectRepositoryProvider)!.setArchived(projectId, !project.isArchived);
      ref.invalidate(projectsProvider);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not change project status')));
    }
  }
  Future<void> _allocation(BuildContext context, WidgetRef ref, Project project) async {
    final amount = TextEditingController(), note = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Allocate funds'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('A planning earmark in project currency. This does not move wallet money or create income.'),
        const SizedBox(height: 16),
        TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Allocation (${project.currency.code})'),
          validator: (v) => (Money.parseMinor(v ?? '', project.currency) ?? 0) > 0 ? null : 'Enter a positive amount'),
        TextField(controller: note, maxLength: 240, decoration: const InputDecoration(labelText: 'Note (optional)')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Allocate'))]));
    if (result == true) {
      try {
        await ref.read(projectRepositoryProvider)!.allocate(projectId, Money.parseMinor(amount.text, project.currency)!, note.text);
        ref.invalidate(projectsProvider);
      } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not allocate funds')));
      }
    }
    amount.dispose(); note.dispose();
  }
  Future<void> _category(BuildContext context, WidgetRef ref) async {
    final text = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New project category'), content: TextField(controller: text,
        maxLength: 60, decoration: const InputDecoration(labelText: 'Category name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (text.text.trim().isNotEmpty) Navigator.pop(ctx, true); }, child: const Text('Create'))]));
    if (result == true) {
      try {
        await ref.read(projectRepositoryProvider)!.addCategory(projectId, text.text);
        ref.invalidate(projectsProvider);
      } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create category. Check for a duplicate name.')));
      }
    }
    text.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(projectsProvider).when(
    loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
    error: (_, _) => Scaffold(appBar: AppBar(), body: _ProjectError(onRetry: () => ref.invalidate(projectsProvider))),
    data: (data) {
      final project = data?.projects.where((p) => p.id == projectId).firstOrNull;
      if (project == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Project not found')));
      final summary = ProjectFinance.calculate(project, data!.transactions, data.allocations, data.categories);
      final entries = data.transactions.where((t) => t.projectId == projectId).toList();
      final allocations = data.allocations.where((a) => a.projectId == projectId);
      String money(int value) => Money.format(value, project.currency);
      return Scaffold(
        appBar: AppBar(title: Text(project.name), actions: [
          IconButton(tooltip: 'Edit project', icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProjectEditorScreen(project: project)))),
          PopupMenuButton<String>(onSelected: (_) => _archive(context, ref, project), itemBuilder: (_) => [
            PopupMenuItem(value: 'archive', child: Text(project.isArchived ? 'Restore project' : 'Archive project'))]),
        ]),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('${project.type.label} · ${project.status.label} · ${project.currency.code}', style: Theme.of(context).textTheme.titleMedium),
          if (project.clientName.isNotEmpty) Text('Client: ${project.clientName}'),
          if (project.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(project.description)),
          Text('Starts ${DateFormat.yMMMd().format(project.startDate)}${project.deadline == null ? '' : ' · Due ${DateFormat.yMMMd().format(project.deadline!)}'}'),
          const SizedBox(height: 24),
          Text('Cash-based financial summary', style: Theme.of(context).textTheme.titleLarge),
          const Text('Original wallet amounts are retained. Totals below use each entry’s recorded conversion to project currency.'),
          const SizedBox(height: 12),
          _Metric(label: 'Cash receipts', value: money(summary.receipts)),
          _Metric(label: 'Cash payments / expenses', value: money(summary.expenses)),
          _Metric(label: 'Cash surplus', value: money(summary.cashSurplus)),
          const Text('Cash surplus is receipts minus payments, not accounting profit.'),
          const Divider(height: 32),
          _Metric(label: 'Planned budget', value: project.budgetMinor == null ? 'Not set' : money(project.budgetMinor!)),
          _Metric(label: 'Remaining budget', value: summary.remainingBudget == null ? 'Not set' : money(summary.remainingBudget!)),
          _BudgetProgress(summary: summary),
          const SizedBox(height: 12),
          if (project.type == ProjectType.business) ...[
            _Metric(label: 'Contract obligation', value: project.contractMinor == null ? 'Not recorded' : money(project.contractMinor!)),
            _Metric(label: 'Client payments received', value: money(summary.clientReceipts)),
            _Metric(label: 'Outstanding client payments', value: summary.outstanding == null ? 'Contract not recorded' : money(summary.outstanding!)),
            if (summary.overpayment > 0) _Metric(label: 'Receipts above contract', value: money(summary.overpayment)),
            const Text('Only entries marked as client receipts reduce the contract obligation.'),
          ] else ...[
            _Metric(label: 'Money allocated (planning)', value: money(summary.allocated)),
            _Metric(label: 'Available allocated funds', value: money(summary.availableAllocation)),
            const Text('Allocation minus spending. Allocations are not wallet transfers or income.'),
            if (summary.availableAllocation < 0) Text('Spending exceeds allocations.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          if (!project.isArchived) Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(icon: const Icon(Icons.remove), label: const Text('Add expense'),
              onPressed: () => TransactionActions.openEditor(context, ref, initialProjectId: projectId, initialType: TransactionType.expense)),
            OutlinedButton.icon(icon: const Icon(Icons.add), label: const Text('Add income'),
              onPressed: () => TransactionActions.openEditor(context, ref, initialProjectId: projectId, initialType: TransactionType.income)),
            if (project.type == ProjectType.business) OutlinedButton(onPressed: () => TransactionActions.openEditor(context, ref,
              initialProjectId: projectId, initialType: TransactionType.income, initialClientReceipt: true), child: const Text('Record client receipt')),
            if (project.type == ProjectType.personal) OutlinedButton(onPressed: () => _allocation(context, ref, project), child: const Text('Allocate funds')),
          ]),
          if (project.isArchived) const Text('Archived · history is retained. Restore the project to record new activity.'),
          const SizedBox(height: 24),
          Row(children: [Expanded(child: Text('Recent transactions', style: Theme.of(context).textTheme.titleLarge)),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProjectTransactionsScreen(projectId: projectId))), child: const Text('View all'))]),
          if (entries.isEmpty) const Text('No project transactions yet. Add an entry or assign an existing transaction.'),
          for (final t in entries.take(5)) _ProjectTransactionTile(transaction: t),
          const SizedBox(height: 12),
          ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Spending by category'), children: [
            if (summary.categoryExpenses.isEmpty) const ListTile(title: Text('No expenses recorded')),
            for (final c in summary.categoryExpenses.entries) _Metric(label: c.key, value: money(c.value)),
          ]),
          ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Monthly cash flow'), children: [
            if (summary.monthly.isEmpty) const ListTile(title: Text('No cash flow yet')),
            for (final month in summary.monthly.keys.toList()..sort((a,b) => b.compareTo(a))) ListTile(contentPadding: EdgeInsets.zero,
              title: Text(DateFormat.yMMM().format(month)),
              subtitle: Text('Receipts ${money(summary.monthly[month]!.receipts)}\nPayments ${money(summary.monthly[month]!.payments)}'),
              trailing: Text(money(summary.monthly[month]!.surplus))),
          ]),
          if (project.type == ProjectType.personal) ExpansionTile(tilePadding: EdgeInsets.zero,
            title: const Text('Allocation history'), children: [
              if (allocations.isEmpty) const ListTile(title: Text('No allocations recorded')),
              for (final a in allocations) ListTile(contentPadding: EdgeInsets.zero,
                title: Text(money(a.amountMinor)), subtitle: Text('${DateFormat.yMMMd().format(a.occurredAt)}${a.note.isEmpty ? '' : ' · ${a.note}'}'),
                trailing: project.isArchived ? null : IconButton(tooltip: 'Remove allocation', icon: const Icon(Icons.delete_outline), onPressed: () async {
                  final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Remove allocation?'),
                    content: const Text('This removes the planning earmark. Wallet balances and income remain unchanged.'), actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))]));
                  if (ok != true) return;
                  try { await ref.read(projectRepositoryProvider)!.removeAllocation(a.id); ref.invalidate(projectsProvider); }
                  catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove allocation'))); }
                })),
            ]),
          ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Project categories'), children: [
            Wrap(spacing: 8, children: [for (final c in data.categories.where((c) => c.projectId == projectId)) Chip(label: Text(c.name))]),
            if (!project.isArchived) TextButton.icon(onPressed: () => _category(context, ref), icon: const Icon(Icons.add), label: const Text('Custom category')),
          ]),
        ]),
      );
    },
  );
}

class ProjectTransactionsScreen extends ConsumerWidget {
  const ProjectTransactionsScreen({super.key, required this.projectId});
  final int projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Project transactions')),
    body: ref.watch(projectsProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ProjectError(onRetry: () => ref.invalidate(projectsProvider)),
      data: (data) {
        final entries = data?.transactions.where((t) => t.projectId == projectId).toList() ?? [];
        if (entries.isEmpty) return const Center(child: Text('No project transactions'));
        return ListView(padding: const EdgeInsets.all(20), children: [for (final t in entries) _ProjectTransactionTile(transaction: t)]);
      },
    ),
  );
}

class _ProjectTransactionTile extends ConsumerWidget {
  const _ProjectTransactionTile({required this.transaction});
  final TransactionModel transaction;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    final converted = t.projectCurrency != t.currency;
    return ListTile(contentPadding: EdgeInsets.zero,
      title: Text(t.title),
      subtitle: Text('${DateFormat.yMMMd().format(t.occurredAt)}${t.clientReceipt ? ' · Client receipt ${t.paymentReference}' : ''}'
        '${converted ? '\nProject: ${Money.format(t.projectAmountMinor!, t.projectCurrency!)} (${t.projectCurrency!.code}) · rate ${t.projectRate}' : ''}'),
      trailing: Text('${Money.format(t.signedMinor, t.currency, signed: true)}\n${t.currency.code}', textAlign: TextAlign.end),
      onTap: () => TransactionActions.openEditor(context, ref, existing: t));
  }
}
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(
    crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(label)), const SizedBox(width: 16), Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]));
}
class _ProjectError extends StatelessWidget {
  const _ProjectError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('Could not load projects. Stored records have not been reset.'),
    TextButton(onPressed: onRetry, child: const Text('Retry')),
  ]));
}
