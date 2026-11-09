import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/models/project.dart';
import 'package:moneytrack/data/models/transaction.dart';
import 'package:moneytrack/data/models/transaction_type.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'package:moneytrack/data/repositories/project_repository.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/planning/domain/schedule.dart';
import 'package:moneytrack/features/projects/domain/project_finance.dart';
import 'package:moneytrack/features/statistics/domain/finance_calculator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();sqfliteFfiInit();
  group('Civil recurring schedules',(){
    test('daily and weekly use calendar dates',(){
      expect(CivilSchedule.key(CivilSchedule.at(DateTime(2026,3,7),'daily',2)),'2026-03-09');
      expect(CivilSchedule.key(CivilSchedule.at(DateTime(2026,3,7),'weekly',2)),'2026-03-21');
    });
    test('monthly preserves the original month-end anchor',(){
      final anchor=DateTime(2026,1,31);
      expect([for(var i=0;i<4;i++)CivilSchedule.key(CivilSchedule.at(anchor,'monthly',i))],
        ['2026-01-31','2026-02-28','2026-03-31','2026-04-30']);
    });
    test('yearly leap-day schedules recover February 29 in leap years',(){
      expect(CivilSchedule.key(CivilSchedule.at(DateTime(2024,2,29),'yearly',1)),'2025-02-28');
      expect(CivilSchedule.key(CivilSchedule.at(DateTime(2024,2,29),'yearly',4)),'2028-02-29');
      expect(()=>CivilSchedule.parse('2026-02-29'),throwsFormatException);
    });
    test('nominal occurrence dates survive timezone/epoch differences',(){
      final model=TransactionModel.fromMap({'id':1,'wallet_id':1,'currency':'USD','type':'income','amount_minor':100,
        'category_id':'salary','occurred_at':DateTime.utc(2026,1,30,18).millisecondsSinceEpoch,'created_at':0,'updated_at':0,
        'recurring_rule_id':1,'occurrence_date':'2026-01-31'});
      expect(CivilSchedule.key(model.occurredAt),'2026-01-31');
    });
  });
  group('Phase 3 financial operations',(){
    late Directory dir;late AppDatabase db;late PlanningRepository planning;late WalletRepository wallets;late SqfliteTransactionRepository transactions;
    setUp(() async {dir=await Directory.systemTemp.createTemp('planning-test-');db=await AppDatabase.open(factory:databaseFactoryFfi,path:'${dir.path}/ledger.db');
      planning=PlanningRepository(db);wallets=WalletRepository(db);transactions=SqfliteTransactionRepository(db);});
    tearDown(() async {await db.close();await dir.delete(recursive:true);});
    Future<void> fund(int minor)=>wallets.save(Wallet(id:1,name:'Main',type:WalletType.cash,currency:AppCurrency.usd,openingMinor:minor));
    TransactionModel entry(int minor,{TransactionType type=TransactionType.expense})=>TransactionModel(type:type,amountMinor:minor,categoryId:type.isIncome?'salary':'food',occurredAt:DateTime(2026),createdAt:DateTime(2026),updatedAt:DateTime(2026));
    Future<int> rule({bool automatic=false,TransactionType type=TransactionType.income,String start='2026-01-01',String? end,String frequency='daily',int amount=100,int? id,int? projectId,String? rate})=>planning.saveRule(id:id,ruleName:'Schedule',type:type,amountMinor:amount,walletId:1,categoryId:type.isIncome?'salary':'food',frequency:frequency,startDate:start,endDate:end,automatic:automatic,projectId:projectId,projectRate:rate);
    test('borrowing, lending, partial and full repayments never become income/expenses',() async {
      final borrowed=await planning.createDebt(contact:'Alex',borrowed:true,principalMinor:10000,walletId:1,reference:'loan1');
      expect((await wallets.fetch()).balances[1],10000);
      final lent=await planning.createDebt(contact:'Sam',borrowed:false,principalMinor:2000,walletId:1,reference:'lend1');
      expect((await wallets.fetch()).balances[1],8000);
      await planning.repay(borrowed,walletId:1,walletMinor:3000,rate:'1',reference:'pay1');
      await planning.repay(lent,walletId:1,walletMinor:500,rate:'1',reference:'receive1');
      final data=await planning.fetch();expect(data.debts.firstWhere((d)=>d.id==borrowed).remainingMinor,7000);
      expect(data.debts.firstWhere((d)=>d.id==lent).status(DateTime.now()),'Partially paid');
      expect((await wallets.fetch()).balances[1],5500);
      expect(FinanceCalculator.totals(await transactions.fetchAll()).count,0);
      await fund(5000);await planning.repay(borrowed,walletId:1,walletMinor:7000,rate:'1',reference:'final');
      expect((await planning.fetch()).debts.firstWhere((d)=>d.id==borrowed).status(DateTime.now()),'Settled');
    });
    test('invalid lending rolls back both debt and wallet posting',() async {
      await expectLater(planning.createDebt(contact:'Sam',borrowed:false,principalMinor:100,walletId:1,reference:'lend'),throwsA(isA<DatabaseException>()));
      expect((await planning.fetch()).debts,isEmpty);expect((await wallets.fetch()).balances[1],0);
    });
    test('overpayments, duplicate repayment references and financial edits are rejected',() async {
      await fund(1000);final id=await planning.createDebt(contact:'Alex',borrowed:true,principalMinor:1000,walletId:1,reference:'loan');
      await expectLater(planning.repay(id,walletId:1,walletMinor:1001,rate:'1',reference:'over'),throwsA(isA<DatabaseException>()));
      await planning.repay(id,walletId:1,walletMinor:300,rate:'1',reference:'pay');
      await expectLater(planning.repay(id,walletId:1,walletMinor:300,rate:'1',reference:'PAY'),throwsA(isA<DatabaseException>()));
      await expectLater(db.db.update('debts',{'principal_minor':2000},where:'id=?',whereArgs:[id]),throwsA(isA<DatabaseException>()));
      expect((await planning.fetch()).debts.single.remainingMinor,700);
      await planning.editDebt(id,contact:'Alex updated',dueDate:'2026-01-01',note:'Note');
      expect((await planning.fetch()).debts.single.status(DateTime(2026,1,2)),'Overdue');
    });
    test('cross-currency principal repayment stores rate and both amounts',() async {
      final id=await planning.createDebt(contact:'Alex',borrowed:true,principalMinor:10000,walletId:1,reference:'usd-loan');
      await wallets.save(const Wallet(name:'AFN',type:WalletType.cash,currency:AppCurrency.afn,openingMinor:1000000));
      final afn=(await wallets.fetch()).wallets.last.id!;
      await planning.repay(id,walletId:afn,walletMinor:700000,rate:'0.014285714286',reference:'afn-pay');
      final data=await planning.fetch();expect(data.debts.single.remainingMinor,0);
      final payment=data.postings.firstWhere((p)=>!p.origin);expect(payment.walletMinor,700000);expect(payment.principalMinor,10000);expect(payment.rate,'0.014285714286');
      expect((await wallets.fetch()).balances[afn],300000);expect((await wallets.fetch()).balances[1],10000);
    });
    test('voiding a repayment reverses cash and outstanding principal without deleting history',() async {
      final id=await planning.createDebt(contact:'Alex',borrowed:true,principalMinor:1000,walletId:1,reference:'loan');
      await planning.repay(id,walletId:1,walletMinor:400,rate:'1',reference:'payment');
      final payment=(await planning.fetch()).postings.firstWhere((p)=>!p.origin);
      await planning.voidRepayment(payment.id);
      final data=await planning.fetch();expect(data.debts.single.remainingMinor,1000);expect(data.postings.firstWhere((p)=>p.id==payment.id).voided,isTrue);
      expect((await wallets.fetch()).balances[1],1000);
    });
    test('goals reserve cash, enforce availability and never double-count savings',() async {
      await fund(10000);final id=await planning.saveGoal(goalName:'Emergency',walletId:1,targetMinor:6000);
      await planning.goalEvent(id,6000,'contribute');final snapshot=await wallets.fetch();
      expect(snapshot.balances[1],10000);expect(snapshot.reserved[1],6000);expect(snapshot.available(1),4000);
      expect(await transactions.fetchAll(),isEmpty);
      await expectLater(transactions.insert(entry(4001)),throwsA(isA<DatabaseException>()));
      await expectLater(planning.goalEvent(id,4001,'too-much'),throwsA(isA<DatabaseException>()));
      await expectLater(planning.goalEvent(id,-6001,'too-low'),throwsA(isA<DatabaseException>()));
      await planning.goalEvent(id,-1000,'withdraw');expect((await wallets.fetch()).balances[1],10000);expect((await wallets.fetch()).available(1),5000);
      await expectLater(planning.goalEvent(id,100,'contribute'),throwsA(isA<DatabaseException>()));
    });
    test('goal completion, withdrawal reopening and archive preserve history',() async {
      await fund(10000);final id=await planning.saveGoal(goalName:'Trip',walletId:1,targetMinor:1000,targetDate:'2026-12-01');
      await expectLater(planning.goalStatus(id,'completed'),throwsA(isA<DatabaseException>()));
      await planning.goalEvent(id,1000,'one');await planning.goalStatus(id,'completed');
      await planning.goalEvent(id,-100,'two');expect((await planning.fetch()).goals.single.status,'active');
      await planning.goalStatus(id,'archived');expect((await wallets.fetch()).reserved[1],900);
      await expectLater(planning.goalEvent(id,100,'three'),throwsA(isA<DatabaseException>()));
      await planning.goalStatus(id,'active');expect((await planning.fetch()).savingsEvents.length,2);
    });
    test('confirmation mode catches missed months, is idempotent and keeps deletion tombstones',() async {
      await rule(start:'2026-01-31',frequency:'monthly');await planning.reconcile(now:DateTime(2026,3,31));await planning.reconcile(now:DateTime(2026,3,31));
      var data=await planning.fetch();expect(data.occurrences.map((o)=>o.dueDate),['2026-01-31','2026-02-28','2026-03-31']);expect(await transactions.fetchAll(),isEmpty);
      final occurrence=data.occurrences.first;await planning.confirmOccurrence(occurrence.id);await planning.confirmOccurrence(occurrence.id);
      final recorded=(await transactions.fetchAll()).single;await transactions.delete(recorded.id!);
      await planning.reconcile(now:DateTime(2026,3,31));await planning.confirmOccurrence(occurrence.id);
      expect(await transactions.fetchAll(),isEmpty);
      await transactions.insert(recorded);data=await planning.fetch();
      expect(data.occurrences.first.transactionId,isNotNull);expect((await transactions.fetchAll()).length,1);
    });
    test('automatic entries reconcile after restart without duplication',() async {
      await rule(automatic:true,end:'2026-01-03');await planning.reconcile(now:DateTime(2026,1,5));
      expect((await transactions.fetchAll()).length,3);
      await db.close();db=await AppDatabase.open(factory:databaseFactoryFfi,path:'${dir.path}/ledger.db');planning=PlanningRepository(db);transactions=SqfliteTransactionRepository(db);
      await planning.reconcile(now:DateTime(2026,1,5));expect((await transactions.fetchAll()).length,3);expect((await planning.fetch()).rules.single.finished,isTrue);
    });
    test('pause, resume and cancellation preserve occurrence history',() async {
      final id=await rule();await planning.ruleState(id,'paused');await planning.reconcile(now:DateTime(2026,1,3));expect((await planning.fetch()).occurrences,isEmpty);
      await planning.ruleState(id,'active');await planning.reconcile(now:DateTime(2026,1,3));expect((await planning.fetch()).occurrences.length,3);
      await planning.ruleState(id,'cancelled');expect((await planning.fetch()).occurrences.every((o)=>o.status=='skipped'),isTrue);
      await expectLater(planning.ruleState(id,'active'),throwsStateError);
    });
    test('blocked automatic expenses remain pending and obey automatic opt-out',() async {
      final id=await rule(automatic:true,type:TransactionType.expense,end:'2026-01-02');await planning.reconcile(now:DateTime(2026,1,2));
      expect(await transactions.fetchAll(),isEmpty);expect((await planning.fetch()).occurrences.every((o)=>o.error!=null),isTrue);
      await fund(1000);await rule(id:id,automatic:false,type:TransactionType.expense,end:'2026-01-02');await planning.reconcile(now:DateTime(2026,1,2));expect(await transactions.fetchAll(),isEmpty);
      await planning.confirmOccurrence((await planning.fetch()).occurrences.first.id);expect((await transactions.fetchAll()).length,1);
    });
    test('clock rollback does not automatically post future pending dates',() async {
      await rule(automatic:true,type:TransactionType.expense,end:'2026-01-03');
      await planning.reconcile(now:DateTime(2026,1,3));
      await fund(1000);await planning.reconcile(now:DateTime(2026,1,1));
      expect((await transactions.fetchAll()).length,1);
      expect((await planning.fetch()).occurrences.where((o)=>o.status=='pending').length,2);
    });
    test('rule edits retain pending snapshots and project reporting rates',() async {
      await fund(10000);final now=DateTime(2026);
      final project=await ProjectRepository(db).save(Project(name:'Work',type:ProjectType.business,currency:AppCurrency.afn,budgetMinor:20000,startDate:now,createdAt:now,updatedAt:now));
      final id=await rule(type:TransactionType.expense,projectId:project,rate:'70',end:'2026-01-02');await planning.reconcile(now:DateTime(2026,1,1));
      await rule(id:id,type:TransactionType.expense,amount:200,projectId:project,rate:'80',end:'2026-01-02');await planning.reconcile(now:DateTime(2026,1,2));
      final data=await planning.fetch();for(final o in data.occurrences){await planning.confirmOccurrence(o.id);}
      final projects=await ProjectRepository(db).fetch();final summary=ProjectFinance.calculate(projects.projects.single,projects.transactions,projects.allocations,projects.categories);
      expect(summary.expenses,7000+16000);expect((await wallets.fetch()).balances[1],9700);
    });
    test('clear all financial data removes new ledgers atomically',() async {
      await planning.createDebt(contact:'A',borrowed:true,principalMinor:1000,walletId:1,reference:'loan');
      final goal=await planning.saveGoal(goalName:'Trip',walletId:1,targetMinor:100);await planning.goalEvent(goal,100,'reserve');
      await rule();await planning.reconcile(now:DateTime(2026,1,1));await transactions.clear();
      final data=await planning.fetch();expect(data.debts,isEmpty);expect(data.goals,isEmpty);expect(data.rules,isEmpty);expect(data.occurrences,isEmpty);expect((await wallets.fetch()).balances[1],0);
    });
    test('foreign key integrity remains clean',() async {expect(await db.db.rawQuery('PRAGMA foreign_key_check'),isEmpty);expect(await db.db.getVersion(),AppDatabase.schemaVersion);});
  });
}
