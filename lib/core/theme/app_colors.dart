import 'package:flutter/material.dart';

/// Brand colour primitives. Screens should prefer the semantic
/// [AppPalette] (via `context.palette`) over these raw values.
abstract final class AppColors {
  static const primary = Color(0xFFD84A45);
  static const primaryDark = Color(0xFFB93835);
  static const primaryLight = Color(0xFFFFAAA3);

  // Midnight navy scale
  static const navy950 = Color(0xFF0B1220);
  static const navy900 = Color(0xFF222222);
  static const navy800 = Color(0xFF1D2939);
  static const navy700 = Color(0xFF344054);
  static const navy600 = Color(0xFF475467);

  // Slate / neutral scale
  static const slate500 = Color(0xFF666666);
  static const slate400 = Color(0xFF98A2B3);
  static const slate300 = Color(0xFFD0D5DD);
  static const slate200 = Color(0xFFE5E5E5);
  static const slate100 = Color(0xFFF2F4F7);
  static const offWhite = Color(0xFFF7F7F7);
  static const white = Color(0xFFFFFFFF);

  static const incomeBlue = Color(0xFF206BA9);
  static const incomeLight = Color(0xFF83BFFF);
  // Legacy palette for stored goal and project choices.
  static const emerald = Color(0xFF10B981);
  static const emeraldDeep = Color(0xFF047857);
  static const emeraldBright = Color(0xFF34D399);
  static const emeraldMist = Color(0xFFD1FAE5);

  // Supporting semantic hues
  static const rose = Color(0xFFF43F5E);
  static const roseSoft = Color(0xFFFB7185);
  static const amber = Color(0xFFF59E0B);
}

/// Semantic palette that adapts to brightness. Registered as a
/// [ThemeExtension] so it animates smoothly when the theme changes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.income,
    required this.incomeSoft,
    required this.expense,
    required this.expenseSoft,
    required this.warning,
    required this.warningSoft,
    required this.shadow,
    required this.navBar,
    required this.chartGrid,
    required this.chartTrack,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color income;
  final Color incomeSoft;
  final Color expense;
  final Color expenseSoft;
  final Color warning;
  final Color warningSoft;
  final Color shadow;
  final Color navBar;
  final Color chartGrid;
  final Color chartTrack;

  static const light = AppPalette(
    background: AppColors.offWhite,
    surface: AppColors.white,
    surfaceMuted: AppColors.slate100,
    surfaceElevated: AppColors.white,
    border: AppColors.slate200,
    textPrimary: AppColors.navy900,
    textSecondary: AppColors.slate500,
    textTertiary: AppColors.slate500,
    income: AppColors.incomeBlue,
    incomeSoft: Color(0xFFE9F3FD),
    expense: Color(0xFFBD3836),
    expenseSoft: Color(0xFFFDECEF),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFEF3E2),
    shadow: Color(0xFF222222),
    navBar: AppColors.white,
    chartGrid: Color(0xFFEDF0F4),
    chartTrack: Color(0xFFF1F4F8),
  );

  static const dark = AppPalette(
    background: AppColors.navy950,
    surface: Color(0xFF151E2E),
    surfaceMuted: Color(0xFF172133),
    surfaceElevated: AppColors.navy800,
    border: Color(0xFF223047),
    textPrimary: Color(0xFFF7F7F7),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF94A3B8),
    income: AppColors.incomeLight,
    incomeSoft: Color(0xFF192D40),
    expense: AppColors.roseSoft,
    expenseSoft: Color(0xFF2E1824),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF2E2614),
    shadow: Color(0xFF000000),
    navBar: AppColors.navy900,
    chartGrid: Color(0xFF1C2638),
    chartTrack: Color(0xFF1A2436),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      border: l(border, other.border),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      income: l(income, other.income),
      incomeSoft: l(incomeSoft, other.incomeSoft),
      expense: l(expense, other.expense),
      expenseSoft: l(expenseSoft, other.expenseSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      shadow: l(shadow, other.shadow),
      navBar: l(navBar, other.navBar),
      chartGrid: l(chartGrid, other.chartGrid),
      chartTrack: l(chartTrack, other.chartTrack),
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
