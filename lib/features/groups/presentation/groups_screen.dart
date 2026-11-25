import '../../../core/widgets/finance_hero.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide DataRow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ledger_components.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/storage/access_guard.dart';
import '../../reports/application/report_exporter.dart';
import '../application/group_providers.dart';
import '../application/group_report.dart';
import '../domain/group_fund.dart';
import 'group_forms.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    void open(int id) => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => GroupDetails(id)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Groups & Trips')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New group'),
        onPressed: () async {
          final id = await Navigator.push<int>(
            context,
            MaterialPageRoute(
              builder: (_) => const TripForm(TripFormMode.create),
            ),
          );
          if (context.mounted && id != null) open(id);
        },
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(groupsProvider),
            child: const Text('Retry loading groups'),
          ),
        ),
        data: (rows) => rows.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Create a group to collect contributions, record purchases and return the money left over.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  return _FundRow(row:r,open:()=>open(r['id'] as int));

                },
              ),
      ),
    );
  }
}

class _FundRow extends ConsumerWidget {
  const _FundRow({required this.row,required this.open});
  final DataRow row;final VoidCallback open;
  @override Widget build(BuildContext context,WidgetRef ref){
    final id=row['id'] as int,fund=ref.watch(groupProvider(id));
    return Material(color:context.palette.surface,child:InkWell(onTap:open,child:Padding(padding:const EdgeInsets.fromLTRB(14,12,14,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const LedgerGlyph(Icons.groups_outlined),const SizedBox(width:10),Expanded(child:Text(row['name'] as String,style:Theme.of(context).textTheme.titleMedium)),const Icon(Icons.chevron_right,size:18)]),
      fund.when(loading:()=>const LinearProgressIndicator(),error:(e,st)=>TextButton(onPressed:()=>ref.invalidate(groupProvider(id)),child:const Text('Retry group balances')),data:(g)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Wrap(spacing:8,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,children:[StatusLabel(g.stage.label,positive:g.stage==TripStage.completed),Text('${g.roster.length} members · ${g.currency.code} · ${Dates.shortDate(DateTime.fromMillisecondsSinceEpoch(row['project_date'] as int))}',style:Theme.of(context).textTheme.bodySmall)])),
        FinancialSummary([(label:'Collected',value:Money.format(g.collected,g.currency),color:null),(label:'Cash remaining',value:Money.format(g.cash,g.currency),color:g.cash<0?context.palette.expense:null)])
      ]))
    ]))));
  }
}

class GroupDetails extends ConsumerWidget {
  const GroupDetails(this.id, {super.key});
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(groupProvider(id))
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, s) => Scaffold(
          appBar: AppBar(title: const Text('Group')),
          body: Center(
            child: TextButton(
              onPressed: () => ref.invalidate(groupProvider(id)),
              child: const Text('Retry loading group'),
            ),
          ),
        ),
        data: (g) => DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text(g.name),
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Members'),
                  Tab(text: 'Expenses'),
                  Tab(text: 'Settlement'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                for (final tab in [0, 1, 2, 3]) _GroupSection(g, tab),
              ],
            ),
          ),
        ),
      );
}

