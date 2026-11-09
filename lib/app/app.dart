import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/currency.dart';
import '../core/theme/app_theme.dart';
import '../features/planning/application/planning_providers.dart';
import '../features/settings/application/settings_controller.dart';
import 'app_shell.dart';

class MoneyTrackApp extends ConsumerWidget {
  const MoneyTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      themeAnimationDuration: const Duration(milliseconds: 380),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        // Respect user font scaling, but keep layouts intact at extremes.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
          ),
          child: child!,
        );
      },
      home: const PlanningLifecycle(child: AppShell()),
    );
  }
}
