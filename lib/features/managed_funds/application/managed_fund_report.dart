import '../../../core/utils/money.dart';
import '../../../data/repositories/managed_fund_repository.dart';
import '../../reports/application/report_service.dart';
import '../domain/managed_fund.dart';

ReportDocument managedFundReport(
  ManagedFundDetail detail, {
  required bool dari,
}) {
  final ledger = detail.ledger;
  final fund = ledger.fund;
  String tr(String en, String fa) => dari ? fa : en;
  String money(int minor) =>
      '${Money.plain(minor, fund.currency)} ${fund.currency.code}';
  String date(DateTime value) => value.toIso8601String().split('T').first;
  String status(FundStatus value) => switch (value) {
    FundStatus.active => tr('Active', 'فعال'),
    FundStatus.settlementPending => tr('Settlement pending', 'در انتظار تصفیه'),
    FundStatus.completed => tr('Completed', 'تکمیل شده'),
    FundStatus.cancelled => tr('Cancelled', 'لغو شده'),
  };
  String action(FundEventKind kind) => switch (kind) {
    FundEventKind.funding => tr('Funding', 'دریافت پول'),
    FundEventKind.purchase => tr('Purchase', 'خرید'),
    FundEventKind.refund => tr('Merchant refund', 'بازپرداخت فروشنده'),
    FundEventKind.reimburseDirect => tr(
      'Direct reimbursement',
      'بازپرداخت مستقیم',
    ),
    FundEventKind.reimburseCash => tr(
      'Fund reimbursement',
      'بازپرداخت از پول امانتی',
    ),
    _ => tr('Reversal', 'برگشت ثبت'),
  };
  return ReportDocument(
    tr('Managed fund activity', 'گزارش پول امانتی'),
    [
      fund.name,
      '${tr('Provided by', 'تأمین‌کننده')}: ${fund.provider}',
      '${date(fund.opened)} · ${fund.currency.code} · ${status(fund.status)}',
      '${tr('Received', 'دریافت شده')} ${money(ledger.received)}',
      '${tr('Spent', 'مصرف شده')} ${money(ledger.expenses)}',
      '${tr('Entrusted cash', 'موجودی امانتی')} ${money(ledger.cash)}',
      '${tr('Outstanding advances', 'پیش‌پرداخت باقی‌مانده')} ${money(ledger.outstanding)}',
    ].join('\n'),
    [
      tr('Date', 'تاریخ'),
      tr('Record', 'ثبت'),
      tr('Description', 'توضیحات'),
      tr('Amount', 'مبلغ'),
    ],
    [
      for (final event in ledger.events) ...[
        [
          date(event.date),
          '#${event.id} · ${action(event.kind)}',
          [
            event.party,
            event.method,
            if (event.note.isNotEmpty) event.note,
            if (event.target != null) '#${event.target}',
            if (ledger.reversed(event.id)) tr('Reversed', 'برگشت شده'),
            if (event.kind == FundEventKind.purchase)
              '${tr('Entrusted', 'امانتی')} ${money(event.cash)} · ${tr('Personal', 'شخصی')} ${money(event.personal)}',
          ].join(' · '),
          money(event.total),
        ],
        for (final item in detail.items[event.id] ?? const <PurchaseLine>[])
          [
            date(event.date),
            '#${event.id}',
            [
              item.name,
              if (item.quantityMilli != null)
                '${PurchaseLine.formatQuantity(item.quantityMilli!)} ${item.unit} × ${money(item.unitMinor!)}',
            ].join(' · '),
            money(item.total),
          ],
      ],
    ],
    rightToLeft: dari,
  );
}
