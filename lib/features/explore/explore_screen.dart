import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_shell.dart';
import '../../core/constants/categories.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/ledger_components.dart';
import '../transactions/application/transactions_controller.dart';
import '../wallets/application/wallet_providers.dart';
import '../backup/presentation/backup_screen.dart';
import '../budgets/presentation/budget_screen.dart';
import '../budgets/presentation/wallet_budget_panel.dart';
import '../planning/presentation/planning_screens.dart';
import '../planning/presentation/upcoming_screen.dart';
import '../projects/presentation/projects_screen.dart';
import '../groups/presentation/groups_screen.dart';
import '../reports/presentation/reports_screen.dart';
import '../security/presentation/security_widgets.dart';
import '../settings/presentation/settings_screen.dart';
import '../transactions/application/transaction_filter.dart';
import '../transactions/presentation/transaction_actions.dart';
import '../transactions/presentation/transactions_screen.dart';
import '../wallets/presentation/wallets_screen.dart';
import '../dashboard/presentation/dashboard_screen.dart';

enum MoneyFeature {
  overview('Planning','Available cash','Check cash, reserved savings and wallet spending plans.','dashboard home today available balance budget emergency',Icons.account_balance_outlined),
  wallets(
    'Group Money',
    'Wallets and accounts',
    'Check cash and view each account’s history.',
    'bank cash opening balance archive',
    Icons.account_balance_wallet_outlined,
  ),
  transfer(
    'Group Money',
    'Transfer money',
    'Move cash between your wallets.',
    'send exchange fx rate conversion',
    Icons.swap_horiz,
  ),
  categories(
    'Tools',
    'Categories',
    'Browse income and spending by category.',
    'food salary groceries transport dining',
    Icons.category_outlined,
  ),
  activity(
    'Financial Management',
    'Transactions and receipts',
    'Find an entry to edit it or attach a receipt.',
    'activity history delete undo camera photo pdf search filters',
    Icons.receipt_long_outlined,
  ),
  add(
    'Financial Management',
    'Add a transaction',
    'Record an expense or income.',
    'payment purchase salary deposit entry',
    Icons.add_circle_outline,
  ),
  budget(
    'Planning',
    'Wallet budgets',
    'Set spending limits by wallet, period or category.',
    'daily weekly custom rollover budget planning overspend',
    Icons.donut_large_outlined,
  ),
  monthly(
    'Planning',
    'Monthly spending limit',
    'Track one monthly limit across a reporting currency.',
    'budget alert warning overall',
    Icons.track_changes,
  ),
  savings(
    'Planning',
    'Savings goals',
    'Reserve cash for a goal or emergency fund.',
    'save money saving savings withdrawal contribution weekly replenishment target',
    Icons.savings_outlined,
  ),
  recurring(
    'Planning',
    'Recurring transactions',
    'Schedule repeated entries and review due items.',
    'rent bills salary repeat subscription automatic confirmation',
    Icons.event_repeat,
  ),
  debts(
    'Financial Management',
    'Debts and loans',
    'Track money you owe and money owed to you.',
    'borrowed money borrowing lending lent loan credit repayments principal',
    Icons.handshake_outlined,
  ),
  upcoming(
    'Planning',
    'Upcoming payments',
    'Check due dates and entries awaiting review.',
    'obligations overdue deadlines upcoming bills pending',
    Icons.event_outlined,
  ),
  reminders(
    'Planning',
    'Local reminders',
    'Choose whether Android shows due-date notifications.',
    'notification notify alarm reconcile planning',
    Icons.notifications_outlined,
  ),
  groups('Group Money','Groups & Trips','Collect contributions, track shared purchases and settle refunds.','friends picnic group expenses trip fund football futsal outing shared split reimbursements',Icons.groups_outlined),
  projects(
    'Financial Management',
    'Projects',
    'Track project income, costs and client payments.',
    'business project finances assignments categories contract allocations',
    Icons.folder_outlined,
  ),
  insights(
    'Financial Management',
    'Spending insights',
    'Compare spending and income over time.',
    'analytics statistics trends chart balance categories',
    Icons.bar_chart,
  ),
  reports(
    'Financial Management',
    'Financial reports',
    'Filter financial records and export PDF or CSV.',
    'detailed reports cash flow project summaries print',
    Icons.assessment_outlined,
  ),
  currency(
    'Tools',
    'Reporting currency',
    'Choose the original currency to include in reports.',
    'currency tools afn usd afghani dollar eur pkr jpy kwd',
    Icons.currency_exchange,
  ),
  backup(
    'Tools',
    'Backup and restore',
    'Save or recover an encrypted copy of your ledger.',
    'backup back up restore passphrase recovery import',
    Icons.enhanced_encryption_outlined,
  ),
  security(
    'Application',
    'App security',
    'Manage your PIN, biometrics and automatic lock.',
    'fingerprint password unlock privacy security',
    Icons.lock_outline,
  ),
  export(
    'Tools',
    'Data export',
    'Share transaction history as a CSV spreadsheet.',
    'export csv excel download share',
    Icons.ios_share,
  ),
  appearance('Application','Appearance','Choose light, dark or system theme.','display night mode day theme colors',Icons.contrast_outlined),
  settings(
    'Application',
    'Settings',
    'Change your name, appearance and device preferences.',
    'theme dark mode light system about version clear delete ledger',
    Icons.settings_outlined,
  );

