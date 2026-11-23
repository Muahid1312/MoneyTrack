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
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.primaryLight : AppColors.primaryDark,
      primaryContainer: isDark ? const Color(0xFF412726) : const Color(0xFFFBE9E7),
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
        backgroundColor:isDark?p.surface:AppColors.primaryDark,foregroundColor:Colors.white,
        surfaceTintColor:Colors.transparent,toolbarHeight:48,elevation:0,
        titleTextStyle:text.titleLarge?.copyWith(color:Colors.white),
        iconTheme:const IconThemeData(color:Colors.white),
        systemOverlayStyle:SystemUiOverlayStyle.light,
      ),
      dividerTheme: DividerThemeData(color:p.border,thickness:.7,space:1),
      expansionTileTheme: ExpansionTileThemeData(iconColor:scheme.primary,textColor:p.textPrimary,shape:Border(bottom:BorderSide(color:p.border)),collapsedShape:Border(bottom:BorderSide(color:p.border))),
      iconTheme: IconThemeData(color: p.textPrimary, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hintStyle: text.bodyMedium?.copyWith(color: p.textTertiary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: controlBorder.copyWith(borderSide: BorderSide.none),
        enabledBorder: controlBorder.copyWith(borderSide: BorderSide.none),
        focusedBorder: controlBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: controlBorder.copyWith(
            borderSide: BorderSide(color: p.expense, width: 1.2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.navy800 : AppColors.navy900,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.primaryLight,
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
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
            AppColors.primary.withValues(alpha: 0.18),
        todayBorder: const BorderSide(color: AppColors.primary),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.hero),
        dayStyle: text.bodyMedium,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.primaryLight : AppColors.primaryDark,
          textStyle: text.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface, surfaceTintColor: Colors.transparent, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 3),
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
      listTileTheme: ListTileThemeData(minTileHeight:48, minVerticalPadding:4,iconColor:p.textSecondary,contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:2)),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primary),
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
