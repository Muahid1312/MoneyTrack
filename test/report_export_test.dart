import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/features/reports/application/report_service.dart';
import 'package:moneytrack/features/reports/application/report_exporter.dart';
import 'support/phase4_fixture.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();late Phase4Fixture f;
  setUp(() async {f=Phase4Fixture();await f.open();await f.seed();});tearDown(() async {await f.close();});
  test('operating totals exclude debt principal and savings reservations and count project entries once',() async {
    final report=await loadReport(f.runtime,const ReportFilter(currency:AppCurrency.usd));
    expect(report.totals.income,3000);expect(report.totals.expense,650);expect(report.totals.net,2350);
    final cash=report.selectedPositions.single;expect(cash['balance'],103150);expect(cash['reserved'],2000);
    expect(report.selectedDebts.single.remainingMinor,800);expect(report.selectedGoals.single.allocatedMinor,2000);
  });
  test('currency, date, wallet, category, type and project filters are exact',() async {
    final foreign=await loadReport(f.runtime,const ReportFilter(currency:AppCurrency.afn));expect(foreign.totals.count,0);
    expect(foreign.selectedProjects.single.currency,AppCurrency.afn);expect(foreign.lifetime(foreign.selectedProjects.single).expenses,7000);
    final day=await loadReport(f.runtime,ReportFilter(currency:AppCurrency.usd,from:DateTime(2026,1,2),until:DateTime(2026,1,3),walletId:1,category:'salary',type:TransactionType.income));expect(day.totals.income,1000);expect(day.totals.expense,0);
    final home=(await loadReport(f.runtime,const ReportFilter(currency:AppCurrency.usd))).projects.firstWhere((p)=>p.name=='Home');
    final project=await loadReport(f.runtime,ReportFilter(currency:AppCurrency.usd,projectId:home.id));expect(project.totals.expense,300);
  });
  test('all export rows match stable headers; CSV preserves exact amounts, quotes and Unicode',() async {
    final data=await loadReport(f.runtime,const ReportFilter(currency:AppCurrency.usd));
    for(final kind in ['overview','transactions','projects','debts']){
      final doc=ReportDocuments.build(data,kind);expect(doc.rows.every((row)=>row.length==doc.headers.length),isTrue,reason:kind);
      expect(ReportExporter.csv(doc),startsWith('\uFEFF'));}
    final csv=ReportExporter.csv(const ReportDocument('Test','USD',['description','amount','currency'],[['Lunch, "team"\nرسید','1.05','USD'],['=SUM(A1:A2)','-0.01','USD']]));
    expect(csv,contains('"Lunch, ""team""\nرسید"'));expect(csv,contains("'=SUM(A1:A2)"));expect(csv,contains(',-0.01,USD'));
  });
  test('PDF output is A4, numbered and multi-page with long Unicode text',() async {
    final document=ReportDocument('Financial report','AFN · 2026-01-01',['description','amount','currency'],[
      for(var i=0;i<3;i++)['${List.filled(200,'رسید ؋ long text ').join()}\nSecond line','123.45','AFN']]);
    final bytes=await ReportExporter.pdf(document);expect(ascii.decode(bytes.take(5).toList()),'%PDF-');
    final structure=latin1.decode(bytes);expect(RegExp(r'/Type\s*/Page\b').allMatches(structure).length,greaterThan(1));
  },timeout:const Timeout(Duration(minutes:2)));
  test('oversized PDF result is rejected without silently truncating records',() async {
    final doc=ReportDocument('Large','USD',['id'],[for(var i=0;i<1001;i++)['$i']]);
    await expectLater(ReportExporter.pdf(doc),throwsStateError);
  });
}