  const MoneyFeature(
    this.group,
    this.title,
    this.description,
    this.terms,
    this.icon,
  );
  final String group, title, description, terms;
  final IconData icon;
  bool get available => true; // All registered tools are bundled offline.
  bool matches(String query) {
    final index = '$title $description $terms $group'.toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(index.contains);
  }

  Future<void> open(BuildContext context, WidgetRef ref) async {
    if (this == add) return TransactionActions.openEditor(context, ref);
    if (this == insights) {
      ref.read(shellTabProvider.notifier).state = 1;
      return;
    }
    final page = switch (this) {
      overview => Scaffold(appBar:AppBar(title:const Text('Available cash')),body:const DashboardScreen()),
      activity => Scaffold(appBar:AppBar(title:const Text('Search all transactions')),body:const TransactionsScreen()),
      wallets => const WalletsScreen(),
      transfer => const TransferScreen(),
      categories => const _CategoriesPage(),
      budget => Scaffold(
        appBar: AppBar(title: const Text('Wallet budgets')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Text(
              'Choose a wallet and set a limit for the expenses you want to track.',
            ),
            SizedBox(height: 12),
            WalletBudgetPanel(),
          ],
        ),
      ),
      monthly => const BudgetScreen(),
      savings => const GoalsScreen(),
      recurring => const RecurringScreen(),
      debts => const DebtsScreen(),
      upcoming => const UpcomingScreen(),
      reminders => const PlanningScreen(),
      groups => const GroupsScreen(),
      projects => const ProjectsScreen(),
      reports => const ReportsScreen(),
      currency => const SettingsScreen(page: SettingsPage.currency),
      backup => const BackupScreen(),
      security => const SecuritySettingsScreen(),
      export => const SettingsScreen(page: SettingsPage.export),
      appearance => const SettingsScreen(page:SettingsPage.appearance),
      settings => const SettingsScreen(),
      _ => throw StateError('Unknown destination'),
    };
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: '/explore/$name'),
        builder: (_) => page,
      ),
    );
  }
}

class _CategoriesPage extends ConsumerWidget {
  const _CategoriesPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Categories')),
    body: ListView(
      children: [
        for (final group in [Categories.expense, Categories.income]) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              group.first.type.isIncome ? 'Income' : 'Expenses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final c in group)
            ListTile(
              leading: Icon(c.icon),
              title: Text(c.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ref.read(transactionFilterProvider.notifier).state =
                    TransactionFilter(categoryIds: {c.id});
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(c.name)),
                      body: const TransactionsScreen(),
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    ),
  );
}

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreState();
}

class _ExploreState extends ConsumerState<ExploreScreen> {
  final _search = TextEditingController();
  final _pins = <MoneyFeature>[], _recent = <MoneyFeature>[];
  late final Future<SharedPreferences?> _prefs;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _prefs = SharedPreferences.getInstance().then<SharedPreferences?>(
      (p) => p,
      onError: (_, _) => null,
    );
    _prefs.then((p) {
      if (!mounted) return;
      List<MoneyFeature> read(String key) => [
        for (final id in p?.getStringList(key) ?? <String>[])
          for (final f in MoneyFeature.values)
            if (f.name == id) f,
      ];
      setState(() {
        _pins.addAll(read('explore.pins'));
        _recent.addAll(read('explore.recent'));
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _store(String key, List<MoneyFeature> list) async {
    final names = list.map((f) => f.name).toList();
    try {
      await (await _prefs)?.setStringList(key, names);
    } on Exception {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Directory preferences could not be saved on this device.',
            ),
          ),
        );
    }
  }

  Future<void> _pin(MoneyFeature f) async {
    await _prefs;
    if (!mounted) return;
    setState(() {
      if (!_pins.remove(f)) _pins.add(f);
    });
    await _store('explore.pins', _pins);
  }

  Future<void> _open(MoneyFeature f) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _prefs;
    if (!mounted) return;
    setState(() {
      _recent.remove(f);
      _recent.insert(0, f);
      if (_recent.length > 3) _recent.removeLast();
    });
    _store('explore.recent', _recent);
    if (mounted) await f.open(context, ref);
  }

