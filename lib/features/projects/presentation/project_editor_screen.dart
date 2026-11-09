import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/project.dart';
import '../application/project_providers.dart';

const projectIcons = <String, IconData>{
  'folder': Icons.folder_outlined, 'house': Icons.home_outlined,
  'work': Icons.work_outline, 'flight': Icons.flight_outlined,
  'school': Icons.school_outlined, 'favorite': Icons.favorite_outline,
};
const projectColors = [0xFF10B981, 0xFF3B82F6, 0xFF8B5CF6, 0xFFF97316, 0xFFEC4899];

class ProjectEditorScreen extends ConsumerStatefulWidget {
  const ProjectEditorScreen({super.key, this.project});
  final Project? project;
  @override
  ConsumerState<ProjectEditorScreen> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends ConsumerState<ProjectEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _description, _client, _budget, _contract;
  late ProjectType _type;
  late ProjectStatus _status;
  late AppCurrency _currency;
  late DateTime _start;
  DateTime? _deadline;
  late int _color;
  late String _icon;
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _client = TextEditingController(text: p?.clientName ?? '');
    _type = p?.type ?? ProjectType.personal;
    _status = p?.status ?? ProjectStatus.planned;
    _currency = p?.currency ?? AppCurrency.usd;
    _budget = TextEditingController(text: p?.budgetMinor == null ? '' : Money.plain(p!.budgetMinor!, _currency));
    _contract = TextEditingController(text: p?.contractMinor == null ? '' : Money.plain(p!.contractMinor!, _currency));
    final now = DateTime.now();
    _start = p?.startDate ?? DateTime(now.year, now.month, now.day);
    _deadline = p?.deadline;
    _color = p?.color ?? projectColors.first;
    _icon = p?.icon ?? 'folder';
  }
  @override
  void dispose() {
    for (final controller in [_name, _description, _client, _budget, _contract]) { controller.dispose(); }
    super.dispose();
  }
  String? _amountValidator(String? text) => (text ?? '').trim().isEmpty ||
      Money.parseMinor(text!, _currency) != null ? null : 'Enter a valid nonnegative amount';
  Future<void> _pickDate(bool deadline) async {
    final now = DateTime.now();
    final first = deadline ? _start : DateTime(1900);
    final last = DateTime(2200);
    final initial = (deadline ? _deadline : _start) ?? (now.isBefore(_start) ? _start : now);
    final date = await showDatePicker(context: context, initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first, lastDate: last, helpText: deadline ? 'Project deadline' : 'Project start date');
    if (date != null && mounted) setState(() {
      if (deadline) { _deadline = date; } else { _start = date; }
    });
  }
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_deadline != null && _deadline!.isBefore(_start)) {
      setState(() => _error = 'Deadline must be on or after the start date'); return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(projectRepositoryProvider);
      if (repo == null) throw StateError('Project storage unavailable');
      final now = DateTime.now();
      await repo.save(Project(id: widget.project?.id, name: _name.text,
        description: _description.text, type: _type, clientName: _client.text,
        currency: _currency, budgetMinor: _budget.text.trim().isEmpty ? null : Money.parseMinor(_budget.text, _currency),
        contractMinor: _type == ProjectType.personal || _contract.text.trim().isEmpty
          ? null : Money.parseMinor(_contract.text, _currency),
        startDate: _start, deadline: _deadline, status: _status,
        color: _color, icon: _icon, createdAt: widget.project?.createdAt ?? now, updatedAt: now));
      ref.invalidate(projectsProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Could not save. A project with client receipts must remain business; a project with allocations must remain personal.';
      });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.project == null ? 'New project' : 'Edit project')),
    body: Form(key: _form, child: ListView(padding: const EdgeInsets.all(24), children: [
      TextFormField(controller: _name, maxLength: 100,
        decoration: const InputDecoration(labelText: 'Project name'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a project name' : null),
      TextFormField(controller: _description, maxLength: 2000, minLines: 2, maxLines: 5,
        decoration: const InputDecoration(labelText: 'Description (optional)')),
      const SizedBox(height: 12),
      DropdownButtonFormField<ProjectType>(isExpanded: true, initialValue: _type,
        decoration: const InputDecoration(labelText: 'Project type'),
        items: [for (final t in ProjectType.values) DropdownMenuItem(value: t, child: Text(t.label))],
        onChanged: _saving ? null : (v) => setState(() => _type = v!)),
      if (_type == ProjectType.business) ...[
        const SizedBox(height: 16),
        TextFormField(controller: _client, maxLength: 100, decoration: const InputDecoration(labelText: 'Client name (optional)')),
      ],
      const SizedBox(height: 16),
      DropdownButtonFormField<AppCurrency>(isExpanded: true, key: ValueKey(_currency), initialValue: _currency,
        decoration: const InputDecoration(labelText: 'Project currency', helperText: 'Fixed after creation to protect historical totals.'),
        items: [for (final c in AppCurrency.values) DropdownMenuItem(value: c, child: Text('${c.code} · ${c.name}'))],
        onChanged: widget.project != null || _saving ? null : (v) => setState(() {
          _currency = v!; _budget.clear(); _contract.clear();
        })),
      const SizedBox(height: 20),
      TextFormField(controller: _budget, validator: _amountValidator,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: 'Planned budget (${_currency.code}, optional)',
          helperText: 'Planning only. Empty means no budget; zero is an explicit zero limit.')),
      if (_type == ProjectType.business) ...[
        const SizedBox(height: 20),
        TextFormField(controller: _contract, validator: _amountValidator,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Contract obligation (${_currency.code}, optional)',
            helperText: 'Agreed total owed by the client. This does not record revenue received.', helperMaxLines: 2)),
      ],
      const SizedBox(height: 20),
      DropdownButtonFormField<ProjectStatus>(isExpanded: true, initialValue: _status,
        decoration: const InputDecoration(labelText: 'Status'),
        items: [for (final s in ProjectStatus.values.where((s) => s != ProjectStatus.archived || widget.project?.isArchived == true))
          DropdownMenuItem(value: s, child: Text(s.label))],
        onChanged: _saving || widget.project?.isArchived == true ? null : (v) => setState(() => _status = v!)),
      const SizedBox(height: 16),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Start date'),
        subtitle: Text(_date(_start)), trailing: const Icon(Icons.calendar_today_outlined),
        onTap: _saving ? null : () => _pickDate(false)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Deadline (optional)'),
        subtitle: Text(_deadline == null ? 'Not set' : _date(_deadline!)),
        trailing: _deadline == null ? const Icon(Icons.event_outlined) : IconButton(
          tooltip: 'Remove deadline', icon: const Icon(Icons.close), onPressed: () => setState(() => _deadline = null)),
        onTap: _saving ? null : () => _pickDate(true)),
      ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Appearance'), children: [
        DropdownButtonFormField<String>(isExpanded: true, initialValue: projectIcons.containsKey(_icon) ? _icon : 'folder',
          decoration: const InputDecoration(labelText: 'Icon'),
          items: [for (final icon in projectIcons.entries) DropdownMenuItem(value: icon.key,
            child: Row(children: [Icon(icon.value), const SizedBox(width: 12), Text(icon.key)]))],
          onChanged: (v) => setState(() => _icon = v!)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, children: [for (final color in projectColors) IconButton(
          tooltip: 'Project color ${projectColors.indexOf(color) + 1}',
          onPressed: () => setState(() => _color = color),
          icon: Icon(_color == color ? Icons.check_circle : Icons.circle, color: Color(color)))]),
      ]),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 24),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save project')),
    ])),
  );
}
String _date(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