class _GroupSection extends ConsumerWidget {
  const _GroupSection(this.g, this.tab);
  final GroupFund g;
  final int tab;
  String money(int n) => Money.format(n, g.currency);
  void form(BuildContext c, TripForm f) =>
      Navigator.push(c, MaterialPageRoute<int>(builder: (_) => f));
  void action(
    BuildContext c,
    EntryKind k,
    String title, {
    int? related,
    Map<int, int> plan = const {},
  }) => form(
    c,
    TripForm(
      TripFormMode.action,
      group: g,
      kind: k,
      title: title,
      related: related,
      plan: plan,
    ),
  );
  void pay(
    BuildContext c,
    EntryKind k,
    String title,
    int n, {
    int? m,
    int? link,
  }) => form(
    c,
    TripForm(
      TripFormMode.payment,
      group: g,
      kind: k,
      title: title,
      member: m,
      related: link,
      initialAmount: n,
    ),
  );
  Widget button(String text, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(text),
      );
  Widget heading(BuildContext c, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
    child: Text(title, style: Theme.of(c).textTheme.titleMedium),
  );
  Widget stat(String name, int n) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 8,
      children: [
        Text(name),
        Text(money(n),textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
  Widget summary(BuildContext c)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Padding(padding:const EdgeInsets.only(bottom:8),child:Wrap(spacing:8,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,children:[StatusLabel(g.stage.label,positive:g.stage==TripStage.completed),Text('${g.roster.length} members · ${g.currency.code}',style:Theme.of(c).textTheme.bodySmall)])),
    FinanceHero(label: 'Group cash · ${g.currency.code}', amount: money(g.cash), details: [(label: 'Collected', value: money(g.collected)), (label: 'Spent', value: money(g.spent))]),
    const SizedBox(height: 10),
  ]);
  Widget obligationSummary(BuildContext c)=>Column(children:[
    stat('Reimbursements due',g.owed(EntryKind.memberExpense)),stat('Other unpaid bills',g.owed(EntryKind.liability)),
    const Divider(),stat(g.surplus<0?'Deficit':'Available for refunds',g.surplus.abs())
  ]);
  Widget activity(BuildContext c, int id, TripEntry e) {
    final amount = e.amount > 0 ? e.amount : g.events[e.related]?.amount;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(e.label.isEmpty ? e.kind.label : e.label),
      subtitle: Text(
        [
          Dates.shortDate(e.at),
          if(e.kind.purchase)e.category,
          e.kind.label,
          if (e.member != null) g.members[e.member]!.name,
          if (g.reversed.contains(id)) 'Reversed',
        ].join(' · '),
      ),
      trailing: amount == null ? null : Text(money(amount)),
      onTap: () => showEvent(c, id, e),
    );
  }

  void showEvent(BuildContext context, int id, TripEntry e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            e.label.isEmpty ? e.kind.label : e.label,
            style: Theme.of(sheet).textTheme.titleLarge,
          ),
          Text(
            '#$id · ${e.kind.label} · ${Dates.shortDate(e.at)} ${TimeOfDay.fromDateTime(e.at).format(sheet)}',
          ),
          if (e.amount > 0 || e.kind == EntryKind.cashCount)
            stat('Amount', e.amount),
          if (e.kind == EntryKind.cashCount)
            stat('Difference when counted', g.countVariances[id]!),
          if (e.member != null) Text(g.members[e.member]!.name),
          if (e.related != null) Text('Linked entry #${e.related}'),
          if (e.category.isNotEmpty) Text(e.category),
          if (e.method.isNotEmpty) Text(e.method),
          if (e.note.isNotEmpty) Text(e.note),
          if (e.quantity != null)
            Text('${quantityText(e.quantity!)} × ${money(e.unit!)}'),
          if (e.kind.purchase) _GroupImage(g.id, id),
          if (e.kind == EntryKind.confirm)
            for (final a in e.allocation.entries)
              stat(g.members[a.key]!.name, a.value),
          if (g.reversed.contains(id))
            const Text('Reversed. The original record is retained.'),
          if (!g.reversed.contains(id) &&
              g.editable &&
              (e.kind.purchase || e.kind == EntryKind.contribution))
            button('Correct entry', Icons.edit_outlined, () {
              Navigator.pop(sheet);
              form(
                context,
                TripForm(
                  e.kind.purchase
                      ? TripFormMode.expense
                      : TripFormMode.contribution,
                  group: g,
                  original: id,
                ),
              );
            }),
          if (!g.reversed.contains(id) &&
              g.editable &&
              (e.kind.purchase ||
                  [
                    EntryKind.contribution,
                    EntryKind.reimburse,
                    EntryKind.payBill,
                  ].contains(e.kind)))
            button('Reverse with reason', Icons.undo, () {
              Navigator.pop(sheet);
              action(context, EntryKind.reverse, 'Reverse entry', related: id);
            }),
        ],
      ),
    );
  }

  Widget member(BuildContext c, WidgetRef ref, TripMember m) {
    final history = g.events.entries.where(
      (e) =>
          e.value.member == m.id ||
          (e.value.related != null &&
              g.events[e.value.related]?.member == m.id),
    );
    final paid = g.net[m.id] ?? 0, due = g.memberDue(m);
    return Card(child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(m.name),
      subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Paid ${money(paid)} · Expected ${money(m.expected)}'),
        StatusLabel(m.expected==0?'No target':due==0?'Fully paid':paid==0?'Unpaid':'Partially paid',positive:due==0 && m.expected>0)
      ]),
      children: [
        stat('Expected', m.expected),
        stat('Remaining contribution', due),
        stat('Refunds paid', g.paid[m.id] ?? 0),
        if (g.frozen) stat('Refund still due', g.dueRefund(m.id)),
        if (g.editable)
          Wrap(
            spacing: 8,
            children: [
              button(
                'Add contribution',
                Icons.add,
                () => form(
                  c,
                  TripForm(TripFormMode.contribution, group: g, member: m.id),
                ),
              ),
              button(
                'Edit member',
                Icons.edit_outlined,
                () => form(
                  c,
                  TripForm(TripFormMode.member, group: g, member: m.id),
                ),
              ),
              if (history.isEmpty && g.roster.length > 1)
                button('Remove', Icons.person_remove_outlined, () async {
                  final ok = await showDialog<bool>(
                    context: c,
                    builder: (d) => AlertDialog(
                      title: Text('Remove ${m.name}?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Keep'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !c.mounted) return;
                  try {
                    await ref
                        .read(groupRepositoryProvider)!
                        .member(
                          g.id,
                          id: m.id,
                          name: m.name,
                          expected: m.expected,
                          remove: true,
                        );
                    if (c.mounted) ref.invalidate(groupProvider(g.id));
                  } catch (e) {
                    if (c.mounted) {
                      ScaffoldMessenger.of(c).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is FundError
                                ? e.message
                                : 'Could not remove member.',
                          ),
                        ),
                      );
                    }
                  }
                }),
            ],
          ),
        for (final e in history.toList().reversed) activity(c, e.key, e.value),
      ],
    ));
  }

  List<Widget> settlement(BuildContext c) {
    Map<int, int> plan = g.allocation;
    String? error;
    if (!g.frozen) {
      try {
        plan = g.preview();
      } on FundError catch (e) {
        error = e.message;
      }
    }
    return [
      summary(c),
      obligationSummary(c),
      if (g.stage != TripStage.completed)
        button(
          'Count group cash',
          Icons.calculate_outlined,
          () => form(
            c,
            TripForm(
              TripFormMode.payment,
              group: g,
              kind: EntryKind.cashCount,
              title: 'Count group cash',
            ),
          ),
        ),
      if (g.countVariances.isNotEmpty)
        Text('Last count difference · ${money(g.countVariances.values.last)}'),
      heading(c, 'Reimbursements and bills'),
      if (g.obligations.values.every((a) => a == 0))
        const Text('No outstanding payments.'),
      for (final o in g.obligations.entries.where((e) => e.value > 0))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(g.events[o.key]!.label),
          subtitle: Text(
            '${g.members[g.events[o.key]!.member]?.name ?? "Unpaid bill"} · ${money(o.value)} due',
          ),
          trailing: TextButton(
            onPressed: () => pay(
              c,
              g.events[o.key]!.kind == EntryKind.memberExpense
                  ? EntryKind.reimburse
                  : EntryKind.payBill,
              'Record payment',
              o.value,
              m: g.events[o.key]!.member,
              link: o.key,
            ),
            child: const Text('Pay'),
          ),
        ),
      heading(c, g.frozen ? 'Confirmed refunds' : 'Refund preview'),
      if(plan.isNotEmpty)Text(g.frozen?'Record each refund when the member receives it.':'Each member’s share is based on their actual contribution.',style:Theme.of(c).textTheme.bodySmall),
      if (error != null) Text(error),
      if (error == null)
        for (final m in g.roster)
          Builder(
            builder: (_) {
              final allocated = plan[m.id] ?? 0,
                  paid = g.paid[m.id] ?? 0,
                  remaining = allocated - paid;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.name),
                subtitle: Text(
                  g.frozen
                      ? '${remaining == 0
                            ? (allocated == 0 ? "No refund" : "Paid")
                            : paid > 0
                            ? "Partially paid"
                            : "Pending"} · ${money(paid)} paid'
                      : 'Contributed ${money(g.net[m.id] ?? 0)}',
                ),
                trailing:
                    g.stage == TripStage.settlement &&
                        !g.unmatchedCount &&
                        remaining > 0
                    ? TextButton(
                        onPressed: () => pay(
                          c,
                          EntryKind.refund,
                          'Record refund',
                          remaining,
                          m: m.id,
                        ),
                        child: Text('Pay ${money(remaining)}'),
                      )
                    : Text(money(allocated)),
              );
            },
          ),
      if (!g.frozen && error == null)
        FilledButton(
          onPressed: () => action(
            c,
            EntryKind.confirm,
            'Confirm settlement plan',
            plan: plan,
          ),
          child: const Text('Review and confirm plan'),
        ),
      if (g.stage == TripStage.settlement)
        FilledButton(
          onPressed:
              !g.unmatchedCount &&
                  g.cash == 0 &&
                  g.obligations.values.every((v) => v == 0)
              ? () => action(c, EntryKind.complete, 'Complete group')
              : null,
          child: const Text('Complete group'),
        ),
      if (g.frozen || g.stage == TripStage.cancelled)
        button(
          'Reopen with reason',
          Icons.history,
          () => action(c, EntryKind.reopen, 'Reopen group'),
        ),
      if (g.editable)
        for (final e in g.paid.entries.where((e) => e.value > 0))
          button(
            'Record refund returned by ${g.members[e.key]!.name}',
            Icons.undo,
            () => pay(
              c,
              EntryKind.returnRefund,
              'Record refund returned',
              e.value,
              m: e.key,
            ),
          ),
      heading(c, 'Financial report'),
      Wrap(
        spacing: 8,
        children: [
          button(
            'Share PDF',
            Icons.picture_as_pdf_outlined,
            () => share(c, 'pdf'),
          ),
          button('Share CSV', Icons.table_view_outlined, () => share(c, 'csv')),
          button('Share summary', Icons.share_outlined, () => share(c, 'text')),
        ],
      ),
    ];
  }

  Future<void> share(BuildContext c, String format) async {
    try {
      AccessGuard.writable();
      final report = GroupReport(g);
      if (format != 'text') {
        await ReportExporter.share(
          await ReportExporter.write(report.document, format == 'pdf'),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(text: report.summary, subject: g.name),
        );
      }
    } catch (e) {
      if (c.mounted) {
        ScaffoldMessenger.of(c).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Could not share the report. Try the text summary.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    const padding = EdgeInsets.fromLTRB(16, 12, 16, 32);
    final key = PageStorageKey('group-${g.id}-$tab');
    if (tab == 1) {
      final members = g.roster.toList();
      return ListView.builder(
        key: key,
        padding: padding,
        itemCount: members.length + 1,
        itemBuilder: (c, i) {
          if (i == 0) {
            return g.editable
                ? button(
                    'Add member',
                    Icons.person_add_outlined,
                    () => form(c, TripForm(TripFormMode.member, group: g)),
                  )
                : const SizedBox.shrink();
          }
          return member(c, ref, members[i - 1]);
        },
      );
    }
    if (tab == 2 || tab == 4) {
      final rows = g.events.entries
          .where((e) => tab == 4 || e.value.kind.purchase)
          .toList()
          .reversed
          .toList();
      return ListView.builder(
        key: key,
        padding: padding,
        itemCount: rows.length + 1,
        itemBuilder: (c, i) {
          if (i > 0) {
            final r = rows[i - 1];
            return activity(c, r.key, r.value);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tab == 2 && g.editable)
                button(
                  'Add expense',
                  Icons.add,
                  () => form(c, TripForm(TripFormMode.expense, group: g)),
                ),
              if (rows.isEmpty)
                const Text(
                  'No entries yet. Record who paid when you add a purchase.',
                ),
            ],
          );
        },
      );
    }
    return ListView(
      key: key,
      padding: padding,
      children: switch (tab) {
        0 => [
          summary(c),
          Wrap(
            spacing: 8,
            children: [
              if(g.editable)FilledButton.icon(onPressed:()=>form(c,TripForm(TripFormMode.contribution,group:g)),icon:const Icon(Icons.add,size:18),label:const Text('Add contribution')),
              if(g.editable)button('Add expense',Icons.shopping_basket_outlined,()=>form(c,TripForm(TripFormMode.expense,group:g))),
              button(
                'View members',
                Icons.groups_outlined,
                () => DefaultTabController.of(c).animateTo(1),
              ),
              button(
                'Settle project',
                Icons.balance,
                () => DefaultTabController.of(c).animateTo(3),
              ),
            ],
          ),
          heading(c,'Fund balance'),
          obligationSummary(c),
          heading(c, 'Recent activity'),
          if (g.events.isEmpty)
            const Text('Add the first contribution when you collect money.'),
          for (final r in g.events.entries.toList().reversed.take(6))
            activity(c, r.key, r.value),
          if (g.events.isNotEmpty)
            button(
              'Full history',
              Icons.history,
              () => Navigator.push(
                c,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Group history')),
                    body: Consumer(
                      builder: (ctx, ref, _) => ref
                          .watch(groupProvider(g.id))
                          .when(
                            data: (fresh) => _GroupSection(fresh, 4),
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, st) => TextButton(
                              onPressed: () =>
                                  ref.invalidate(groupProvider(g.id)),
                              child: const Text('Retry loading history'),
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          heading(c,'Contribution plan'),stat('Expected contributions',g.expected),stat('Unpaid contributions',g.outstanding),
          if(g.project['budget_minor']!=null)stat('Planned budget',g.project['budget_minor'] as int),
          heading(c, 'Group details'),
          Text(
            Dates.shortDate(
              DateTime.fromMillisecondsSinceEpoch(
                g.project['project_date'] as int,
              ),
            ),
          ),
          for (final key in ['location', 'description'])
            if ((g.project[key] as String).isNotEmpty)
              Text(g.project[key] as String),
          _GroupImage(g.id, null),
          if (g.stage == TripStage.planning)
            button(
              'Start group',
              Icons.play_arrow,
              () => action(c, EntryKind.activate, 'Start group'),
            ),
          if (g.editable)
            TextButton(
              onPressed: () => action(c, EntryKind.cancel, 'Cancel group'),
              child: const Text('Cancel group'),
            ),
        ],
        _ => settlement(c),
      },
    );
  }
}

final _imageProvider = FutureProvider.autoDispose
    .family<Uint8List?, (int, int?)>(
      (ref, key) => ref.watch(groupRepositoryProvider)!.image(key.$1, key.$2),
    );

class _GroupImage extends ConsumerWidget {
  const _GroupImage(this.group, this.event);
  final int group;
  final int? event;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final bytes = ref.watch(_imageProvider((group, event))).valueOrNull;
    if (bytes == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.image_outlined),
        label: Text(event == null ? 'View group photo' : 'View receipt'),
        onPressed: () => showDialog<void>(
          context: c,
          builder: (d) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
