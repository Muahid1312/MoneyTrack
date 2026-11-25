import 'package:flutter/material.dart';

import '../constants/categories.dart';
import '../theme/app_accent.dart';

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
    final a = context.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size, height: size,
      decoration: BoxDecoration(
        color: selected ? a.primary : a.surface,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(category.icon, size: size * .48,
        color: selected ? a.onPrimary : a.onSurface),
    );

  }
}
