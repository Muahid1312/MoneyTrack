import 'package:flutter/material.dart';

import '../constants/categories.dart';
import '../theme/app_colors.dart';

/// Rounded-square tinted icon for a category.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.category,
    this.size = 44,
    this.selected = false,
  });

  final TransactionCategory category;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = category.color;
    final bg = selected
        ? c
        : c.withValues(alpha: context.isDark ? 0.18 : 0.12);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: selected
            ? [
                BoxShadow(
                    color: c.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6)),
              ]
            : null,
      ),
      child: Icon(
        category.icon,
        size: size * 0.48,
        color: selected
            ? Colors.white
            : (context.isDark ? Color.lerp(c, Colors.white, 0.18) : c),
      ),
    );
  }
}
