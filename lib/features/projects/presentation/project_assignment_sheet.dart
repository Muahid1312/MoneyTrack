import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/project.dart';
import '../../wallets/domain/exchange_rate.dart';
import '../application/project_providers.dart';

class ProjectAssignment {
  const ProjectAssignment({this.projectId, this.categoryId, this.rate,
    this.clientReceipt = false, this.paymentReference});
  final int? projectId, categoryId;
  final String? rate, paymentReference;
  final bool clientReceipt;
}

class ProjectAssignmentSheet extends ConsumerStatefulWidget {
  const ProjectAssignmentSheet({super.key, required this.initial,
    required this.sourceCurrency, required this.amountMinor, required this.isIncome});
  final ProjectAssignment initial;
  final AppCurrency sourceCurrency;
  final int amountMinor;
  final bool isIncome;
  @override
  ConsumerState<ProjectAssignmentSheet> createState() => _AssignmentState();
}

class _AssignmentState extends ConsumerState<ProjectAssignmentSheet> {
  late int? _projectId, _categoryId;
  late bool _clientReceipt;
  late final TextEditingController _rate, _reference;
  String? _error;
  @override
  void initState() {
    super.initState();
    _projectId = widget.initial.projectId;
    _categoryId = widget.initial.categoryId;
    _clientReceipt = widget.initial.clientReceipt && widget.isIncome;
    _rate = TextEditingController(text: widget.initial.rate ?? '');
    _reference = TextEditingController(text: widget.initial.paymentReference ?? '');
  }
  @override
  void dispose() { _rate.dispose(); _reference.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(projectsProvider);
    return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: data.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (_, _) => TextButton(onPressed: () => ref.invalidate(projectsProvider), child: const Text('Retry loading projects')),
        data: (snapshot) {
          if (snapshot == null) return const Text('Project storage unavailable');
          final projects = snapshot.projects.where((p) => !p.isArchived || p.id == _projectId).toList();
          final project = projects.where((p) => p.id == _projectId).firstOrNull;
          final categories = snapshot.categories.where((c) => c.projectId == _projectId).toList();
          final same = project?.currency == widget.sourceCurrency;
          String? preview;
          if (project != null && widget.amountMinor > 0) {
            try {
              preview = Money.format(ExchangeRate.parse(same ? '1' : _rate.text)
                .convert(widget.amountMinor, widget.sourceCurrency, project.currency), project.currency);
            } catch (_) { /* Rate validation occurs before applying. */ }
          }
          return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Project assignment', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('This labels the same wallet transaction. It does not create another income or expense.'),
              const SizedBox(height: 20),
              DropdownButtonFormField<int>(key: ValueKey(_projectId), initialValue: project?.id ?? 0,
                isExpanded: true, decoration: const InputDecoration(labelText: 'Project'),
                items: [const DropdownMenuItem(value: 0, child: Text('Unassigned personal transaction')),
                  for (final p in projects) DropdownMenuItem(value: p.id,
                    child: Text('${p.name} · ${p.currency.code}${p.isArchived ? ' · Archived' : ''}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() {
                  _projectId = v == 0 ? null : v; _categoryId = null;
                  _rate.clear(); _reference.clear(); _clientReceipt = false; _error = null;
                })),
              if (project != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(isExpanded: true, key: ValueKey('category-$_projectId-$_categoryId'),
                  initialValue: _categoryId ?? 0, decoration: const InputDecoration(labelText: 'Project category'),
                  items: [const DropdownMenuItem(value: 0, child: Text('Use transaction category')),
                    for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _categoryId = v == 0 ? null : v)),
                if (!same) ...[
                  const SizedBox(height: 16),
                  TextField(controller: _rate, onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Manual rate to ${project.currency.code}',
                      helperText: '1 ${widget.sourceCurrency.code} = rate ${project.currency.code}. This historical rate is saved.', helperMaxLines: 2)),
                ],
                const SizedBox(height: 12),
                Text('Original: ${Money.format(widget.amountMinor, widget.sourceCurrency)} (${widget.sourceCurrency.code})'),
                if (preview != null) Text('Project reporting amount: $preview (${project.currency.code})'),
                if (widget.isIncome && project.type == ProjectType.business) ...[
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Client receipt'),
                    subtitle: const Text('Reduces outstanding contract payments'), value: _clientReceipt,
                    onChanged: (v) => setState(() => _clientReceipt = v)),
                  if (_clientReceipt) TextField(controller: _reference, maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Unique payment reference',
                      helperText: 'Use the bank/payment receipt ID. Reusing it in this wallet or project is blocked.', helperMaxLines: 2)),
                ],
                if (project.isArchived) const Text('Restore this project before recording changes, or select another project.'),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 24),
              FilledButton(onPressed: () {
                if (_projectId == null) { Navigator.pop(context, const ProjectAssignment()); return; }
                if (project == null || project.isArchived) { setState(() => _error = 'Choose an unarchived project'); return; }
                String rate;
                try { rate = ExchangeRate.parse(same ? '1' : _rate.text).text; }
                on FormatException catch (e) { setState(() => _error = e.message); return; }
                final client = widget.isIncome && project.type == ProjectType.business && _clientReceipt;
                if (client && _reference.text.trim().isEmpty) { setState(() => _error = 'Enter the payment reference'); return; }
                Navigator.pop(context, ProjectAssignment(projectId: _projectId, categoryId: _categoryId,
                  rate: rate, clientReceipt: client, paymentReference: client ? _reference.text.trim() : null));
              }, child: const Text('Apply assignment')),
            ]));
        },
      ),
    ));
  }
}
