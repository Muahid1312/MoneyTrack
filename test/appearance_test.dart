import 'package:moneytrack/data/models/planning.dart';
import 'package:moneytrack/features/budgets/domain/wallet_budget.dart';
import 'package:moneytrack/features/planning/application/planning_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/app/app.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/core/theme/app_accent.dart';
import 'package:moneytrack/core/theme/app_colors.dart';
import 'package:moneytrack/core/theme/app_theme.dart';
import 'package:moneytrack/core/widgets/finance_hero.dart';
import 'package:moneytrack/data/models/app_settings.dart';
import 'package:moneytrack/data/repositories/providers.dart';
import 'package:moneytrack/data/repositories/settings_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/data/storage/portable_snapshot.dart';
import 'package:moneytrack/features/explore/explore_screen.dart';
import 'package:moneytrack/features/settings/application/appearance_controller.dart';
import 'package:moneytrack/features/settings/application/settings_controller.dart';
import 'package:moneytrack/features/transactions/application/transactions_controller.dart';
import 'package:moneytrack/features/transactions/presentation/widgets/amount_keypad.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger_calendar_test.dart' as records;
import 'support/fakes.dart';
import 'support/open_feature.dart';
import 'support/screen_capture.dart';

void main() {
  test(
    'all presets and extreme custom accents keep contrast and financial semantics',
    () {
      expect(AppAccent.presets, hasLength(12));
      expect(AppAccent.parse('#fff'), isNull);
      expect(AppAccent.parse(' 25A0FF '), const Color(0xFF25A0FF));
      expect(AppAccent.parse('#8825A0FF'), isNull);
      for (final color in [
        ...AppAccent.presets.values,
        Colors.white,
        Colors.black,
        const Color(0xFFFFFF00),
      ]) {
        for (final brightness in Brightness.values) {
          final test = brightness == Brightness.dark
              ? AppTheme.dark(color)
              : AppTheme.light(color);
          final t = test.extension<AccentPalette>()!;
          final semantic = test.extension<AppPalette>()!;
          expect(
            AppAccent.contrast(t.onPrimary, t.primary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            AppAccent.contrast(t.primary, semantic.surface),
            greaterThanOrEqualTo(4.49),
          );
          expect(
            AppAccent.contrast(t.onSurface, t.surface),
            greaterThanOrEqualTo(4.49),
          );
          expect(
            AppAccent.contrast(t.cardInk, t.dark),
            greaterThanOrEqualTo(7),
          );
          expect(
            semantic.expense,
            brightness == Brightness.dark
                ? AppPalette.dark.expense
                : AppPalette.light.expense,
          );
          expect(
            semantic.income,
            brightness == Brightness.dark
                ? AppPalette.dark.income
                : AppPalette.light.income,
          );
        }
      }
    },
  );

  test(
    'accent and language preferences round trip through the portable settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'currency': 'AFN',
        'monthly_budget_minor': 20000,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepository(prefs);
      expect(repo.loadAccent().seed, AppAccent.emerald);
      final next = repo
          .loadAccent()
          .select(Colors.black)
          .select(Colors.white)
          .select(Colors.black);
      await repo.saveAccent(next);
      await repo.save(
        repo.load().copyWith(
          language: AppLanguageChoice.dari,
          themeMode: ThemeMode.dark,
        ),
      );
      final backup = Map<String, dynamic>.from(
        PortableSnapshot.preferences(prefs),
      );
      expect(backup[AppAccent.preferenceKey], '#000000,#000000,#FFFFFF');
      expect(
        () => PortableSnapshot.validatePreferences({
          AppAccent.preferenceKey: '#123',
        }),
        throwsFormatException,
      );
      await prefs.clear();
      await PortableSnapshot.applyPreferences(prefs, backup);
      expect(repo.loadAccent().recent, [Colors.black, Colors.white]);
      expect(repo.load().language, AppLanguageChoice.dari);
      expect(repo.load().themeMode, ThemeMode.dark);
      expect(repo.load().currency, AppCurrency.afn);
      expect(repo.load().monthlyBudgetMinor, 20000);
    },
  );

  testWidgets(
    'Home, Budgets, keypad and Appearance use the same persistent theme',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'currency': 'AFN',
        'user_name': 'Ahmad',
        'theme_mode': 'light',
        'monthly_budget_minor': 220000,
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsRepository(prefs);
      final repo = InMemoryTransactionRepository(records.entries);
      final c = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          transactionRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(() => records.clock),
          planningProvider.overrideWith(
            (_) async => PlanningSnapshot(
              debts: [],
              postings: [],
              goals: [],
              savingsEvents: [],
              rules: [],
              occurrences: [],
              budgets: [
                WalletBudget(
                  id: 1,
                  walletId: 1,
                  limit: 40000,
                  category: 'groceries',
                  period: BudgetPeriod.monthly,
                  start: DateTime(2024, 2),
                ),
                WalletBudget(
                  id: 2,
                  walletId: 1,
                  limit: 25000,
                  category: 'food',
                  period: BudgetPeriod.weekly,
                  start: DateTime(2024, 2, 26),
                ),
              ],
            ),
          ),
          walletsProvider.overrideWith(
            (_) async => const WalletSnapshot(
              records.wallets,
              {1: 2275000, 2: 45000},
              [],
              reserved: {1: 500000},
            ),
          ),
        ],
      );
      final key = GlobalKey();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      });
      await c.read(transactionsProvider.future);
      final before = c.read(allTransactionsProvider).toList();
      await loadCaptureFonts(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: RepaintBoundary(key: key, child: const MoneyTrackApp()),
        ),
      );
      await tester.pumpAndSettle();
      await captureView(tester, key, 'home-emerald');
      expect(find.text('22,750.00 ؋'), findsOneWidget);
      expect(find.text('Welcome to MoneyTrack'), findsOneWidget);
      expect(find.text('Weekly spending'), findsOneWidget);
      final todayBar = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message?.contains('85.00 ؋') ?? false),
      );
      await tester.ensureVisible(todayBar);
      await tester.pumpAndSettle();
      await tester.tap(todayBar);
      await tester.pumpAndSettle();
      expect(find.text('Tea and bread'), findsOneWidget);
      expect(find.text('Translation'), findsNothing);
      expect(find.text('Previous evening'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const PageStorageKey('moneytrack-home')),
        const Offset(0, 640),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add expense'));
      await tester.pumpAndSettle();
      expect(find.byType(AmountKeypad), findsOneWidget);
      await captureView(tester, key, 'add-expense');
      Future<void> keyTap(String label) async {
        final semantics = tester.ensureSemantics();
        final finder = find.bySemanticsLabel(label);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pump();
        semantics.dispose();
      }

      await keyTap('4');
      await keyTap('Decimal point');
      await keyTap('5');
      final amount = find.byKey(const ValueKey('entry-amount'));
      expect(tester.widget<TextField>(amount).controller!.text, '4.5');
      final semantics = tester.ensureSemantics();
      final delete = find.bySemanticsLabel('Delete digit. Long press to clear');
      await tester.longPress(delete);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amount).controller!.text, '');
      semantics.dispose();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'Budgets'));
      await tester.pumpAndSettle();
      expect(find.text('Add budget'), findsOneWidget);
      await captureView(tester, key, 'budgets');
      await openFeature(tester, MoneyFeature.appearance);
      expect(find.text('Display mode'), findsOneWidget);

      Future<void> reveal(Finder finder) async {
        final scrollable = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        if (finder.evaluate().isEmpty)
          await tester.scrollUntilVisible(finder, 240, scrollable: scrollable);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      final ocean = find.byTooltip('Ocean Blue');
      await reveal(ocean);
      await tester.tap(ocean);
      await tester.pumpAndSettle();
      expect(c.read(accentProvider).seed, AppAccent.presets['Ocean Blue']);
      await captureView(tester, key, 'appearance-ocean');
      final hex = find.byKey(const ValueKey('accent-hex'));
      await reveal(hex);
      await tester.enterText(hex, '#123');
      await tester.pumpAndSettle();
      expect(find.text('Enter six hexadecimal digits.'), findsOneWidget);
      await tester.enterText(hex, '#7950C4');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final apply = find.text('Apply custom color');
      await reveal(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(c.read(accentProvider).seed, AppAccent.presets['Royal Purple']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Home'));
      await tester.pumpAndSettle();
      final hero = tester.element(find.byType(FinanceHero).first);
      expect(Theme.of(hero).brightness, Brightness.dark);
      expect(
        hero.accent.primary,
        AppTheme.dark(AppAccent.presets['Royal Purple']!).colorScheme.primary,
      );
      await captureView(tester, key, 'home-purple-dark');
      await c
          .read(settingsProvider.notifier)
          .setLanguage(AppLanguageChoice.dari);
      await tester.pumpAndSettle();
      expect(find.text('به مانی‌ترک خوش آمدید'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(FinanceHero).first)),
        TextDirection.rtl,
      );
      await captureView(tester, key, 'home-dari-rtl');
      expect(c.read(allTransactionsProvider), before);
      expect(settings.loadAccent().seed, AppAccent.presets['Royal Purple']);
      expect(tester.takeException(), isNull);
    },
  );
}
