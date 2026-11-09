import '../../documents/presentation/attachments_screen.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/amount_input.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pressable.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/models/wallet.dart';
import '../../../data/repositories/providers.dart';
import '../../projects/application/project_providers.dart';
import '../../projects/presentation/project_assignment_sheet.dart';
import '../../settings/application/settings_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import '../application/transactions_controller.dart';
import 'widgets/amount_keypad.dart';

enum EditorResult { saved, deleted }

class TransactionEditorScreen extends ConsumerStatefulWidget {
  const TransactionEditorScreen({super.key, this.existing, this.initialType, this.initialProjectId, this.initialClientReceipt = false});

  final TransactionModel? existing;
  final TransactionType? initialType;
  final int? initialProjectId;
  final bool initialClientReceipt;

  static Route<EditorResult> route({TransactionModel? existing, TransactionType? initialType, int? initialProjectId, bool initialClientReceipt = false}) {
    return PageRouteBuilder<EditorResult>(
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) =>
          TransactionEditorScreen(existing: existing, initialType: initialType, initialProjectId: initialProjectId, initialClientReceipt: initialClientReceipt),
      transitionsBuilder: (context, anim, secondary, child) {
        final c = CurvedAnimation(
            parent: anim, curve: AppCurves.emphasized, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: Tween(begin: 0.0, end: 1.0)
              .animate(CurvedAnimation(parent: anim, curve: const Interval(0, 0.6))),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(c),
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(c),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<TransactionEditorScreen> createState() => _TransactionEditorScreenState();
}

class _TransactionEditorScreenState extends ConsumerState<TransactionEditorScreen> {
  late TransactionType _type;
  late ProjectAssignment _project;
  int _walletId = 1;
  AppCurrency _currency = AppCurrency.usd;
  late AmountInput _amount;
  String? _categoryId;
  late DateTime _date;
  late String _note;
  String? _error;
  int _shakeAmount = 0;
  int _shakeCategory = 0;
  bool _saving = false;
  bool _done = false;
  final _categoryScroll = ScrollController();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _project = ProjectAssignment(projectId: e?.projectId ?? widget.initialProjectId,
      categoryId: e?.projectCategoryId, rate: e?.projectRate,
      clientReceipt: e?.clientReceipt ?? widget.initialClientReceipt,
      paymentReference: e?.paymentReference);
    _walletId = e?.walletId ?? 1;
    _currency = e?.currency ?? ref.read(walletsProvider).valueOrNull?.wallets.where((w) => w.id == 1).firstOrNull?.currency ?? ref.read(currencyProvider);
    _type = e?.type ?? widget.initialType ?? TransactionType.expense;
    _amount = e == null ? AmountInput('', _currency) : AmountInput.fromMinor(e.amountMinor, _currency);
    _categoryId = e?.categoryId;
    _date = e?.occurredAt ?? ref.read(clockProvider)();
    _note = e?.note ?? '';
  }

  @override
  void dispose() {
    _categoryScroll.dispose();
    super.dispose();
  }

  void _setType(TransactionType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      if (t.isExpense && _project.clientReceipt) {
        _project = ProjectAssignment(projectId: _project.projectId,
          categoryId: _project.categoryId, rate: _project.rate);
      }
      if (_categoryId != null && Categories.byId(_categoryId!).type != t) {
        _categoryId = null;
      }
      _error = null;
    });
    if (_categoryScroll.hasClients) {
      _categoryScroll.animateTo(0, duration: AppDurations.medium, curve: AppCurves.standard);
    }
  }

