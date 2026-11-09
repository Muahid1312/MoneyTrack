import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing scale (4pt grid).
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal padding used by every top-level screen.
  static const double screen = 20;
}

/// Corner radii. Cards use [lg]/[xl], controls use [md], chips use [pill].
abstract final class AppRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;

  static const card = BorderRadius.all(Radius.circular(lg));
  static const hero = BorderRadius.all(Radius.circular(xl));
  static const control = BorderRadius.all(Radius.circular(md));
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 450);
  static const chart = Duration(milliseconds: 600);
}

abstract final class AppCurves {
  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutQuart;
}

abstract final class AppShadows {
  /// Soft two-layer shadow for cards. Nearly invisible in dark mode,
  /// where elevation is expressed with borders and surface tone instead.
  static List<BoxShadow> card(BuildContext context) {
    final p = context.palette;
    if (context.isDark) {
      return [
        BoxShadow(
          color: p.shadow.withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
    }
    return [
      BoxShadow(
        color: p.shadow.withValues(alpha: 0.04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: p.shadow.withValues(alpha: 0.06),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static List<BoxShadow> hero(BuildContext context) => [
        BoxShadow(
          color: AppColors.navy900.withValues(alpha: context.isDark ? 0.5 : 0.28),
          blurRadius: 32,
          offset: const Offset(0, 16),
        ),
      ];

  static List<BoxShadow> glow(Color color, {double strength = 0.35}) => [
        BoxShadow(
          color: color.withValues(alpha: strength),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}
