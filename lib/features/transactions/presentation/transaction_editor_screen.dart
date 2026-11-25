import '../../../core/utils/app_language.dart';
import 'widgets/amount_keypad.dart';
import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_typography.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../documents/presentation/attachments_screen.dart';
import '../../planning/presentation/planning_forms.dart';
import '../../planning/application/planning_providers.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/amount_input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/feedback.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/models/wallet.dart';
import '../../../data/repositories/providers.dart';
import '../../projects/application/project_providers.dart';
import '../../projects/presentation/project_assignment_sheet.dart';
import '../../settings/application/settings_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/presentation/wallets_screen.dart';
import '../application/transactions_controller.dart';

enum EditorResult { saved, deleted }

class TransactionEditorScreen extends ConsumerStatefulWidget {
  const TransactionEditorScreen({
    super.key,
    this.existing,
    this.initialDate,
    this.onPosted,
    this.initialType,
    this.preferredCurrency,
    this.initialProjectId,
    this.initialClientReceipt = false,
  });

  final TransactionModel? existing;
  final DateTime? initialDate;
  final void Function(DateTime, AppCurrency)? onPosted;
  final TransactionType? initialType;
  final AppCurrency? preferredCurrency;
  final int? initialProjectId;
  final bool initialClientReceipt;

  static Route<EditorResult> route({
    TransactionModel? existing,
    TransactionType? initialType,
    DateTime? initialDate,
    void Function(DateTime, AppCurrency)? onPosted,
    AppCurrency? preferredCurrency,
    int? initialProjectId,
    bool initialClientReceipt = false,
  }) => MaterialPageRoute<EditorResult>(
    fullscreenDialog: true,
    builder: (_) => TransactionEditorScreen(
      existing: existing,
      initialType: initialType,
      initialDate: initialDate,
      onPosted: onPosted,
      preferredCurrency: preferredCurrency,
      initialProjectId: initialProjectId,
      initialClientReceipt: initialClientReceipt,
    ),
  );

  @override
  ConsumerState<TransactionEditorScreen> createState() =>
      _TransactionEditorScreenState();
}

