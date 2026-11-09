import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'buttons.dart';

/// Illustrated empty state: layered rings around an icon with a soft glow.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final size = compact ? 88.0 : 120.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.slow,
      curve: AppCurves.standard,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl, vertical: compact ? AppSpacing.lg : AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        AppColors.emerald.withValues(alpha: 0.16),
                        AppColors.emerald.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                  Container(
                    width: size * 0.72,
                    height: size * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border),
                      color: p.surface,
                    ),
                  ),
                  Container(
                    width: size * 0.48,
                    height: size * 0.48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.emerald.withValues(alpha: context.isDark ? 0.18 : 0.12),
                    ),
                    child: Icon(icon,
                        size: size * 0.24,
                        color: context.isDark
                            ? AppColors.emeraldBright
                            : AppColors.emeraldDeep),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
            Text(title,
                textAlign: TextAlign.center,
                style: (compact ? t.titleMedium : t.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: p.textSecondary)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: actionLabel!,
                icon: Icons.add_rounded,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
