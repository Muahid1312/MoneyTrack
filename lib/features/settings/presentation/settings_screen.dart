import '../../../data/storage/app_runtime.dart';
import '../../documents/application/document_service.dart';
import '../../reports/application/report_exporter.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../statistics/presentation/statistics_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../security/presentation/security_widgets.dart';
import '../../backup/presentation/backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../core/constants/currency.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/pressable.dart';
import '../../budgets/presentation/budget_editor_sheet.dart';
import '../../budgets/presentation/budget_screen.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/application/reminder_service.dart';
import '../../planning/presentation/planning_screens.dart';
import '../../projects/presentation/projects_screen.dart';
import '../../transactions/application/transaction_filter.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../wallets/presentation/wallets_screen.dart';
import '../application/data_export_service.dart';
import '../application/settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  bool _clearing = false;

  Future<void> _export(BuildContext tileContext) async {
    if (_clearing || _exporting) return;
    final txs = ref.read(allTransactionsProvider);
    if (txs.isEmpty) {
      showAppSnack(context,
          message: 'There are no transactions to export yet.',
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.slate300);
      return;
    }
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = true);
    try {
      final file = await DataExportService.writeCsv(txs, ref.read(currencyProvider));
      await DataExportService.share(file, txs.length, origin: origin);
    } catch (e) {
      if (mounted) {
        showAppSnack(context,
            message: 'Export failed. Please try again.',
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.roseSoft);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clearAll() async {
    if (_clearing || _exporting) return;
    setState(() => _clearing = true);
    try {
      final count = ref.read(allTransactionsProvider).length;
      final ok = await confirmDestructive(context, title: 'Clear current ledger?',
        message: 'This permanently deletes $count transactions, receipts, transfers, opening balances, project allocations, debts, savings history, recurring rules and history, budgets and preferences. Wallet and project definitions and the device PIN remain. Previously restored rollback generations and files saved outside the app remain. This cannot be undone.',
        confirmLabel: 'Clear ledger', icon: Icons.delete_forever_outlined);
      if (!ok || !mounted) return;
      await ref.read(transactionsProvider.notifier).clearAll();
      await ref.read(settingsProvider.notifier).reset();
      if (ref.read(planningRepositoryProvider) != null) {
        await ReminderService().setEnabled(false);
        if (!mounted) return;
        await refreshPlanning(ref);
      }
      if (!mounted) return;
      if (ref.read(appRuntimeProvider) != null) await ref.read(attachmentRepositoryProvider).cleanup();
      await ReportExporter.cleanup(all: true);
      if (!mounted) return;
      ref.read(transactionFilterProvider.notifier).state = const TransactionFilter();
      HapticFeedback.mediumImpact();
      showAppSnack(context, message: 'Current ledger and preferences cleared');
    } catch (_) {
      if (mounted) showAppSnack(context, message: 'Could not finish clearing data. Some changes may already have been applied. Reopen MoneyTrack and check the current ledger.');
    } finally { if (mounted) setState(() => _clearing = false); }
  }

  Future<void> _editName() async {
    final current = ref.read(settingsProvider).userName;
    final result = await showAppSheet<String>(context, builder: (_) => _NameSheet(initial: current));
    if (result != null) await ref.read(settingsProvider.notifier).setUserName(result);
  }

  Future<void> _pickCurrency() async {
    final current = ref.read(currencyProvider);
    final picked = await showAppSheet<AppCurrency>(
      context,
      builder: (ctx) => _CurrencySheet(current: current),
    );
    if (picked != null) await ref.read(settingsProvider.notifier).setCurrency(picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final count = ref.watch(allTransactionsProvider).length;
    final currency = settings.currency;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        MediaQuery.paddingOf(context).top + AppSpacing.lg,
        AppSpacing.screen,
        AppShell.contentBottomInset(context),
      ),
      children: [
        Text('Settings', style: t.headlineMedium),
        const SizedBox(height: 4),
        Text('Make MoneyTrack yours', style: t.bodyMedium?.copyWith(color: p.textSecondary)),
        const SizedBox(height: AppSpacing.xxl),

        // Profile
        Pressable(
          onTap: _editName,
          scale: 0.985,
          semanticLabel: 'Edit your name',
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: AppRadii.card,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1F2B3E), AppColors.navy900],
              ),
              boxShadow: AppShadows.hero(context),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.emeraldBright, AppColors.emeraldDeep],
                    ),
                    boxShadow: AppShadows.glow(AppColors.emerald, strength: 0.3),
                  ),
                  alignment: Alignment.center,
                  child: settings.userName.isEmpty
                      ? const Icon(Icons.person_outline_rounded, color: Colors.white)
                      : Text(settings.userName[0].toUpperCase(),
                          style: t.titleLarge?.copyWith(color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(settings.userName.isEmpty ? 'Add your name' : settings.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('$count ${count == 1 ? 'transaction' : 'transactions'} · on this device',
                          style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, size: 18, color: Colors.white.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),

        const _GroupLabel('Appearance'),
        _Group(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: SegmentedSwitch<ThemeMode>(
              values: const [ThemeMode.light, ThemeMode.dark, ThemeMode.system],
              selected: settings.themeMode,
              labelOf: (m) => switch (m) {
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
                ThemeMode.system => 'System',
              },
              iconOf: (m) => switch (m) {
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.system => Icons.brightness_auto_outlined,
              },
              onChanged: (m) {
                HapticFeedback.selectionClick();
                ref.read(settingsProvider.notifier).setThemeMode(m);
              },
            ),
          ),
        ]),

        const _GroupLabel('Money'),
        _Group(children: [
          _Tile(icon: Icons.receipt_long_outlined, iconColor: AppColors.emerald,
            title: 'Transaction history', subtitle: 'Search, filter, edit & manage receipts',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(), body: const TransactionsScreen())))),
          _Tile(icon: Icons.bar_chart_outlined, iconColor: AppColors.emerald,
            title: 'Spending insights', subtitle: 'Category breakdown & period comparisons',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(), body: const StatisticsScreen())))),
          _Tile(icon: Icons.analytics_outlined, iconColor: AppColors.emerald,
            title: 'Financial reports', subtitle: 'Filters, charts, PDF & CSV exports',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()))),
          _Tile(icon: Icons.event_note_outlined, iconColor: AppColors.emerald,
            title: 'Planning', subtitle: 'Debts, savings & recurring entries',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlanningScreen()))),
          _Tile(icon: Icons.folder_outlined, iconColor: AppColors.emerald,
            title: 'Projects', subtitle: 'Personal & business project finances',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProjectsScreen()))),
          _Tile(icon: Icons.account_balance_wallet_outlined,
            iconColor: AppColors.emerald, title: 'Wallets',
            subtitle: 'Accounts, balances & transfers',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WalletsScreen()))),
          _Tile(
            icon: Icons.payments_outlined,
            iconColor: const Color(0xFF3B82F6),
            title: 'Reporting currency',
            subtitle: '${currency.name} · totals include only this currency',
            value: '${currency.code} ${currency.symbol}',
            onTap: _pickCurrency,
          ),
          _Tile(
            icon: Icons.track_changes_rounded,
            iconColor: AppColors.emerald,
            title: 'Monthly budget',
            subtitle: settings.hasBudget ? 'Alerts at 80% & 100%' : 'Not set',
            value: settings.hasBudget ? Money.format(settings.monthlyBudgetMinor, currency) : 'Set',
            onTap: () => showBudgetEditor(context),
          ),
          _Tile(
            icon: Icons.donut_large_rounded,
            iconColor: const Color(0xFF8B5CF6),
            title: 'Budget overview',
            subtitle: 'Remaining & categories',
            onTap: () => Navigator.of(context).push(BudgetScreen.route()),
          ),
        ]),

        const _GroupLabel('Privacy & backup'),
        _Group(children: [
          _Tile(icon: Icons.lock_outline, iconColor: AppColors.emerald, title: 'App security', subtitle: 'PIN, biometrics & automatic lock',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SecuritySettingsScreen()))),
          _Tile(icon: Icons.enhanced_encryption_outlined, iconColor: AppColors.emerald, title: 'Encrypted backup & restore', subtitle: 'Portable, passphrase-protected data',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BackupScreen()))),
        ]),
        const _GroupLabel('Data'),
        _Group(children: [
          Builder(
            builder: (tileContext) => _Tile(
              icon: Icons.ios_share_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: 'Export to CSV',
              subtitle: count == 0 ? 'No transactions yet' : '$count transactions',
              trailing: _exporting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _exporting || _clearing ? null : () => _export(tileContext),
            ),
          ),
          _Tile(
            icon: Icons.delete_outline_rounded,
            iconColor: p.expense,
            title: _clearing ? 'Clearing current ledger…' : 'Clear current ledger',
            titleColor: p.expense,
            subtitle: 'Erase everything on this device',
            onTap: _clearing || _exporting ? null : _clearAll,
          ),
        ]),

        const _GroupLabel('About'),
        _Group(children: [
          _Tile(
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.slate500,
            title: 'About ${AppInfo.name}',
            subtitle: 'Version ${AppInfo.version}',
            onTap: () => showAppSheet<void>(context, builder: (_) => const _AboutSheet()),
          ),
        ]),
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Text('Your data never leaves this device.',
              style: t.bodySmall?.copyWith(color: p.textTertiary)),
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 28, 6, 10),
        child: Text(text.toUpperCase(), style: AppTypography.overline(context.palette.textSecondary)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: context.isDark ? p.border : p.border.withValues(alpha: 0.6)),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(indent: 66, endIndent: 16, color: p.border.withValues(alpha: 0.7)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.titleColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final Color? titleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: context.isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: t.titleSmall?.copyWith(
                            color: titleColor ?? p.textPrimary, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: p.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelLarge?.copyWith(color: p.textSecondary)),
                ),
              ],
              const SizedBox(width: 4),
              trailing ?? Icon(Icons.chevron_right_rounded, color: p.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencySheet extends StatelessWidget {
  const _CurrencySheet({required this.current});
  final AppCurrency current;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Reporting currency'),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: p.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Reports include only transactions in the selected currency. Wallet currencies and original amounts never change. No conversion rates are assumed.',
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final c in AppCurrency.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Pressable(
              onTap: () => Navigator.of(context).pop(c),
              semanticLabel: c.name,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c == current
                      ? AppColors.emerald.withValues(alpha: context.isDark ? 0.14 : 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: p.surfaceMuted,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      alignment: Alignment.center,
                      child: Text(c.symbol,
                          style: AppTypography.amount(18, color: p.textPrimary)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: t.titleSmall),
                          Text('${c.code} · ${Money.format(123456, c)}',
                              style: t.bodySmall?.copyWith(color: p.textSecondary)),
                        ],
                      ),
                    ),
                    if (c == current)
                      const Icon(Icons.check_circle_rounded, color: AppColors.emerald),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initial});
  final String initial;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: 'Your name', subtitle: 'Used for your dashboard greeting.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: TextField(
            controller: _c,
            autofocus: true,
            maxLength: 30,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.of(context).pop(v),
            decoration: const InputDecoration(hintText: 'e.g. Alex'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: PrimaryButton(
            label: 'Save',
            height: 52,
            onPressed: () => Navigator.of(context).pop(_c.text),
          ),
        ),
      ],
    );
  }
}

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: context.isDark ? AppColors.emeraldBright : AppColors.emeraldDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall),
                    Text(body, style: t.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          const MoneyTrackLogo(size: 72),
          const SizedBox(height: 16),
          Text(AppInfo.name, style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('Version ${AppInfo.version} · ${AppInfo.tagline}',
              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
          const SizedBox(height: 24),
          point(Icons.lock_outline_rounded, 'Private by design',
              'No accounts, no servers. Everything is stored in a local database on this device.'),
          point(Icons.cloud_off_outlined, 'Works fully offline',
              'MoneyTrack never needs an internet connection.'),
          point(Icons.calculate_outlined, 'Exact accounting',
              'Amounts use integer minor units with the precision of each currency.'),
          const SizedBox(height: 8),
          SecondaryButton(
            label: 'Open-source licenses',
            icon: Icons.article_outlined,
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppInfo.name,
              applicationVersion: AppInfo.version,
              applicationIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: MoneyTrackLogo(size: 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// App mark: emerald tile with a rising "M" stroke.
class MoneyTrackLogo extends StatelessWidget {
  const MoneyTrackLogo({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2B3E), AppColors.navy900],
        ),
        boxShadow: AppShadows.hero(context),
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width * 0.24, s.height * 0.70)
      ..lineTo(s.width * 0.24, s.height * 0.36)
      ..lineTo(s.width * 0.50, s.height * 0.58)
      ..lineTo(s.width * 0.76, s.height * 0.30);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.085
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          colors: [AppColors.emeraldBright, AppColors.emerald],
        ).createShader(Offset.zero & s),
    );
    canvas.drawCircle(Offset(s.width * 0.76, s.height * 0.30), s.width * 0.06,
        Paint()..color = AppColors.emeraldBright);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
