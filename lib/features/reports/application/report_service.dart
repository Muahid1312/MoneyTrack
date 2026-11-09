import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/project.dart';
import '../../../data/models/planning.dart';
import '../../../data/models/transaction.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/storage/app_runtime.dart';
import '../../projects/domain/project_finance.dart';
import '../../statistics/domain/finance_calculator.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../projects/application/project_providers.dart';
import '../../settings/application/settings_controller.dart';

class ReportFilter {
  const ReportFilter({required this.currency,this.from,this.until,this.walletId,this.projectId,this.category,this.type});
  final AppCurrency currency;final DateTime? from,until;final int? walletId,projectId;final String? category;final TransactionType? type;
  bool matches(TransactionModel t,{bool currencyCheck=true})=>
    (!currencyCheck||t.currency==currency)&&(from==null||!t.occurredAt.isBefore(from!))&&(until==null||t.occurredAt.isBefore(until!))&&
    (walletId==null||t.walletId==walletId)&&(projectId==null||(projectId==-1?t.projectId==null:t.projectId==projectId))&&
    (type==null||t.type==type)&&(category==null||(category!.startsWith('project:')?'project:${t.projectCategoryId}'==category:t.categoryId==category));
}
class ReportData {
  ReportData({required this.filter,required this.transactions,required this.allTransactions,required this.wallets,required this.positions,
    required this.projects,required this.projectCategories,required this.allocations,required this.debts,required this.postings,required this.goals});
  final ReportFilter filter;final List<TransactionModel> transactions,allTransactions;final List<Map<String,Object?>> wallets,positions;
  final List<Project> projects;final List<ProjectCategory> projectCategories;final List<ProjectAllocation> allocations;
  final List<Debt> debts;final List<DebtPosting> postings;final List<SavingsGoal> goals;
  late final Totals totals=FinanceCalculator.totals(transactions);
  late final Map<String,int> categories = _categories();
  Map<String,int> _categories() {
    final names={for(final c in projectCategories)c.id:c.name};final result=<String,int>{};
    for(final t in transactions.where((t)=>t.type.isExpense)){final label=names[t.projectCategoryId]??t.category.name;result[label]=(result[label]??0)+t.amountMinor;}return result;
  }
  late final Map<DateTime,Totals> months = _months();
  Map<DateTime,Totals> _months() {
    final groups=<DateTime,List<TransactionModel>>{};for(final t in transactions){groups.putIfAbsent(DateTime(t.occurredAt.year,t.occurredAt.month),()=>[]).add(t);}
    return {for(final key in groups.keys.toList()..sort())key:FinanceCalculator.totals(groups[key]!)};
  }
  late final Map<int,Totals> years = _years();
  Map<int,Totals> _years() {final groups=<int,List<TransactionModel>>{};for(final t in transactions){groups.putIfAbsent(t.occurredAt.year,()=>[]).add(t);}return {for(final y in groups.keys.toList()..sort())y:FinanceCalculator.totals(groups[y]!)};}
  List<Map<String,Object?>> get selectedPositions=>positions.where((p)=>wallets.any((w)=>w['id']==p['id']&&w['currency']==filter.currency.code)&&(filter.walletId==null||p['id']==filter.walletId)).toList();
  List<Project> get selectedProjects=>projects.where((p)=>p.currency==filter.currency&&(filter.projectId==null||p.id==filter.projectId)).toList();
  final _lifetime=<int,ProjectSummary>{},_period=<int,ProjectSummary>{};
  ProjectSummary lifetime(Project p)=>_lifetime.putIfAbsent(p.id!,()=>ProjectFinance.calculate(p,allTransactions,allocations,projectCategories));
  ProjectSummary period(Project p)=>_period.putIfAbsent(p.id!,()=>ProjectFinance.calculate(p,allTransactions.where((t)=>filter.matches(t,currencyCheck:false)),const [],projectCategories));
  List<Debt> get selectedDebts=>debts.where((d)=>d.currency==filter.currency&&(filter.walletId==null||postings.any((p)=>p.debtId==d.id&&p.origin&&p.walletId==filter.walletId))).toList();
  List<SavingsGoal> get selectedGoals=>goals.where((g)=>g.currency==filter.currency&&(filter.walletId==null||g.walletId==filter.walletId)).toList();
}
final reportFilterProvider=StateProvider<ReportFilter>((ref)=>ReportFilter(currency:ref.read(currencyProvider),from:DateTime(DateTime.now().year),until:DateTime(DateTime.now().year+1)));
final reportDataProvider=FutureProvider<ReportData>((ref) async {
  ref.watch(transactionsProvider);ref.watch(projectsProvider);
  final runtime=ref.watch(appRuntimeProvider);if(runtime==null)throw StateError('Report storage unavailable');final filter=ref.watch(reportFilterProvider);
  return loadReport(runtime,filter);
});
Future<ReportData> loadReport(AppRuntime runtime,ReportFilter filter) {
  return runtime.database.db.transaction((txn) async {
    final all=(await txn.query('transactions',orderBy:'occurred_at DESC,id DESC')).map(TransactionModel.fromMap).toList();
    final postings=(await txn.query('debt_postings',orderBy:'occurred_at DESC,id DESC')).map(DebtPosting.new).toList();
    final events=await txn.query('savings_events');
    return ReportData(filter:filter,transactions:all.where((t)=>filter.matches(t)).toList(),allTransactions:all,
      wallets:await txn.query('wallets'),positions:await txn.query('wallet_positions'),projects:(await txn.query('projects')).map(Project.fromMap).toList(),
      projectCategories:(await txn.query('project_categories')).map(ProjectCategory.fromMap).toList(),allocations:(await txn.query('project_allocations')).map(ProjectAllocation.fromMap).toList(),
      debts:(await txn.query('debts')).map((d)=>Debt(d,postings.where((p)=>p.debtId==d['id']&&!p.origin&&!p.voided).fold<int>(0,(s,p)=>s+p.principalMinor))).toList(),postings:postings,
      goals:(await txn.query('savings_goals')).map((g)=>SavingsGoal(g,events.where((e)=>e['goal_id']==g['id']).fold<int>(0,(s,e)=>s+(e['delta_minor'] as int)))).toList());
  });
}
class ReportDocument {
  const ReportDocument(this.title,this.scope,this.headers,this.rows);final String title,scope;final List<String> headers;final List<List<String>> rows;
}
abstract final class ReportDocuments {
  static ReportDocument build(ReportData data,String kind) {
    final f=data.filter;final scope='${f.currency.code} · ${f.from==null?'All dates':f.from.toString().split(' ').first} to ${f.until==null?'present':DateTime(f.until!.year,f.until!.month,f.until!.day-1).toString().split(' ').first}';
    if(kind=='transactions')return ReportDocument('Transaction history',scope,
      ['id','date','type','description','category','project_category','wallet_id','currency','amount','signed_amount','project_id','project_currency','project_amount','historical_rate','recurring_rule_id','occurrence_date'],
      [for(final t in data.transactions)['${t.id}',t.occurredAt.toIso8601String(),t.type.storageKey,t.note,t.category.name,data.projectCategories.where((c)=>c.id==t.projectCategoryId).firstOrNull?.name??'','${t.walletId}',t.currency.code,Money.plain(t.amountMinor,t.currency),Money.plain(t.signedMinor,t.currency),
        '${t.projectId??''}',t.projectCurrency?.code??'',t.projectAmountMinor==null?'':Money.plain(t.projectAmountMinor!,t.projectCurrency!),t.projectRate??'','${t.recurringRuleId??''}',t.occurrenceDate??'']]);
    if(kind=='projects')return ReportDocument('Project financial report','$scope · Budget and outstanding amounts are lifetime positions; period cash respects filters.',
      ['project_id','name','client_name','type','currency','planned_budget','lifetime_expenses','remaining_budget','period_cash_receipts','period_cash_payments','period_cash_surplus','contract_obligation','outstanding_client_payments','allocated_funding','available_allocation'],
      [for(final p in data.selectedProjects)_projectRow(data,p)]);
    if(kind=='debts')return ReportDocument('Debt and repayment report','$scope · Outstanding principal is current. Debt scope uses the originating wallet; movement history respects dates.',
      ['record_kind','debt_id','contact','debt_type','debt_currency','original_principal','current_outstanding','wallet_id','wallet_currency','wallet_cash_movement','principal_repaid','historical_rate','voided','date','due_date','reference','original_wallet_cash_movement','original_principal_repaid'],
      [for(final d in data.selectedDebts)...[
        ['debt','${d.id}',d.contact,d.borrowed?'borrowed':'lent',d.currency.code,Money.plain(d.principalMinor,d.currency),Money.plain(d.remainingMinor,d.currency),'','','','','','',DateTime.fromMillisecondsSinceEpoch(d.row['created_at'] as int).toIso8601String(),d.dueDate??'','','',''],
        for(final p in data.postings.where((p)=>p.debtId==d.id&&(f.walletId==null||p.walletId==f.walletId)&&(f.from==null||!p.occurredAt.isBefore(f.from!))&&(f.until==null||p.occurredAt.isBefore(f.until!))))
          [p.origin?'origin':'repayment','${d.id}',d.contact,d.borrowed?'borrowed':'lent',d.currency.code,'','','${p.walletId}',p.currency.code,Money.plain(p.voided?0:p.signedMinor,p.currency),p.origin?'':Money.plain(p.voided?0:p.principalMinor,d.currency),p.rate,p.voided?'yes':'no',p.occurredAt.toIso8601String(),d.dueDate??'',p.reference,Money.plain(p.signedMinor,p.currency),p.origin?'':Money.plain(p.principalMinor,d.currency)]
      ]]);
    final t=data.totals;
    return ReportDocument('Financial overview','$scope · Income/expenses exclude transfers, principal and savings reservations. Wallet positions are current.',
      ['record_kind','label','currency','amount','period_or_position'],[
        ['summary','Income',f.currency.code,Money.plain(t.income,f.currency),'Selected period'],['summary','Expenses',f.currency.code,Money.plain(t.expense,f.currency),'Selected period'],['summary','Net cash flow (income minus expenses)',f.currency.code,Money.plain(t.net,f.currency),'Selected period'],
        for(final p in data.selectedPositions)...[
          ['wallet',data.wallets.firstWhere((w)=>w['id']==p['id'])['name'] as String,f.currency.code,Money.plain(p['balance'] as int,f.currency),'Current cash'],
          ['wallet','Reserved savings',f.currency.code,Money.plain(p['reserved'] as int,f.currency),'Current reservation'],
          ['wallet','Available cash',f.currency.code,Money.plain((p['balance'] as int)-(p['reserved'] as int),f.currency),'Current available cash']],
        for(final c in data.categories.entries)['category',c.key,f.currency.code,Money.plain(c.value,f.currency),'Selected period expenses'],
        for(final m in data.months.entries)...[
          ['month','Income',f.currency.code,Money.plain(m.value.income,f.currency),'${m.key.year}-${m.key.month.toString().padLeft(2,'0')}'],
          ['month','Expenses',f.currency.code,Money.plain(m.value.expense,f.currency),'${m.key.year}-${m.key.month.toString().padLeft(2,'0')}'],
          ['month','Net cash flow',f.currency.code,Money.plain(m.value.net,f.currency),'${m.key.year}-${m.key.month.toString().padLeft(2,'0')}']],
        for(final y in data.years.entries)['year','Net cash flow',f.currency.code,Money.plain(y.value.net,f.currency),'${y.key}'],
        for(final d in data.selectedDebts)['debt',d.borrowed?'Principal owed: ${d.contact}':'Principal receivable: ${d.contact}',d.currency.code,Money.plain(d.remainingMinor,d.currency),'Current principal'],
        for(final g in data.selectedGoals)['savings',g.name,g.currency.code,Money.plain(g.allocatedMinor,g.currency),'Current reserved savings (already in wallet cash)']
      ]);
  }
  static List<String> _projectRow(ReportData data,Project p){final life=data.lifetime(p),period=data.period(p);String value(int? n)=>n==null?'':Money.plain(n,p.currency);
    return ['${p.id}',p.name,p.clientName,p.type.name,p.currency.code,value(p.budgetMinor),value(life.expenses),value(life.remainingBudget),value(period.receipts),value(period.expenses),value(period.cashSurplus),value(p.contractMinor),value(life.outstanding),value(life.allocated),value(life.availableAllocation)];}
}
