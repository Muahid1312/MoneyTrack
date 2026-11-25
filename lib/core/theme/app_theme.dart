import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_accent.dart';
import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData light([Color seed = AppAccent.emerald]) =>
      _build(AppPalette.light, Brightness.light, seed);
  static ThemeData dark([Color seed = AppAccent.emerald]) =>
      _build(AppPalette.dark, Brightness.dark, seed);

  static ThemeData _build(AppPalette p, Brightness brightness, Color seed) {
    final isDark = brightness == Brightness.dark;
    final a = AccentPalette.derive(
      seed,
      p.surface,
      p.textSecondary,
      brightness,
    );
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: a.primary,
          onPrimary: a.onPrimary,
          primaryContainer: a.surface,
          onPrimaryContainer: a.onSurface,
          secondary: a.primary,
          onSecondary: a.onPrimary,
          secondaryContainer: a.surface,
          onSecondaryContainer: a.onSurface,
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
          onError: AppAccent.ink(p.expense),
          errorContainer: p.expenseSoft,
          onErrorContainer: p.expense,
          surfaceTint: Colors.transparent,
        );
    final text = AppTypography.textTheme(p.textPrimary, p.textSecondary);
    final controlBorder = const OutlineInputBorder(
      borderRadius: AppRadii.control,
      borderSide: BorderSide.none,
    );
    final control = RoundedRectangleBorder(borderRadius: AppRadii.control);
    final card = RoundedRectangleBorder(borderRadius: AppRadii.card);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      extensions: [p, a],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          TargetPlatform.android: const FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 54,
        elevation: 0,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.textPrimary),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: .7, space: 1),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: a.primary,
        textColor: p.textPrimary,
      ),
      iconTheme: IconThemeData(color: p.textPrimary, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hintStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: controlBorder,
        enabledBorder: controlBorder,
        focusedBorder: controlBorder.copyWith(
          borderSide: BorderSide(color: a.primary, width: 1.5),
        ),
        errorBorder: controlBorder.copyWith(
          borderSide: BorderSide(color: p.expense, width: 1.2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: a.primary,
        selectionColor: a.primary.withValues(alpha: .25),
        selectionHandleColor: a.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: a.dark,
        contentTextStyle: text.bodyMedium?.copyWith(color: a.cardInk),
        actionTextColor: a.light,
        elevation: 0,
        shape: control,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: card,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: a.dark,
        headerForegroundColor: a.cardInk,
        rangePickerBackgroundColor: p.surfaceElevated,
        rangePickerHeaderBackgroundColor: a.dark,
        rangePickerHeaderForegroundColor: a.cardInk,
        rangeSelectionBackgroundColor: a.surface,
        todayBorder: BorderSide(color: a.primary),
        shape: card,
        dayStyle: text.bodyMedium,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: a.primary,
          textStyle: text.labelLarge,
          shape: control,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: card,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: control,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: control,
          side: BorderSide(color: p.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceMuted,
        selectedColor: a.surface,
        secondarySelectedColor: a.surface,
        checkmarkColor: a.onSurface,
        side: BorderSide.none,
        shape: control,
        labelStyle: text.labelMedium,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: a.primary,
        foregroundColor: a.onPrimary,
        elevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: control,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: a.surface,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? a.onSurface
                : a.unselected,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? a.onSurface
                : a.unselected,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 48,
        minVerticalPadding: 4,
        iconColor: p.textSecondary,
        selectedColor: a.onSurface,
        selectedTileColor: a.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: a.primary,
        linearTrackColor: p.chartTrack,
        circularTrackColor: p.chartTrack,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: a.dark,
          borderRadius: AppRadii.control,
        ),
        textStyle: text.labelMedium?.copyWith(color: a.cardInk),
      ),
    );
  }
}
