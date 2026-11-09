import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
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
import 'package:moneytrack/data/storage/access_guard.dart';
import 'package:moneytrack/data/storage/app_runtime.dart';
import 'package:moneytrack/data/storage/generation_store.dart';
import 'package:moneytrack/features/documents/application/document_service.dart';

class Phase4Fixture {
  late Directory root;late AppDatabase database;late SharedPreferences prefs;late GenerationStore store;
  AppRuntime get runtime=>AppRuntime(database:database,store:store,preferences:prefs,restore:(_) async=>throw UnimplementedError());
  static final image=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC');
  Future<void> open() async {
    AccessGuard.locked=false;AccessGuard.maintenance=false;sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({'currency':'USD','theme_mode':'dark','user_name':'Test user','monthly_budget_minor':50000,'local_reminders':true});
    prefs=await SharedPreferences.getInstance();root=await Directory.systemTemp.createTemp('moneytrack-phase4-');
    store=GenerationStore(Directory(p.join(root.path,'moneytrack-data')),factory:databaseFactoryFfi)..currentId='11111111111111111111111111111111';
    await store.current.create(recursive:true);database=await AppDatabase.open(factory:databaseFactoryFfi,path:p.join(store.current.path,'moneytrack.db'));
  }
  TransactionModel entry(int amount,{TransactionType type=TransactionType.expense,int? projectId,String? rate,String note='Note',DateTime? at}){
    final date=at??DateTime(2026,1,1);return TransactionModel(type:type,amountMinor:amount,categoryId:type.isIncome?'salary':'food',
      projectId:projectId,projectRate:rate,note:note,occurredAt:date,createdAt:date,updatedAt:date);
  }
  Future<void> seed() async {
    final wallets=WalletRepository(database),transactions=SqfliteTransactionRepository(database),planning=PlanningRepository(database);
    await wallets.save(const Wallet(id:1,name:'Cash',type:WalletType.cash,currency:AppCurrency.usd,openingMinor:100000));
    await wallets.save(const Wallet(name:'Afghan cash',type:WalletType.cash,currency:AppCurrency.afn,openingMinor:700000));
    await transactions.insert(entry(1000,type:TransactionType.income));
    final expense=await transactions.insert(entry(250,note:'Lunch, "team"'));
    final date=DateTime(2026,1,1);
    final projects=ProjectRepository(database);
    final personal=await projects.save(Project(name:'Home',type:ProjectType.personal,currency:AppCurrency.usd,budgetMinor:10000,startDate:date,createdAt:date,updatedAt:date));
    await projects.allocate(personal,500,'Planning funds');await transactions.insert(entry(300,projectId:personal));
    final foreign=await projects.save(Project(name:'AFN work',type:ProjectType.business,currency:AppCurrency.afn,budgetMinor:10000,contractMinor:20000,startDate:date,createdAt:date,updatedAt:date));
    await transactions.insert(entry(100,projectId:foreign,rate:'70'));
    final debt=await planning.createDebt(contact:'Alex',borrowed:true,principalMinor:1000,walletId:1,reference:'loan');
    await planning.repay(debt,walletId:1,walletMinor:200,rate:'1',reference:'repay');
    final goal=await planning.saveGoal(goalName:'Emergency',walletId:1,targetMinor:5000);
    await planning.goalEvent(goal,2000,'reserve');
    await planning.saveRule(ruleName:'Daily income',type:TransactionType.income,amountMinor:1000,walletId:1,categoryId:'salary',frequency:'daily',startDate:'2026-01-01',endDate:'2026-01-02',automatic:true);
    await planning.reconcile(now:DateTime(2026,1,2));
    await AttachmentRepository(runtime).import(expense.id!,SelectedDocument('receipt.png',image));
  }
  Future<void> close() async {AccessGuard.locked=false;AccessGuard.maintenance=false;if(database.db.isOpen)await database.close();await root.delete(recursive:true);}
}
