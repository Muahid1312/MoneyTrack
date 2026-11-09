import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'pressable.dart';

/// Base surface for all content cards.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.color,
    this.radius = AppRadii.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = AnimatedContainer(
      duration: AppDurations.medium,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: radius,
        border: Border.all(
          color: context.isDark ? p.border : p.border.withValues(alpha: 0.6),
        ),
        boxShadow: AppShadows.card(context),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

/// Title row used above cards and sections.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: t.bodySmall?.copyWith(color: p.textSecondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (actionLabel != null && onAction != null)
          Pressable(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!,
                      style: t.labelLarge?.copyWith(
                          color: context.isDark
                              ? AppColors.emeraldBright
                              : AppColors.emeraldDeep)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 18,
                      color: context.isDark
                          ? AppColors.emeraldBright
                          : AppColors.emeraldDeep),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
