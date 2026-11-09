import '../../documents/presentation/attachments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/category_avatar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pressable.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../settings/application/settings_controller.dart';
import '../application/transactions_controller.dart';
import 'transaction_editor_screen.dart';

/// Shared flows for creating, editing and deleting transactions so every
/// screen behaves identically.
abstract final class TransactionActions {
  static Future<void> openEditor(
    BuildContext context,
    WidgetRef ref, {
    TransactionModel? existing,
    TransactionType? initialType,
    int? initialProjectId,
    bool initialClientReceipt = false,
    Future<void> Function(TransactionModel tx)? animateOut,
  }) async {
    final result = await Navigator.of(context).push(
        TransactionEditorScreen.route(existing: existing, initialType: initialType, initialProjectId: initialProjectId, initialClientReceipt: initialClientReceipt));
    if (result == EditorResult.deleted && existing?.id != null && context.mounted) {
      if (animateOut != null) await animateOut(existing!);
      if (context.mounted) await deleteWithUndo(context, ref, existing!);
    }
  }

  /// Asks for confirmation, then deletes. Returns true if deleted.
  static Future<bool> confirmAndDelete(
      BuildContext context, WidgetRef ref, TransactionModel tx,
      {Future<void> Function(TransactionModel tx)? animateOut}) async {
    final ok = await askDelete(context, tx, ref.read(currencyProvider));
    if (!ok || !context.mounted) return false;
    if (animateOut != null) await animateOut(tx);
    if (!context.mounted) return false;
    return deleteWithUndo(context, ref, tx);
  }

  static Future<bool> askDelete(
          BuildContext context, TransactionModel tx, AppCurrency currency) =>
      confirmDestructive(
        context,
        title: 'Delete transaction?',
        message: '"${tx.title}" (${Money.format(tx.amountMinor, tx.currency)}) will be '
            'removed. Receipt links are removed too; Undo restores them until you leave this session.',
        confirmLabel: 'Delete',
      );

  static Future<bool> deleteWithUndo(
      BuildContext context, WidgetRef ref, TransactionModel tx) async {
    final controller = ref.read(transactionsProvider.notifier);
    TransactionModel? removed;
    try { removed = await controller.remove(tx.id!); }
    catch (_) {
      if (context.mounted) showAppSnack(context, message: 'Could not delete. Check reserved savings before reversing wallet income.');
      return false;
    }
    final undoEntry = removed;
    if (!context.mounted || undoEntry == null) return true;
    showAppSnack(
      context,
      message: 'Transaction deleted',
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.roseSoft,
      actionLabel: 'Undo',
      onAction: () async {
        try { await controller.restore(undoEntry); }
        catch (_) { if (context.mounted) showAppSnack(context, message: 'Could not restore. Check available funds and wallet/project status.'); }
      },
    );
    return true;
  }

  /// Long-press action sheet with details, edit and delete.
  static Future<void> showActions(
      BuildContext context, WidgetRef ref, TransactionModel tx,
      {Future<void> Function(TransactionModel tx)? animateOut}) async {
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        final t = Theme.of(ctx).textTheme;
        final currency = tx.currency;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CategoryAvatar(category: tx.category, size: 56),
              const SizedBox(height: 12),
              Text(tx.title, style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('${tx.category.name} · ${Dates.shortDate(tx.occurredAt)}',
                  style: t.bodySmall?.copyWith(color: p.textSecondary)),
              const SizedBox(height: 12),
              Text(Money.format(tx.signedMinor, currency, signed: true),
                  style: AppTypography.amount(28,
                      color: tx.type.isIncome ? p.income : p.textPrimary)),
              const SizedBox(height: 20),
              _SheetAction(
                icon: Icons.edit_outlined,
                label: 'Edit transaction',
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              _SheetAction(icon: Icons.attach_file, label: 'Receipts & documents', onTap: () => Navigator.of(ctx).pop('attachments')),
              _SheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Delete transaction',
                destructive: true,
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted) return;
    if (action == 'attachments') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttachmentsScreen(transactionId: tx.id!)));
    }
    if (action == 'edit') {
      await openEditor(context, ref, existing: tx, animateOut: animateOut);
    }
    if (action == 'delete' && context.mounted) {
      await confirmAndDelete(context, ref, tx, animateOut: animateOut);
    }
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = destructive ? p.expense : p.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: destructive ? p.expenseSoft : p.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
