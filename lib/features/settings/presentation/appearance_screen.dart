import '../../../core/utils/app_language.dart';
import 'package:flutter/material.dart';
import '../../../data/models/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../application/appearance_controller.dart';
import '../application/settings_controller.dart';

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceState();
}

class _AppearanceState extends ConsumerState<AppearanceScreen> {
  late final TextEditingController _hex;
  late HSVColor _draft;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(accentProvider).seed;
    _draft = HSVColor.fromColor(current);
    _hex = TextEditingController(text: AppAccent.hex(current));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _edit(HSVColor color) => setState(() {
    _draft = color;
    _hex.text = AppAccent.hex(color.toColor());
    _error = null;
  });

  Future<void> _save(Future<void> Function() write) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await write();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save appearance. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(Color color) {
    _edit(HSVColor.fromColor(color));
    _save(() => ref.read(accentProvider.notifier).select(color));
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider);
    final mode = ref.watch(
      settingsProvider.select((settings) => settings.themeMode),
    );
    final language = ref.watch(
      settingsProvider.select((settings) => settings.language),
    );
    final parsed = AppAccent.parse(_hex.text);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Appearance', 'ظاهر'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(context.tr('Display mode', 'حالت نمایش'), style: t.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in [
                  ThemeMode.light,
                  ThemeMode.dark,
                  ThemeMode.system,
                ])
                  ChoiceChip(
                    label: Text(
                      option == ThemeMode.system
                          ? context.tr('System', 'سیستم')
                          : option == ThemeMode.light
                          ? context.tr('Light', 'روشن')
                          : context.tr('Dark', 'تاریک'),
                    ),
                    selected: mode == option,
                    onSelected: _busy
                        ? null
                        : (_) => _save(
                            () => ref
                                .read(settingsProvider.notifier)
                                .setThemeMode(option),
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(context.tr('Language', 'زبان'), style: t.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final choice in AppLanguageChoice.values)
                  ChoiceChip(
                    label: Text(
                      choice == AppLanguageChoice.english ? 'English' : 'دری',
                    ),
                    selected: choice == language,
                    onSelected: _busy
                        ? null
                        : (_) => _save(
                            () => ref
                                .read(settingsProvider.notifier)
                                .setLanguage(choice),
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(context.tr('Accent colors', 'رنگ برجسته'), style: t.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  children: [
                    for (final entry in AppAccent.presets.entries)
                      _Swatch(
                        entry.key,
                        entry.value,
                        selected: accent.seed == entry.value,
                        onTap: _busy ? null : () => _select(entry.value),
                      ),
                  ],
                ),
                if (accent.recent.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr('Recently used', 'رنگ‌های اخیر'),
                    style: t.labelLarge,
                  ),
                  Wrap(
                    spacing: 3,
                    children: [
                      for (final color in accent.recent)
                        _Swatch(
                          AppAccent.hex(color),
                          color,
                          selected: accent.seed == color,
                          onTap: _busy ? null : () => _select(color),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Live preview', 'پیش‌نمایش زنده'),
            style: t.titleMedium,
          ),
          const SizedBox(height: 8),
          Theme(
            data: context.isDark
                ? AppTheme.dark(_draft.toColor())
                : AppTheme.light(_draft.toColor()),
            child: const _ThemePreview(),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('Custom color', 'رنگ دلخواه'),
                  style: t.titleMedium,
                ),
                const SizedBox(height: 12),
                _Spectrum(color: _draft, onChange: _busy ? null : _edit),
                _Slider(
                  label: context.tr('Hue', 'طیف رنگ'),
                  value: _draft.hue,
                  max: 360,
                  onChange: _busy ? null : (v) => _edit(_draft.withHue(v)),
                ),
                _Slider(
                  label: context.tr('Saturation', 'غلظت رنگ'),
                  value: _draft.saturation,
                  onChange: _busy
                      ? null
                      : (v) => _edit(_draft.withSaturation(v)),
                ),
                _Slider(
                  label: context.tr('Brightness', 'روشنایی'),
                  value: _draft.value,
                  onChange: _busy ? null : (v) => _edit(_draft.withValue(v)),
                ),
                TextField(
                  key: const ValueKey('accent-hex'),
                  controller: _hex,
                  enabled: !_busy,
                  autocorrect: false,
                  inputFormatters: [LengthLimitingTextInputFormatter(7)],
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: context.tr('HEX color', 'کُد رنگ'),
                    hintText: '#09694F',
                    errorText: parsed == null
                        ? 'Enter six hexadecimal digits.'
                        : null,
                  ),
                  onChanged: (_) => setState(() {
                    final color = AppAccent.parse(_hex.text);
                    if (color != null) _draft = HSVColor.fromColor(color);
                  }),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || parsed == null
                      ? null
                      : () => _select(parsed),
                  child: Text(
                    context.tr('Apply custom color', 'اعمال رنگ دلخواه'),
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _edit(HSVColor.fromColor(AppAccent.emerald));
                          _save(
                            () => ref.read(accentProvider.notifier).reset(),
                          );
                        },
                  child: Text(
                    context.tr(
                      'Reset accent to Emerald',
                      'بازگشت به سبز زمردی',
                    ),
                  ),
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: context.palette.expense),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color, {required this.selected, this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: context.palette.border),
              ),
              child: selected
                  ? Icon(Icons.check, size: 20, color: AppAccent.ink(color))
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    this.max = 1,
    this.onChange,
  });
  final String label;
  final double value, max;
  final ValueChanged<double>? onChange;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Semantics(
        label: label,
        child: Slider(
          value: value,
          max: max,
          onChanged: onChange,
          semanticFormatterCallback: (number) => max == 360
              ? '${number.round()} degrees'
              : '${(number * 100).round()} percent',
        ),
      ),
    ],
  );
}

