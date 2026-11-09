import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'pressable.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.loading = false,
    this.destructive = false,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool loading;
  final bool destructive;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final base = destructive ? const Color(0xFFBE123C) : AppColors.emeraldDeep;
    final deep = destructive ? const Color(0xFF9F1239) : const Color(0xFF065F46);
    final t = Theme.of(context).textTheme;
    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleSmall?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
    return Pressable(
      onTap: enabled ? onPressed : null,
      haptic: true,
      semanticLabel: label,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: enabled || loading ? 1 : 0.45,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, deep],
            ),
            boxShadow: enabled ? AppShadows.glow(base, strength: 0.3) : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = color ?? p.textPrimary;
    final t = Theme.of(context).textTheme;
    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: p.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(
                      color: fg, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular tonal icon button.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.background,
    this.foreground,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color? background;
  final Color? foreground;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onPressed,
        scale: 0.92,
        semanticLabel: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: background ?? p.surface,
                shape: BoxShape.circle,
                border: background == null ? Border.all(color: p.border) : null,
              ),
              child: Icon(icon, size: size * 0.46, color: foreground ?? p.textPrimary),
            ),
            if (badge)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.background, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill segmented control with a sliding thumb.
class SegmentedSwitch<T> extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.activeColorOf,
    this.height = 46,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;
  final Color Function(T)? activeColorOf;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final index = values.indexOf(selected);
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / values.length;
        final active = activeColorOf?.call(selected);
        return Stack(
          children: [
            AnimatedPositioned(
              duration: AppDurations.medium,
              curve: AppCurves.standard,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: AnimatedContainer(
                duration: AppDurations.medium,
                decoration: BoxDecoration(
                  color: active ?? p.surfaceElevated,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: (active ?? p.shadow)
                          .withValues(alpha: active != null ? 0.3 : 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (final v in values)
                  Expanded(
                    child: Semantics(
                      selected: v == selected,
                      button: true,
                      label: labelOf(v),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(v),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: AppDurations.medium,
                            style: t.labelLarge!.copyWith(
                              color: v == selected
                                  ? (active != null ? Colors.white : p.textPrimary)
                                  : p.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (iconOf != null) ...[
                                  Icon(iconOf!(v),
                                      size: 17,
                                      color: v == selected
                                          ? (active != null
                                              ? Colors.white
                                              : p.textPrimary)
                                          : p.textSecondary),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(labelOf(v),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Selectable filter chip.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final fg = selected
        ? (context.isDark ? AppColors.navy900 : Colors.white)
        : p.textPrimary;
    return Pressable(
      onTap: onTap,
      haptic: true,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: AppDurations.medium,
        curve: AppCurves.standard,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? (context.isDark ? AppColors.offWhite : AppColors.navy900)
              : p.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? Colors.transparent : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(color: fg)),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              Icon(trailingIcon, size: 16, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
