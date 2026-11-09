import 'package:flutter/material.dart';

import '../../data/models/transaction.dart';
import '../constants/currency.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../utils/date_utils.dart';
import '../utils/money.dart';
import 'category_avatar.dart';
import 'pressable.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.currency,
    this.onTap,
    this.onLongPress,
    this.showDate = false,
    this.highlight = false,
  });

  final TransactionModel transaction;
  final AppCurrency currency;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showDate;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final tx = transaction;
    final amountColor = tx.type.isIncome ? p.income : p.textPrimary;
    final subtitle = [
      tx.category.name,
      showDate ? Dates.shortDate(tx.occurredAt) : Dates.time(tx.occurredAt),
    ].join(' · ');

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.985,
      semanticLabel:
          '${tx.title}, ${tx.type.label} ${Money.format(tx.amountMinor, tx.currency)}, $subtitle',
      child: AnimatedContainer(
        duration: AppDurations.slow,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.emerald.withValues(alpha: context.isDark ? 0.10 : 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            CategoryAvatar(category: tx.category, size: 44),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              Money.format(tx.signedMinor, tx.currency, signed: true),
              style: AppTypography.amount(15, weight: FontWeight.w700, color: amountColor),
            ),
          ],
        ),
      ),
    );
  }
}