class _Spectrum extends StatelessWidget {
  const _Spectrum({required this.color, this.onChange});
  final HSVColor color;
  final ValueChanged<HSVColor>? onChange;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(
      builder: (context, box) {
        const h = 108.0;
        void pick(Offset point) => onChange?.call(
          color
              .withSaturation((point.dx / box.maxWidth).clamp(0.0, 1.0))
              .withValue((1 - point.dy / h).clamp(0.0, 1.0)),
        );
        return ClipRRect(
          borderRadius: AppRadii.control,
          child: GestureDetector(
            onTapDown: (event) => pick(event.localPosition),
            onPanUpdate: (event) => pick(event.localPosition),
            child: SizedBox(
              height: h,
              width: box.maxWidth,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            color.withSaturation(1).withValue(1).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (color.saturation * box.maxWidth - 10).clamp(
                      0,
                      box.maxWidth - 20,
                    ),
                    top: ((1 - color.value) * h - 10).clamp(0, h - 20),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppAccent.ink(color.toColor()),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final a = context.accent, t = Theme.of(context).textTheme;
    final p = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: a.dark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Personal balance', 'موجودی شخصی'),
                  style: t.labelMedium?.copyWith(color: a.cardInk),
                ),
                Text(
                  '15,000.00 AFN',
                  style: t.headlineMedium?.copyWith(color: a.cardInk),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: AppRadii.control,
            child: const LinearProgressIndicator(value: .62, minHeight: 7),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: a.primary,
                  borderRadius: AppRadii.control,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Text(
                    context.tr('Save', 'ذخیره'),
                    style: t.labelLarge?.copyWith(color: a.onPrimary),
                  ),
                ),
              ),
              Chip(
                avatar: Icon(Icons.home_outlined, color: a.onSurface),
                label: Text(context.tr('Home', 'خانه')),
                backgroundColor: a.surface,
              ),
              Icon(
                Icons.shopping_bag_outlined,
                color: a.primary,
                semanticLabel: 'Transaction icon',
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in [12.0, 21.0, 17.0, 30.0])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 7,
                        height: h,
                        decoration: BoxDecoration(
                          color: h == 30 ? a.primary : p.chartTrack,
                          borderRadius: AppRadii.control,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
