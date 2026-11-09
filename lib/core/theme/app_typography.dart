import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography built on Plus Jakarta Sans (bundled under assets/google_fonts
/// so the app renders identically while fully offline).
abstract final class AppTypography {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _base(double size, FontWeight weight,
          {double? height, double? letterSpacing}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: _base(44, FontWeight.w700, height: 1.1, letterSpacing: -1.2),
      displayMedium: _base(36, FontWeight.w700, height: 1.1, letterSpacing: -1),
      displaySmall: _base(30, FontWeight.w700, height: 1.15, letterSpacing: -0.8),
      headlineLarge: _base(28, FontWeight.w700, height: 1.2, letterSpacing: -0.6),
      headlineMedium: _base(24, FontWeight.w700, height: 1.2, letterSpacing: -0.5),
      headlineSmall: _base(20, FontWeight.w700, height: 1.25, letterSpacing: -0.3),
      titleLarge: _base(18, FontWeight.w700, height: 1.3, letterSpacing: -0.2),
      titleMedium: _base(16, FontWeight.w600, height: 1.35, letterSpacing: -0.1),
      titleSmall: _base(14, FontWeight.w600, height: 1.4),
      bodyLarge: _base(16, FontWeight.w500, height: 1.5),
      bodyMedium: _base(14, FontWeight.w500, height: 1.45),
      bodySmall: _base(12.5, FontWeight.w500, height: 1.4),
      labelLarge: _base(14, FontWeight.w600, height: 1.3, letterSpacing: 0.1),
      labelMedium: _base(12.5, FontWeight.w600, height: 1.3, letterSpacing: 0.1),
      labelSmall: _base(11, FontWeight.w600, height: 1.3, letterSpacing: 0.3),
    ).apply(bodyColor: primary, displayColor: primary);
  }

  /// Monetary figures: tabular digits so animated values don't jitter.
  static TextStyle amount(double size,
      {FontWeight weight = FontWeight.w700, Color? color}) {
    return _base(size, weight,
            height: 1.1, letterSpacing: size >= 28 ? -1.2 : -0.3)
        .copyWith(fontFeatures: _tabular, color: color);
  }

  /// Small uppercase overline labels.
  static TextStyle overline(Color color) =>
      _base(11, FontWeight.w700, letterSpacing: 1.1).copyWith(color: color);
}
