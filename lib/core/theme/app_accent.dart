import 'package:flutter/material.dart';

/// Opaque sRGB colors are the stable, portable appearance preference.
abstract final class AppAccent {
  static const emerald = Color(0xFF09694F);
  static const presets = <String, Color>{
    'Emerald': emerald,
    'Ocean Blue': Color(0xFF2563EB),
    'Midnight Navy': Color(0xFF1E3A5F),
    'Royal Purple': Color(0xFF7950C4),
    'Crimson Red': Color(0xFFC83D48),
    'Sunset Orange': Color(0xFFB45309),
    'Teal': Color(0xFF087E8B),
    'Graphite': Color(0xFF475569),
    'Rose': Color(0xFFBE5279),
    'Indigo': Color(0xFF4338CA),
    'Forest Green': Color(0xFF356A42),
    'Obsidian': Color(0xFF202124),
  };
  static const preferenceKey = 'appearance_accents';
  static const recentLimit = 6;

  static Color? parse(String value) {
    final text = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) return null;
    return Color(0xFF000000 | int.parse(text, radix: 16));
  }

  static String hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
  }

  static Color ink(Color background) =>
      contrast(Colors.white, background) >= contrast(Colors.black, background)
      ? Colors.white
      : Colors.black;

  static Color readable(Color color, Color background, {double ratio = 4.5}) {
    if (contrast(color, background) >= ratio) return color;
    final target = ink(background);
    if (contrast(target, background) < ratio) return target;
    var low = 0.0, high = 1.0;
    for (var i = 0; i < 16; i++) {
      final mid = (low + high) / 2;
      if (contrast(Color.lerp(color, target, mid)!, background) >= ratio) {
        high = mid;
      } else {
        low = mid;
      }
    }
    return Color.lerp(color, target, high)!;
  }
}

@immutable
class AccentPreference {
  const AccentPreference({
    this.seed = AppAccent.emerald,
    this.recent = const [],
  });

  static AccentPreference? decode(String value) {
    final parts = value.split(',');
    if (parts.length > AppAccent.recentLimit + 1) return null;
    final colors = parts.map(AppAccent.parse).toList();
    if (colors.any((color) => color == null)) return null;
    final recent = colors.skip(1).cast<Color>().toList();
    if (recent.toSet().length != recent.length) return null;
    return AccentPreference(
      seed: colors.first!,
      recent: List.unmodifiable(recent),
    );
  }

  final Color seed;
  final List<Color> recent;
  String encode() => [seed, ...recent].map(AppAccent.hex).join(',');

  AccentPreference select(Color next) {
    final opaque = Color(0xFF000000 | (next.toARGB32() & 0xFFFFFF));
    return AccentPreference(
      seed: opaque,
      recent: List.unmodifiable(
        [
          opaque,
          ...recent.where((color) => color != opaque),
        ].take(AppAccent.recentLimit),
      ),
    );
  }
}

@immutable
class AccentPalette extends ThemeExtension<AccentPalette> {
  const AccentPalette({
    required this.primary,
    required this.onPrimary,
    required this.light,
    required this.dark,
    required this.surface,
    required this.onSurface,
    required this.cardInk,
    required this.unselected,
  });

  factory AccentPalette.derive(
    Color seed,
    Color surface,
    Color neutralInk,
    Brightness brightness,
  ) {
    final primary = AppAccent.readable(seed, surface);
    final tint = Color.lerp(
      surface,
      seed,
      brightness == Brightness.dark ? .23 : .10,
    )!;
    final deep = AppAccent.readable(
      Color.lerp(seed, Colors.black, .14)!,
      Colors.white,
      ratio: 7,
    );
    return AccentPalette(
      primary: primary,
      onPrimary: AppAccent.ink(primary),
      light: AppAccent.readable(Color.lerp(seed, Colors.white, .62)!, deep),
      dark: deep,
      surface: tint,
      onSurface: AppAccent.readable(primary, tint),
      cardInk: Colors.white,
      unselected: neutralInk,
    );
  }

  final Color primary,
      onPrimary,
      light,
      dark,
      surface,
      onSurface,
      cardInk,
      unselected;

  @override
  AccentPalette copyWith() => this;

  @override
  AccentPalette lerp(ThemeExtension<AccentPalette>? other, double t) {
    if (other is! AccentPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AccentPalette(
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      light: l(light, other.light),
      dark: l(dark, other.dark),
      surface: l(surface, other.surface),
      onSurface: l(onSurface, other.onSurface),
      cardInk: l(cardInk, other.cardInk),
      unselected: l(unselected, other.unselected),
    );
  }
}

extension AccentContext on BuildContext {
  AccentPalette get accent {
    final theme = Theme.of(this);
    return theme.extension<AccentPalette>() ??
        AccentPalette.derive(
          theme.colorScheme.primary,
          theme.colorScheme.surface,
          theme.colorScheme.onSurfaceVariant,
          theme.brightness,
        );
  }
}