class _TransactionEditorScreenState
    extends ConsumerState<TransactionEditorScreen> {
  late TransactionType _type;
  late ProjectAssignment _project;
  int _walletId = 1;
  AppCurrency _currency = AppCurrency.usd;
  late AmountInput _amount;
  String? _categoryId;
  late DateTime _date;
  late String _note;
  String? _error;
  late final TextEditingController _amountText;
  late final TextEditingController _noteText;

  bool _saving = false;

  bool _addReceipt = false;
  bool _showAccounts = false;
  int? _savedId;
  Map<String, int> _usage = {};

  void _readUsage() {
    _usage = {};
    for (final tx
        in ref
            .read(allTransactionsProvider)
            .where((tx) => tx.walletId == _walletId && tx.type == _type)) {
      _usage.update(tx.categoryId, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _project = ProjectAssignment(
      projectId: e?.projectId ?? widget.initialProjectId,
      categoryId: e?.projectCategoryId,
      rate: e?.projectRate,
      clientReceipt: e?.clientReceipt ?? widget.initialClientReceipt,
      paymentReference: e?.paymentReference,
    );
    var wallet = ref.read(selectedWalletProvider);
    if (widget.preferredCurrency != null &&
        wallet?.currency != widget.preferredCurrency) {
      wallet =
          ref
              .read(walletsProvider)
              .valueOrNull
              ?.wallets
              .where(
                (w) => !w.archived && w.currency == widget.preferredCurrency,
              )
              .firstOrNull ??
          wallet;
    }
    _walletId = e?.walletId ?? wallet?.id ?? 1;
    _currency = e?.currency ?? wallet?.currency ?? ref.read(currencyProvider);
    final history = ref
        .read(allTransactionsProvider)
        .where((t) => t.walletId == _walletId);
    _type =
        e?.type ??
        widget.initialType ??
        (history.where((t) => t.type.isIncome).length * 2 > history.length
            ? TransactionType.income
            : TransactionType.expense);
    _readUsage();
    _amount = e == null
        ? AmountInput('', _currency)
        : AmountInput.fromMinor(e.amountMinor, _currency);
    _categoryId = e?.categoryId;
    final now = ref.read(clockProvider)();
    final day = widget.initialDate ?? now;
    _date =
        e?.occurredAt ??
        DateTime(
          day.year,
          day.month,
          day.day,
          now.hour,
          now.minute,
          now.second,
        );
    _amountText = TextEditingController(text: _amount.raw);
    _noteText = TextEditingController(text: e?.note ?? '');
    _note = e?.note ?? '';
  }

  @override
  void dispose() {
    _amountText.dispose();
    _noteText.dispose();
    super.dispose();
  }

  void _setType(TransactionType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _showAccounts = false;
      _readUsage();
      if (t.isExpense && _project.clientReceipt) {
        _project = ProjectAssignment(
          projectId: _project.projectId,
          categoryId: _project.categoryId,
          rate: _project.rate,
        );
      }
      if (_categoryId != null && Categories.byId(_categoryId!).type != t) {
        _categoryId = null;
      }
      _error = null;
    });
  }

  String walletLabel(Wallet w) =>
      '${w.name} · ${w.currency.code}${w.archived ? " · Archived" : ""}';

  void selectAccount(Wallet w) {
    setState(() {
      if (w.currency != _currency) {
        _amount = AmountInput('', w.currency);
        _amountText.clear();
        _project = ProjectAssignment(
          projectId: _project.projectId,
          categoryId: _project.categoryId,
          clientReceipt: _project.clientReceipt,
          paymentReference: _project.paymentReference,
        );
      }
      _walletId = w.id!;
      _currency = w.currency;
      _showAccounts = false;
      _readUsage();
    });
  }

  Future<void> _pickDate() async {
    if (widget.existing?.recurringRuleId != null) {
      showAppSnack(
        context,
        message:
            'The scheduled occurrence date stays fixed. Edit the rule for future dates.',
      );
      return;
    }
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(_date.year < 2000 ? _date.year : 2000),
      lastDate: now,
      helpText: 'Transaction date',
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
          _date.second,
        ),
      );
    }
  }

  Future<void> _editProject() async {
    final result = await showModalBottomSheet<ProjectAssignment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProjectAssignmentSheet(
        initial: _project,
        sourceCurrency: _currency,
        amountMinor: _amount.minor,
        isIncome: _type.isIncome,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _project = result;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final repo = ref.read(walletRepositoryProvider);
    if (repo != null) {
      final wallet = ref
          .read(walletsProvider)
          .valueOrNull
          ?.wallets
          .where((w) => w.id == _walletId)
          .firstOrNull;
      if (wallet == null || wallet.archived || wallet.currency != _currency) {
        setState(() => _error = 'Choose an active wallet before saving');
        return;
      }
    }
    final minor = _amount.minor;
    if (minor <= 0) {
      setState(() {
        _error = 'Enter an amount greater than zero';
      });
      HapticFeedback.heavyImpact();
      return;
    }
    if (_categoryId == null && _project.categoryId != null) {
      _categoryId = _type.isIncome ? 'business' : 'other';
    }
    if (_categoryId == null) {
      setState(() {
        _error = 'Choose a category';
      });
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final now = ref.read(clockProvider)();
    final controller = ref.read(transactionsProvider.notifier);
    try {
      if (_isEdit) {
        await controller.edit(
          widget.existing!.copyWith(
            walletId: _walletId,
            currency: _currency,
            projectId: () => _project.projectId,
            projectCategoryId: () => _project.categoryId,
            projectRate: () => _project.rate,
            clientReceipt: _type.isIncome && _project.clientReceipt,
            paymentReference: () => _project.paymentReference,
            type: _type,
            amountMinor: minor,
            categoryId: _categoryId,
            note: _note,
            occurredAt: _date,
            updatedAt: now,
          ),
        );
      } else {
        final saved = await controller.add(
          TransactionModel(
            walletId: _walletId,
            currency: _currency,
            projectId: _project.projectId,
            projectCategoryId: _project.categoryId,
            projectRate: _project.rate,
            clientReceipt: _type.isIncome && _project.clientReceipt,
            paymentReference: _project.paymentReference,
            type: _type,
            amountMinor: minor,
            categoryId: _categoryId!,
            note: _note,
            occurredAt: _date,
            createdAt: now,
            updatedAt: now,
          ),
        );
        _savedId = saved.id;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is FormatException
            ? e.message
            : e is ArgumentError
            ? '${e.message}'
            : e is DatabaseException &&
                  e.toString().toLowerCase().contains('reserved')
            ? 'This would consume reserved savings. Withdraw a savings reservation or choose another wallet.'
            : e is DatabaseException && e.isUniqueConstraintError()
            ? 'That payment reference is already recorded for this wallet or project. Edit the existing receipt instead.'
            : 'Could not save. Check the wallet/project status and try again.';
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (!_isEdit && _savedId != null) {
      widget.onPosted?.call(_date, _currency);
      selectWallet(ref, _walletId);
      if (_addReceipt) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => AttachmentsScreen(transactionId: _savedId!),
          ),
        );
        if (!mounted) return;
      }
    }
    // ignore: deprecated_member_use
    SemanticsService.announce(
      _isEdit ? 'Transaction updated' : 'Transaction saved',
      TextDirection.ltr,
    );
    showAppSnack(
      context,
      message: _isEdit ? 'Changes saved' : '${_type.label} saved',
    );
    if (mounted) Navigator.of(context).pop(EditorResult.saved);
  }

  Future<void> _delete() async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete transaction?',
      message:
          'This transaction will be permanently removed from your history.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop(EditorResult.deleted);
  }

  List<TransactionCategory> get orderedCategories {
    final cats = [...Categories.forType(_type)];
    final rank = {for (var i = 0; i < cats.length; i++) cats[i].id: i};
    cats.sort((a, b) {
      final delta = (_usage[b.id] ?? 0).compareTo(_usage[a.id] ?? 0);
      return delta != 0 ? delta : rank[a.id]!.compareTo(rank[b.id]!);
    });
    return cats;
  }

  Future<void> _chooseCategory() async {
    final cats = orderedCategories;
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => ListView(
        children: [
          for (final c in cats)
            ListTile(
              leading: Icon(c.icon, color: c.color),
              title: Text(c.name),
              selected: c.id == _categoryId,
              onTap: () => Navigator.pop(sheet, c.id),
            ),
        ],
      ),
    );
    if (mounted && picked != null) {
      setState(() {
        _categoryId = picked;
        _error = null;
      });
    }
  }

  Future<void> _frequent() async {
    final history = ref
        .read(allTransactionsProvider)
        .where(
          (t) =>
              t.walletId == _walletId &&
              t.currency == _currency &&
              t.type == _type &&
              t.projectId == null &&
              t.recurringRuleId == null,
        );
    final templates =
        <
          ({String category, int amount, String note}),
          ({TransactionModel entry, int count})
        >{};
    for (final t in history) {
      final key = (category: t.categoryId, amount: t.amountMinor, note: t.note);
      templates.update(
        key,
        (old) => (entry: old.entry, count: old.count + 1),
        ifAbsent: () => (entry: t, count: 1),
      );
    }
    final ranked = templates.values.toList()
      ..sort((a, b) {
        final n = b.count.compareTo(a.count);
        return n != 0 ? n : b.entry.occurredAt.compareTo(a.entry.occurredAt);
      });
    final t = await showModalBottomSheet<TransactionModel>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Reuse an entry'),
            subtitle: Text(
              'Fill this draft from a previous payment in this account. Review it before saving.',
            ),
          ),
          if (ranked.isEmpty)
            const ListTile(
              title: Text('No previous entries for this account and type.'),
            ),
          for (final item in ranked.take(12))
            ListTile(
              title: Text(item.entry.title),
              subtitle: Text(item.entry.category.name),
              trailing: Text(Money.format(item.entry.amountMinor, _currency)),
              onTap: () => Navigator.pop(sheet, item.entry),
            ),
        ],
      ),
    );
    if (t != null && mounted) {
      setState(() {
        _categoryId = t.categoryId;
        _note = t.note;
        _noteText.text = _note;
        _amount = AmountInput.fromMinor(t.amountMinor, _currency);
        _amountText.text = _amount.raw;
        _error = null;
      });
    }
  }

  Future<void> _schedule() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecurringForm(
          draft: (
            walletId: _walletId,
            type: _type,
            category: _categoryId,
            amount: _amount.raw,
            name: _note,
            date: _date,
            projectId: _project.projectId,
            rate: _project.rate,
          ),
        ),
      ),
    );
    if (result == true && mounted) {
      showAppSnack(context, message: 'Recurring rule saved');
      Navigator.pop(context);
    }
  }

  Future<void> _transfer() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          initialDate: _date,
          sourceId: _walletId,
          onPosted: widget.onPosted,
        ),
      ),
    );
    if (result == true && mounted) Navigator.pop(context, EditorResult.saved);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walletsProvider);
    final wallets =
        state.valueOrNull?.wallets
            .where((w) => !w.archived || w.id == _walletId)
            .toList() ??
        const <Wallet>[];
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    final selectedWallet = wallets.where((w) => w.id == _walletId).firstOrNull;
    final fieldButton = TextButton.styleFrom(
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsets.zero,
      foregroundColor: palette.textPrimary,
      textStyle: Theme.of(context).textTheme.bodyMedium,
    );
    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        titleTextStyle: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: palette.textPrimary),
        leading: const BackButton(),
        title: Text(
          _isEdit ? context.tr('Edit transaction', 'ویرایش معامله') : _type.isIncome
              ? context.tr('Add income', 'افزودن عاید') : context.tr('Add expense', 'افزودن مصرف'),
        ),
        actions: [
          if (!_isEdit)
            IconButton(
              tooltip: 'Reuse an entry',
              icon: const Icon(Icons.star_outline),
              onPressed: _saving ? null : _frequent,
            ),
          if (_isEdit)
            IconButton(
              tooltip: 'Receipts & documents',
              icon: const Icon(Icons.attach_file),
              onPressed: _saving
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AttachmentsScreen(
                          transactionId: widget.existing!.id!,
                        ),
                      ),
                    ),
            ),
          if (_isEdit)
            IconButton(
              tooltip: 'Delete transaction',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                children: [
                  Row(
                    children: [
                      for (final label in [
                        'Income',
                        'Expense',
                        if (!_isEdit) 'Transfer',
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                tapTargetSize: MaterialTapTargetSize.padded,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                foregroundColor: _type.label == label
                                    ? context.accent.onSurface
                                    : scheme.onSurface,
                                backgroundColor: _type.label == label
                                    ? context.accent.surface
                                    : null,
                                side: BorderSide(
                                  color: _type.label == label
                                      ? context.accent.primary
                                      : scheme.outline,
                                ),
                              ),
                              onPressed: _saving
                                  ? null
                                  : () => label == 'Transfer'
                                        ? _transfer()
                                        : _setType(
                                            label == 'Income'
                                                ? TransactionType.income
                                                : TransactionType.expense,
                                          ),
                              child: Text(switch (label) {
                                'Income' => context.tr('Income', 'عاید'),
                                'Expense' => context.tr('Expense', 'مصرف'),
                                _ => context.tr('Transfer', 'انتقال'),
                              }),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountText,
                    enabled: !_saving,
                    key: const ValueKey('entry-amount'),
                    keyboardType: TextInputType.none,
                    textAlign: TextAlign.center,
                    style: AppTypography.amount(39, color: palette.textPrimary),
                    decoration: InputDecoration(
                      labelText: '${context.tr('Amount', 'مبلغ')} (${_currency.code})',
                      hintText: '0',
                      hintStyle: AppTypography.amount(39, color: palette.textSecondary),
                      floatingLabelAlignment: FloatingLabelAlignment.center,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      fillColor: context.accent.surface,
                    ),
                    onChanged: (v) => setState(() {
                      final raw = v.trim();
                      _amount = AmountInput(
                        Money.parseMinor(raw, _currency) == null ? raw : raw.replaceAll(',', ''),
                        _currency,
                      );
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _EntryRow(
                    context.tr('Category', 'دسته'),
                    TextButton(
                      style: fieldButton,
                      onPressed: _saving ? null : _chooseCategory,
                      child: Text(
                        _categoryId == null
                            ? context.tr('Choose category', 'انتخاب دسته')
                            : Categories.byId(_categoryId!).name,
                      ),
                    ),
                  ),
                  if (!_showAccounts && !_isEdit)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final cat in orderedCategories.take(3))
                            ChoiceChip(
                              key: ValueKey('quick-category-${cat.id}'),
                              avatar: Icon(cat.icon, size: 16),
                              label: Text(cat.name),
                              selected: _categoryId == cat.id,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() {
                                      _categoryId = cat.id;
                                      _error = null;
                                    }),
                            ),
                        ],
                      ),
                    ),
                  _EntryRow(
                    context.tr('Note', 'یادداشت'),
                    TextField(
                      key: const ValueKey('entry-note'),
                      controller: _noteText,
                      enabled: !_saving,
                      maxLength: 240,
                      decoration: const InputDecoration(
                        hintText: 'Optional',
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        enabledBorder: InputBorder.none,
                        counterText: '',
                      ),
                      onChanged: (v) => _note = v.trim(),
                    ),
                  ),
                  _EntryRow(
                    context.tr('Date', 'تاریخ'),
                    TextButton(
                      style: fieldButton,
                      onPressed: _saving ? null : _pickDate,
                      child: Text(DateFormat.yMMMd().add_jm().format(_date)),
                    ),
                  ),
                  _EntryRow(
                    context.tr('Account', 'حساب'),
                    state.hasError
                        ? TextButton(
                            onPressed: () => ref.invalidate(walletsProvider),
                            child: const Text('Retry loading wallets'),
                          )
                        : wallets.isEmpty
                        ? Text(_currency.code)
                        : TextButton(
                            style: fieldButton,
                            onPressed: _saving
                                ? null
                                : () {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    setState(
                                      () => _showAccounts = !_showAccounts,
                                    );
                                  },
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedWallet == null
                                        ? 'Choose account'
                                        : walletLabel(selectedWallet),
                                  ),
                                ),
                                Icon(
                                  _showAccounts
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (!_showAccounts) ...[
                    const SizedBox(height: 8),
                    AmountKeypad(
                      allowDecimal: _currency.decimalDigits > 0,
                      enabled: !_saving,
                      onKey: (key) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() {
                          _amount = applyAmountKey(_amount, key);
                          _amountText.text = _amount.isEmpty ? '' : _amount.display;
                          _error = null;
                        });
                      },
                    ),
                  ],
                  if (_showAccounts) ...[
                    ColoredBox(
                      color: palette.surfaceMuted,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Choose account',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close accounts',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _showAccounts = false),
                          ),
                        ],
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns =
                            box.maxWidth >= 340 &&
                                MediaQuery.textScalerOf(context).scale(14) < 19
                            ? 3
                            : 2;
                        return Wrap(
                          children: [
                            for (final wallet in wallets)
                              SizedBox(
                                width: box.maxWidth / columns,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                    shape: const RoundedRectangleBorder(),
                                    backgroundColor: wallet.id == _walletId
                                        ? context.accent.surface
                                        : palette.surface,
                                    foregroundColor: palette.textPrimary,
                                    side: BorderSide(color: palette.border),
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => selectAccount(wallet),
                                  child: Text(
                                    walletLabel(wallet),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  ExpansionTile(
                    title: Text(context.tr('More details', 'جزئیات بیشتر')),
                    initiallyExpanded: _project.projectId != null,
                    children: [
                      if (ref.watch(projectRepositoryProvider) != null)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            _project.projectId == null
                                ? 'Project (optional)'
                                : ref
                                          .watch(projectsProvider)
                                          .valueOrNull
                                          ?.projects
                                          .where(
                                            (p) => p.id == _project.projectId,
                                          )
                                          .firstOrNull
                                          ?.name ??
                                      'Assigned project',
                          ),
                          onTap: _saving ? null : _editProject,
                        ),
                      if (!_isEdit &&
                          !_addReceipt &&
                          !_project.clientReceipt &&
                          _project.categoryId == null &&
                          ref.watch(planningRepositoryProvider) != null)
                        ListTile(
                          leading: const Icon(Icons.event_repeat),
                          title: const Text('Create a recurring schedule'),
                          subtitle: const Text(
                            'Review a schedule using these details. Saving it closes this draft.',
                          ),
                          onTap: _saving ? null : _schedule,
                        ),
                      if (!_isEdit)
                        CheckboxListTile(
                          title: Text(context.tr('Add a receipt after saving', 'افزودن رسید پس از ذخیره')),
                          value: _addReceipt,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _addReceipt = v ?? false),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : _isEdit
                        ? 'Save changes'
                        : _type.isIncome ? context.tr('Save income', 'ذخیرهٔ عاید')
                          : context.tr('Save expense', 'ذخیرهٔ مصرف'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.name, this.field);
  final String name;
  final Widget field;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            SizedBox(
              width: 82,
              child: Text(
                name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: field,
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1, indent: 82),
    ],
  );
}