  void _onKey(KeypadKey key) {
    final before = _amount.raw;
    setState(() {
      _amount = switch (key) {
        DigitKey(:final digit) => _amount.appendDigit(digit),
        DecimalKey() => _amount.appendDecimal(),
        BackspaceKey() => _amount.backspace(),
        ClearKey() => _amount.clear(),
      };
      if (_amount.minor > 0 && _error != null && _categoryId != null) _error = null;
    });
    if (before == _amount.raw && key is! ClearKey) {
      HapticFeedback.heavyImpact(); // input rejected (limit reached)
    } else {
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _pickDate() async {
    if (widget.existing?.recurringRuleId != null) {
      showAppSnack(context, message: 'The scheduled occurrence date stays fixed. Edit the rule for future dates.');
      return;
    }
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Transaction date',
    );
    if (picked != null) {
      setState(() => _date = DateTime(
          picked.year, picked.month, picked.day, _date.hour, _date.minute, _date.second));
    }
  }

  Future<void> _editNote() async {
    final result = await showAppSheet<String>(
      context,
      builder: (ctx) => _NoteSheet(initial: _note),
    );
    if (result != null) setState(() => _note = result.trim());
  }

  Future<void> _editProject() async {
    final result = await showModalBottomSheet<ProjectAssignment>(context: context,
      isScrollControlled: true, useSafeArea: true,
      builder: (_) => ProjectAssignmentSheet(initial: _project,
        sourceCurrency: _currency, amountMinor: _amount.minor, isIncome: _type.isIncome));
    if (result != null && mounted) setState(() { _project = result; _error = null; });
  }

  Future<void> _save() async {
    if (_saving) return;
    final repo = ref.read(walletRepositoryProvider);
    if (repo != null) {
      final wallet = ref.read(walletsProvider).valueOrNull?.wallets
          .where((w) => w.id == _walletId).firstOrNull;
      if (wallet == null || wallet.archived || wallet.currency != _currency) {
        setState(() => _error = 'Choose an active wallet before saving');
        return;
      }
    }
    final minor = _amount.minor;
    if (minor <= 0) {
      setState(() {
        _error = 'Enter an amount greater than zero';
        _shakeAmount++;
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
        _shakeCategory++;
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
        await controller.edit(widget.existing!.copyWith(
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
        ));
      } else {
        await controller.add(TransactionModel(
          walletId: _walletId,
          currency: _currency,
          projectId: _project.projectId, projectCategoryId: _project.categoryId,
          projectRate: _project.rate, clientReceipt: _type.isIncome && _project.clientReceipt,
          paymentReference: _project.paymentReference,
          type: _type,
          amountMinor: minor,
          categoryId: _categoryId!,
          note: _note,
          occurredAt: _date,
          createdAt: now,
          updatedAt: now,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is FormatException ? e.message
          : e is ArgumentError ? '${e.message}'
          : e is DatabaseException && e.toString().toLowerCase().contains('reserved')
            ? 'This would consume reserved savings. Withdraw a savings reservation or choose another wallet.'
          : e is DatabaseException && e.isUniqueConstraintError()
            ? 'That payment reference is already recorded for this wallet or project. Edit the existing receipt instead.'
            : 'Could not save. Check the wallet/project status and try again.';
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    // ignore: deprecated_member_use
    SemanticsService.announce(
        _isEdit ? 'Transaction updated' : 'Transaction saved', TextDirection.ltr);
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    if (mounted) Navigator.of(context).pop(EditorResult.saved);
  }

  Future<void> _delete() async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete transaction?',
      message: 'This transaction will be permanently removed from your history.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop(EditorResult.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final currency = _currency;
    final walletState = ref.watch(walletsProvider);
    final available = walletState.valueOrNull?.wallets
        .where((w) => !w.archived || w.id == _walletId).toList();
    final accent = _type.isIncome ? AppColors.emerald : p.expense;

    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(builder: (context, c) {
                final compact = c.maxHeight < 700;
                // Very short screens: keep everything reachable by scrolling.
                final scroll = c.maxHeight < 620 || ref.watch(projectRepositoryProvider) != null;
                final saveButton = Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.md),
                  child: PrimaryButton(
                    label: _isEdit ? 'Save changes' : 'Save ${_type.label.toLowerCase()}',
                    icon: Icons.check_rounded,
                    height: scroll ? 52 : 56,
                    loading: _saving && !_done,
                    onPressed: _save,
                  ),
                );
                final column = Column(
                  children: [
                    _header(t),
                    if (ref.watch(walletRepositoryProvider) != null)
                      Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                        child: walletState.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => TextButton(onPressed: () => ref.invalidate(walletsProvider), child: const Text('Retry loading wallets')),
                          data: (_) => DropdownButtonFormField<int>(isExpanded: true, 
                            key: ValueKey(_walletId), initialValue: available?.any((w) => w.id == _walletId) == true ? _walletId : null,
                            decoration: const InputDecoration(labelText: 'Wallet · original currency'),
                            items: [for (final w in available ?? <Wallet>[])
                              DropdownMenuItem(value: w.id, child: Text('${w.name} · ${w.currency.code}${w.archived ? ' · Archived' : ''}'))],
                            onChanged: _saving ? null : (id) {
                              final w = available!.firstWhere((w) => w.id == id);
                              setState(() {
                                if (_currency != w.currency) {
                                  _amount = AmountInput('', w.currency);
                                  // A rate from the previous source currency cannot be reused.
                                  _project = ProjectAssignment(projectId: _project.projectId,
                                    categoryId: _project.categoryId,
                                    clientReceipt: _project.clientReceipt,
                                    paymentReference: _project.paymentReference);
                                }
                                _walletId = id!; _currency = w.currency;
                              });
                            },
                          ),
                        )),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
                      child: SegmentedSwitch<TransactionType>(
                        values: const [TransactionType.expense, TransactionType.income],
                        selected: _type,
                        labelOf: (v) => v.label,
                        iconOf: (v) => v.isIncome
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        activeColorOf: (v) => v.isIncome ? AppColors.emerald : p.expense,
                        onChanged: _setType,
                      ),
                    ),
                    if (scroll)
                      SizedBox(height: 116, child: _amountDisplay(currency, accent, t, compact))
                    else
                      Expanded(child: _amountDisplay(currency, accent, t, compact)),
                    if (ref.watch(projectRepositoryProvider) != null)
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ListTile(dense: true, contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(_project.projectId == null ? 'Project (optional)' :
                            ref.watch(projectsProvider).valueOrNull?.projects.where((p) => p.id == _project.projectId).firstOrNull?.name ?? 'Project assignment'),
                          subtitle: Text(_project.projectId == null ? 'Unassigned personal transaction' :
                            _project.clientReceipt ? 'Client receipt · ${_project.paymentReference ?? "add payment reference"}' : 'Project category & historical conversion'),
                          trailing: const Icon(Icons.chevron_right), onTap: _saving ? null : _editProject)),
                    _metaRow(t),
                    SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                    _ShakeX(trigger: _shakeCategory, child: _categoryPicker(t)),
                    SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen - 4),
                      child: AmountKeypad(
                        onKey: _onKey,
                        keyHeight: scroll ? 48 : (compact ? 52 : 58),
                      ),
                    ),
                    if (!scroll) saveButton,
                  ],
                );
                if (!scroll) return column;
                // Short screens: content scrolls, Save stays pinned.
                return Column(
                  children: [
                    Expanded(child: SingleChildScrollView(child: column)),
                    saveButton,
                  ],
                );
              }),
            ),
            if (_done)
              Positioned.fill(
                child: _SuccessOverlay(
                  title: _isEdit ? 'Changes saved' : '${_type.label} added',
                  amount: Money.format(_amount.minor, currency),
                  color: accent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(TextTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              _isEdit ? 'Edit transaction' : 'New transaction',
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (_isEdit)
            AppIconButton(icon: Icons.attach_file, tooltip: 'Receipts & documents',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttachmentsScreen(transactionId: widget.existing!.id!)))),
          if (_isEdit)
            AppIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete transaction',
              foreground: context.palette.expense,
              onPressed: _delete,
            )
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _amountDisplay(AppCurrency currency, Color accent, TextTheme t, bool compact) {
    final p = context.palette;
    final empty = _amount.isEmpty;
    final symbol = Text(
      currency.symbol,
      style: AppTypography.amount(compact ? 26 : 30,
          weight: FontWeight.w600, color: empty ? p.textTertiary : p.textSecondary),
    );
    return Semantics(
      liveRegion: true,
      label: 'Amount ${Money.format(_amount.minor, currency)}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: AppDurations.medium,
            child: Text(
              _type.isIncome ? 'MONEY IN' : 'MONEY OUT',
              key: ValueKey(_type),
              style: AppTypography.overline(accent),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ShakeX(
            trigger: _shakeAmount,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!currency.symbolAfter) ...[symbol, const SizedBox(width: 6)],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.18), end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.center,
                        children: [...previous, if (current != null) current],
                      ),
                      child: Text(
                        _amount.display,
                        key: ValueKey(_amount.raw),
                        style: AppTypography.amount(compact ? 50 : 60,
                            weight: FontWeight.w800,
                            color: empty ? p.textTertiary : p.textPrimary),
                      ),
                    ),
                    if (currency.symbolAfter) ...[const SizedBox(width: 8), symbol],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: AppDurations.fast,
            child: _error == null
                ? const SizedBox(height: 20)
                : Row(
                    key: ValueKey(_error),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: p.expense),
                      const SizedBox(width: 6),
                      Text(_error!, style: t.labelMedium?.copyWith(color: p.expense)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(TextTheme t) {
    final now = ref.read(clockProvider)();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Row(
        children: [
          Expanded(
            child: _MetaButton(
              icon: Icons.calendar_today_rounded,
              label: Dates.relativeDay(_date, now),
              onTap: _pickDate,
              semantic: 'Change date, ${Dates.shortDate(_date)}',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MetaButton(
              icon: Icons.notes_rounded,
              label: _note.isEmpty ? 'Add note' : _note,
              muted: _note.isEmpty,
              onTap: _editNote,
              semantic: _note.isEmpty ? 'Add description' : 'Edit description, $_note',
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryPicker(TextTheme t) {
    final p = context.palette;
    final cats = Categories.forType(_type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: Text('Category',
              style: t.labelMedium?.copyWith(color: p.textSecondary)),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 84,
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            child: ListView.separated(
              key: ValueKey(_type),
              controller: _categoryScroll,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) {
                final c = cats[i];
                final selected = c.id == _categoryId;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: c.name,
                  excludeSemantics: true,
                  child: Pressable(
                    haptic: true,
                    scale: 0.92,
                    onTap: () => setState(() {
                      _categoryId = c.id;
                      if (_error == 'Choose a category') _error = null;
                    }),
                    child: SizedBox(
                      width: 70,
                      child: Column(
                        children: [
                          CategoryAvatar(category: c, size: 50, selected: selected),
                          const SizedBox(height: 6),
                          Text(
                            c.name.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelSmall?.copyWith(
                              color: selected ? p.textPrimary : p.textSecondary,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaButton extends StatelessWidget {
  const _MetaButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.semantic,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String semantic;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: p.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(
                      color: muted ? p.textTertiary : p.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.initial});
  final String initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Description', subtitle: 'Optional — e.g. "Lunch with team"'),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v),
            decoration: const InputDecoration(hintText: 'What was this for?'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Row(
            children: [
              if (widget.initial.isNotEmpty) ...[
                Expanded(
                  child: SecondaryButton(
                    label: 'Remove',
                    onPressed: () => Navigator.of(context).pop(''),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: PrimaryButton(
                  label: 'Done',
                  height: 52,
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal shake when [trigger] changes (validation feedback).
class _ShakeX extends StatelessWidget {
  const _ShakeX({required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: trigger == 0 ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, v, child) {
        final dx = math.sin(v * math.pi * 6) * 10 * (1 - v);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}

class _SuccessOverlay extends StatelessWidget {
  const _SuccessOverlay({required this.title, required this.amount, required this.color});
  final String title;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      builder: (context, v, _) {
        final bg = Curves.easeOut.transform((v / 0.3).clamp(0, 1));
        final pop = Curves.elasticOut.transform(((v - 0.1) / 0.6).clamp(0, 1));
        final check = Curves.easeOutCubic.transform(((v - 0.3) / 0.45).clamp(0, 1));
        final text = Curves.easeOut.transform(((v - 0.45) / 0.4).clamp(0, 1));
        return ColoredBox(
          color: p.background.withValues(alpha: 0.97 * bg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: pop,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color.lerp(color, Colors.white, 0.2)!, color],
                      ),
                      boxShadow: AppShadows.glow(color, strength: 0.4),
                    ),
                    child: CustomPaint(painter: _CheckPainter(check)),
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: text,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - text)),
                    child: Column(
                      children: [
                        Text(title, style: t.titleLarge),
                        const SizedBox(height: 6),
                        Text(amount,
                            style: AppTypography.amount(22,
                                weight: FontWeight.w700, color: p.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.30, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.66)
      ..lineTo(size.width * 0.71, size.height * 0.38);
    final metric = path.computeMetrics().first;
    final partial = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      partial,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
