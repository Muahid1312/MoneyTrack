import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.emerald,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.emeraldBright : AppColors.emeraldDeep,
      onPrimary: isDark ? AppColors.navy900 : Colors.white,
      secondary: isDark ? AppColors.slate200 : AppColors.navy900,
      onSecondary: isDark ? AppColors.navy900 : Colors.white,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceElevated,
      surfaceContainerHighest: p.surfaceMuted,
      outline: p.border,
      outlineVariant: p.border,
      error: p.expense,
      onError: Colors.white,
      surfaceTint: Colors.transparent,
    );
    final text = AppTypography.textTheme(p.textPrimary, p.textSecondary);

    final controlBorder = OutlineInputBorder(
      borderRadius: AppRadii.control,
      borderSide: BorderSide(color: p.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        ...const PageTransitionsTheme().builders,
        TargetPlatform.android: const FadeForwardsPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: p.textPrimary,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textPrimary, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hintStyle: text.bodyMedium?.copyWith(color: p.textTertiary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: controlBorder.copyWith(borderSide: BorderSide.none),
        enabledBorder: controlBorder.copyWith(borderSide: BorderSide.none),
        focusedBorder: controlBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        errorBorder: controlBorder.copyWith(
            borderSide: BorderSide(color: p.expense, width: 1.2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.emerald,
        selectionColor: AppColors.emerald.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.emerald,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.navy800 : AppColors.navy900,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.emeraldBright,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.hero),
        titleTextStyle: text.titleLarge,
        contentTextStyle:
            text.bodyMedium?.copyWith(color: p.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surfaceElevated,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: isDark ? AppColors.navy800 : AppColors.navy900,
        headerForegroundColor: Colors.white,
        rangePickerBackgroundColor: p.surfaceElevated,
        rangePickerHeaderBackgroundColor:
            isDark ? AppColors.navy800 : AppColors.navy900,
        rangePickerHeaderForegroundColor: Colors.white,
        rangeSelectionBackgroundColor:
            AppColors.emerald.withValues(alpha: 0.18),
        todayBorder: const BorderSide(color: AppColors.emerald),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.hero),
        dayStyle: text.bodyMedium,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.emeraldBright : AppColors.emeraldDeep,
          textStyle: text.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface, surfaceTintColor: Colors.transparent, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.card, side: BorderSide(color: p.border)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.control), textStyle: text.labelLarge,
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.control), side: BorderSide(color: p.border),
      )),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary,
        elevation: 2, extendedTextStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
      ),
      listTileTheme: ListTileThemeData(iconColor: p.textSecondary, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.emerald),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.navy800,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: text.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}
