import '../../../core/utils/money.dart';
import '../../../core/utils/date_utils.dart';
import '../../reports/application/report_service.dart';
import '../domain/group_fund.dart';

class GroupReport {
  GroupReport(this.group);
  final GroupFund group;
  String money(int n) =>
      '${Money.plain(n, group.currency)} ${group.currency.code}';
  String get summary {
    final g = group;
    return [
      '${g.name} · ${Dates.shortDate(DateTime.fromMillisecondsSinceEpoch(g.project['project_date'] as int))}',
      '${g.stage.label} · ${g.roster.length} members',
      'Expected ${money(g.expected)} · Collected ${money(g.collected)}',
      'Spent ${money(g.spent)} · Cash left ${money(g.cash)}',
      'Reimbursements due ${money(g.owed(EntryKind.memberExpense))} · Bills due ${money(g.owed(EntryKind.liability))}',
      'Refunds paid (net) ${money(g.refunded)} · ${g.surplus < 0 ? 'Deficit' : 'Available after obligations'} ${money(g.surplus.abs())}',
    ].join('\n');
  }

  ReportDocument get document {
    final g = group;
    final rows = <List<String>>[];
    final categories = <String, int>{};
    for (final row in g.events.entries) {
      final e = row.value;
      if (e.kind.purchase && !g.reversed.contains(row.key)) {
        categories.update(
          e.category,
          (v) => v + e.amount,
          ifAbsent: () => e.amount,
        );
      }
    }
    for (final category in categories.entries) {
      rows.add(['Expense category', category.key, money(category.value)]);
    }
    rows.add(['Reimbursements', 'Paid to members', money(g.reimbursed)]);
    for (final m in g.roster) {
      rows.add([
        'Member',
        m.name,
        'Expected ${money(m.expected)} · Paid in ${money(g.net[m.id] ?? 0)} · Outstanding ${money(g.memberDue(m))} · Refund allocation ${g.frozen ? money(g.allocation[m.id] ?? 0) : "unconfirmed"} · Refunds paid ${money(g.paid[m.id] ?? 0)}',
      ]);
    }
    for (final row in g.events.entries) {
      final e = row.value;
      final detail = [
        if (e.member != null) g.members[e.member]!.name,
        if (e.category.isNotEmpty) e.category,
        if (e.label.isNotEmpty) e.label,
        if (e.amount > 0 || e.kind == EntryKind.cashCount) money(e.amount),
        if (e.kind == EntryKind.cashCount)
          'Difference ${money(g.countVariances[row.key]!)}',
        if (e.quantity != null)
          '${quantityText(e.quantity!)} × ${money(e.unit!)}',
        if (e.method.isNotEmpty) e.method,
        if (e.related != null) 'Linked entry #${e.related}',
        if (e.note.isNotEmpty) e.note,
        if (e.kind == EntryKind.confirm)
          for (final a in e.allocation.entries)
            '${g.members[a.key]!.name} ${money(a.value)}',
        if (g.reversed.contains(row.key)) 'Reversed',
      ].join(' · ');
      rows.add(['#${row.key} ${Dates.shortDate(e.at)}', e.kind.label, detail]);
    }
    return ReportDocument(g.name, summary, [
      'Record',
      'Name or action',
      'Details',
    ], rows);
  }
}
