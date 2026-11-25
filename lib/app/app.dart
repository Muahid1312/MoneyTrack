import 'package:flutter_localizations/flutter_localizations.dart';
import '../data/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/currency.dart';
import '../core/theme/app_theme.dart';
import '../features/planning/application/planning_providers.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/application/appearance_controller.dart';
import 'app_shell.dart';

class MoneyTrackApp extends ConsumerWidget {
  const MoneyTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final accent = ref.watch(accentProvider.select((s) => s.seed));
    final locale = ref.watch(settingsProvider.select((s) => s.language.locale));
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent),
      themeMode: mode,
      locale: locale,
      supportedLocales: [for (final language in AppLanguageChoice.values) language.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeAnimationDuration: Duration.zero,
      home: const PlanningLifecycle(child: AppShell()),
    );
  }
}