  Future<void> _reorder() async {
    final order = [..._pins];
    final result = await showModalBottomSheet<List<MoneyFeature>>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (ctx, update) => Column(
          children: [
            Text('Pinned features', style: Theme.of(ctx).textTheme.titleMedium),
            Expanded(
              child: ListView(
                children: [
                  for (var i = 0; i < order.length; i++)
                    ListTile(
                      title: Text(order[i].title),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Move ${order[i].title} up',
                            onPressed: i == 0
                                ? null
                                : () => update(() {
                                    final item = order.removeAt(i);
                                    order.insert(i - 1, item);
                                  }),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Move ${order[i].title} down',
                            onPressed: i == order.length - 1
                                ? null
                                : () => update(() {
                                    final item = order.removeAt(i);
                                    order.insert(i + 1, item);
                                  }),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(sheet, order),
              child: const Text('Save order'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pins
        ..clear()
        ..addAll(result);
    });
    await _store('explore.pins', result);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final items = MoneyFeature.values.where((f) => f.available && f.matches(query));
    return Scaffold(appBar:AppBar(title:const Text('More'),actions:[IconButton(tooltip:'Quick guide',icon:const Icon(Icons.help_outline),onPressed:()=>showQuickGuide(context))]),body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Find a feature',
              hintText: 'Try trip, borrow, savings or backup',
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          if (query.isEmpty && _pins.isNotEmpty) ...[
            _Heading('Pinned'),
            Wrap(
              spacing: 8,
              children: [
                for (final f in _pins)
                  ActionChip(
                    label: Text(f.title),
                    avatar: Icon(f.icon, size: 16),
                    onPressed: () => _open(f),
                  ),
              ],
            ),
            if (_pins.length > 1)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.reorder),
                  label: const Text('Reorder pins'),
                  onPressed: _reorder,
                ),
              ),
          ],
          if (query.isEmpty && _recent.isNotEmpty) ...[
            _Heading('Recently opened'),
            Wrap(
              spacing: 8,
              children: [
                for (final f in _recent)
                  ActionChip(label: Text(f.title), onPressed: () => _open(f)),
              ],
            ),
          ],
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No matching features. Try a shorter name such as “debt” or “wallet”.',
              ),
            ),
          for (final group in const ['Group Money','Planning','Financial Management','Tools','Application']) if(items.any((f)=>f.group==group)) ...[
            _Heading(group),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for(final f in [if(group=='Group Money' && items.contains(MoneyFeature.groups))MoneyFeature.groups,...items.where((f)=>f.group==group && f!=MoneyFeature.groups)])
                    _FeatureTile(key:ValueKey('feature-${f.name}'),feature:f,pinned:_pins.contains(f),onOpen:()=>_open(f),onPin:_ready?()=>_pin(f):null),

                ],
              ),
            ),
          ],
          if (query.length >= 2) _RecordMatches(query),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({super.key,required this.feature,required this.pinned,required this.onOpen,required this.onPin});
  final MoneyFeature feature;final bool pinned;final VoidCallback onOpen;final VoidCallback? onPin;
  @override Widget build(BuildContext context)=>Column(children:[ListTile(
    contentPadding:const EdgeInsetsDirectional.only(start:12,end:0),
    leading:LedgerGlyph(feature.icon),title:Text(feature.title),subtitle:Text(feature.description),onTap:onOpen,
    trailing:IconButton(tooltip:'${pinned?"Unpin":"Pin"} ${feature.title}',onPressed:onPin,icon:Icon(pinned?Icons.push_pin:Icons.push_pin_outlined,size:18))),
    const Divider(indent:56)
  ]);
}

class _RecordMatches extends ConsumerWidget {
  const _RecordMatches(this.query);
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.toLowerCase();
    final wallets = ref.watch(walletsProvider).valueOrNull?.wallets;
    final accounts = wallets
        ?.where((w) => w.name.toLowerCase().contains(q))
        .take(3);
    final entries = ref
        .watch(allTransactionsProvider)
        .where((t) => '${t.note} ${t.category.name}'.toLowerCase().contains(q))
        .take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (accounts != null && accounts.isNotEmpty) ...[
          const _Heading('Matching wallets'),
          for (final w in accounts)
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(w.name),
              subtitle: Text('${w.type.label} · ${w.currency.code}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => WalletDetailsScreen(walletId: w.id!),
                ),
              ),
            ),
        ],
        if (entries.isNotEmpty) ...[
          const _Heading('Matching transactions'),
          for (final t in entries)
            ListTile(
              leading: const Icon(Icons.receipt_outlined),
              title: Text(t.title),
              subtitle: Text(
                '${Dates.shortDate(t.occurredAt)} · ${Money.format(t.signedMinor, t.currency, signed: true)} ${t.currency.code}',
              ),
              onTap: () => TransactionActions.showActions(context, ref, t),
            ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 3),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );
}

void showQuickGuide(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  builder: (ctx) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    children: [
      Text('Getting started', style: Theme.of(ctx).textTheme.headlineSmall),
      const ListTile(
        leading: Icon(Icons.account_balance_wallet_outlined),
        title: Text('Choose a wallet'),
        subtitle: Text(
          'Open Accounts for balances or search More for available cash.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.add),
        title: Text('Record a payment'),
        subtitle: Text(
          'Use + on Transactions, review the date and account, enter an amount and save.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.search),
        title: Text('Find a tool'),
        subtitle: Text(
          'Search More by what you want to do. Pin a tool to put it first.',
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Got it'),
      ),
    ],
  ),
);
