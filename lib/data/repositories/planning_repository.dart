import '../storage/access_guard.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/currency.dart';
import '../../features/planning/domain/schedule.dart';
import '../../features/wallets/domain/exchange_rate.dart';
import '../database/app_database.dart';
import '../models/planning.dart';
import '../models/transaction.dart';
import '../models/transaction_type.dart';
import 'transaction_repository.dart';

class PlanningRepository {
  PlanningRepository(this.database);
  final AppDatabase database;
  Future<PlanningSnapshot> fetch() => database.db.transaction((txn) async {
    final postings=(await txn.query('debt_postings',orderBy:'occurred_at DESC,id DESC')).map(DebtPosting.new).toList();
    final events=await txn.query('savings_events',orderBy:'occurred_at DESC,id DESC');
    return PlanningSnapshot(
      debts:(await txn.query('debts',orderBy:'created_at DESC,id DESC')).map((d)=>Debt(d,
        postings.where((p)=>p.debtId==d['id'] && !p.origin && !p.voided).fold<int>(0,(s,p)=>s+p.principalMinor))).toList(),
      postings:postings, savingsEvents:events,
      goals:(await txn.query('savings_goals',orderBy:'id DESC')).map((g)=>SavingsGoal(g,
        events.where((e)=>e['goal_id']==g['id']).fold<int>(0,(s,e)=>s+(e['delta_minor'] as int)))).toList(),
      rules:(await txn.query('recurring_rules',orderBy:'next_date,id')).map(RecurringRule.new).toList(),
      occurrences:(await txn.query('recurring_occurrences',orderBy:'due_date,id')).map(RecurringOccurrence.new).toList());
  });
  static void amount(int value) { if(value<=0 || value>AppInfo.maxAmountMinor) throw ArgumentError('Enter a valid positive amount'); }
  static String name(String value) { final text=value.trim(); if(text.isEmpty || text.length>100) throw ArgumentError('Enter 1–100 characters'); return text; }
  static String? date(String? value) { if(value==null || value.isEmpty)return null; CivilSchedule.parse(value); return value; }
  Future<Map<String,Object?>> _wallet(DatabaseExecutor txn,int id) async {
    final rows=await txn.query('wallets',where:'id=? AND archived=0',whereArgs:[id]);
    if(rows.isEmpty)throw ArgumentError('Choose an active wallet'); return rows.single;
  }
  Future<int> createDebt({required String contact,required bool borrowed,required int principalMinor,
    required int walletId,required String reference,String? dueDate,String note=''}) => database.db.transaction((txn) async {
    AccessGuard.writable();
    amount(principalMinor); final wallet=await _wallet(txn,walletId); final now=DateTime.now().millisecondsSinceEpoch;
    final id=await txn.insert('debts',{'contact':name(contact),'type':borrowed?'borrowed':'lent',
      'principal_minor':principalMinor,'currency':wallet['currency'],'created_at':now,'due_date':date(dueDate),'note':note.trim()});
    await txn.insert('debt_postings',{'debt_id':id,'wallet_id':walletId,'kind':'origin','wallet_minor':principalMinor,
      'principal_minor':principalMinor,'currency':wallet['currency'],'rate':'1','direction':borrowed?1:-1,
      'reference':name(reference).toLowerCase(),'occurred_at':now}); return id;
  });
  Future<void> editDebt(int id,{required String contact,String? dueDate,String note=''}) async {
    AccessGuard.writable();
    if(await database.db.update('debts',{'contact':name(contact),'due_date':date(dueDate),'note':note.trim()},where:'id=?',whereArgs:[id])!=1)throw StateError('Debt not found');
  }
  Future<void> repay(int debtId,{required int walletId,required int walletMinor,required String rate,required String reference}) => database.db.transaction((txn) async {
    AccessGuard.writable();
    amount(walletMinor); final wallet=await _wallet(txn,walletId);
    final rows=await txn.query('debts',where:'id=?',whereArgs:[debtId]); if(rows.isEmpty)throw ArgumentError('Debt not found');
    final debt=rows.single; final source=AppCurrency.requireCode(wallet['currency'] as String), target=AppCurrency.requireCode(debt['currency'] as String);
    final exchange=ExchangeRate.parse(source==target?'1':rate);
    final principal=exchange.convert(walletMinor,source,target);
    await txn.insert('debt_postings',{'debt_id':debtId,'wallet_id':walletId,'kind':'repayment','wallet_minor':walletMinor,
      'principal_minor':principal,'currency':source.code,'rate':exchange.text,'direction':debt['type']=='borrowed'?-1:1,
      'reference':name(reference).toLowerCase(),'occurred_at':DateTime.now().millisecondsSinceEpoch});
  });
  Future<void> voidRepayment(int id) async {
    AccessGuard.writable();
    if(await database.db.update('debt_postings',{'voided':1},where:"id=? AND kind='repayment' AND voided=0",whereArgs:[id])!=1)throw StateError('Repayment not found');
  }
  Future<int> saveGoal({int? id,required String goalName,required int walletId,required int targetMinor,
    String? targetDate,int color=0xFF10B981,String icon='savings'}) => database.db.transaction((txn) async {
    AccessGuard.writable();
    amount(targetMinor); final wallet=await _wallet(txn,walletId);
    final map=<String,Object?>{'name':name(goalName),'wallet_id':walletId,'currency':wallet['currency'],
      'target_minor':targetMinor,'target_date':date(targetDate),'color':color,'icon':icon};
    if(id==null) { map['created_at']=DateTime.now().millisecondsSinceEpoch;return txn.insert('savings_goals',map); }
    final totals=await txn.rawQuery('SELECT COALESCE(SUM(delta_minor),0) AS n FROM savings_events WHERE goal_id=?',[id]);
    final old=await txn.query('savings_goals',where:'id=?',whereArgs:[id]); if(old.isEmpty)throw StateError('Goal not found');
    if(old.single['status']=='completed' && (totals.single['n'] as int)<targetMinor)map['status']='active';
    await txn.update('savings_goals',map,where:'id=?',whereArgs:[id]);return id;
  });
  Future<void> goalEvent(int goalId,int deltaMinor,String reference) => database.db.transaction((txn) async {
    AccessGuard.writable();
    amount(deltaMinor.abs());
    await txn.insert('savings_events',{'goal_id':goalId,'delta_minor':deltaMinor,'reference':name(reference),
      'occurred_at':DateTime.now().millisecondsSinceEpoch});
    final goal=(await txn.query('savings_goals',where:'id=?',whereArgs:[goalId])).single;
    final allocated=(await txn.rawQuery('SELECT SUM(delta_minor) AS n FROM savings_events WHERE goal_id=?',[goalId])).single['n'] as int;
    if(goal['status']=='completed' && allocated<(goal['target_minor'] as int))await txn.update('savings_goals',{'status':'active'},where:'id=?',whereArgs:[goalId]);
  });
  Future<void> goalStatus(int id,String status) async {
    AccessGuard.writable();
    if(!['active','completed','archived'].contains(status))throw ArgumentError('Invalid goal status');
    await database.db.update('savings_goals',{'status':status},where:'id=?',whereArgs:[id]);
  }
  Future<int> saveRule({int? id,required String ruleName,required TransactionType type,
    required int amountMinor,required int walletId,required String categoryId,int? projectId,String? projectRate,
    required String frequency,required String startDate,String? endDate,bool automatic=false}) => database.db.transaction((txn) async {
    AccessGuard.writable();
    amount(amountMinor); final wallet=await _wallet(txn,walletId); final anchor=CivilSchedule.parse(startDate);
    CivilSchedule.at(anchor,frequency,0); date(endDate);
    if(endDate!=null && endDate.compareTo(startDate)<0)throw ArgumentError('End date precedes start');
    if(Categories.byId(categoryId).id=='unknown' || Categories.byId(categoryId).type!=type)throw ArgumentError('Choose a matching category');
    if(projectId!=null) {
      final projects=await txn.query('projects',where:"id=? AND status!='archived'",whereArgs:[projectId]);
      if(projects.isEmpty)throw ArgumentError('Choose an unarchived project');
      if(projects.single['currency']!=wallet['currency'])ExchangeRate.parse(projectRate??'');
    }
    final map=<String,Object?>{'name':name(ruleName),'type':type.storageKey,'amount_minor':amountMinor,'wallet_id':walletId,
      'currency':wallet['currency'],'category_id':categoryId,'project_id':projectId,'project_rate':projectRate,
      'frequency':frequency,'start_date':startDate,'end_date':endDate,'automatic':automatic?1:0};
    if(id==null){map.addAll({'created_at':DateTime.now().millisecondsSinceEpoch,'next_date':startDate,'next_index':0});return txn.insert('recurring_rules',map);}
    final old=await txn.query('recurring_rules',where:'id=?',whereArgs:[id]);
    if(old.isEmpty || old.single['state']=='cancelled')throw StateError('Cancelled rules cannot be edited');
    if(old.single['start_date']!=startDate || old.single['frequency']!=frequency){map['next_date']=startDate;map['next_index']=0;}
    await txn.update('recurring_rules',map,where:'id=?',whereArgs:[id]);return id;
  });
  Future<void> ruleState(int id,String state) => database.db.transaction((txn) async {
    AccessGuard.writable();
    if(!['active','paused','cancelled'].contains(state))throw ArgumentError('Invalid state');
    final rows=await txn.query('recurring_rules',where:'id=?',whereArgs:[id]);
    if(rows.isEmpty || rows.single['state']=='cancelled')throw StateError('Cancelled rules cannot resume');
    await txn.update('recurring_rules',{'state':state},where:'id=?',whereArgs:[id]);
    if(state=='cancelled')await txn.update('recurring_occurrences',{'status':'skipped','error':'Rule cancelled'},where:"rule_id=? AND status='pending'",whereArgs:[id]);
  });
  /// Every pending occurrence stores its template, so editing a rule never
  /// silently changes missed bills. Each execution is its own atomic commit.
  Future<void> reconcile({DateTime? now}) async {
    if(AccessGuard.locked || AccessGuard.maintenance)return;
    final today=CivilSchedule.key(now??DateTime.now());
    final rules=await database.db.query('recurring_rules',where:"state='active'");
    for(final original in rules) {
      var more=true;
      while(more && !AccessGuard.locked && !AccessGuard.maintenance) {
        more=await database.db.transaction((txn) async {
    AccessGuard.writable();
          final current=(await txn.query('recurring_rules',where:'id=?',whereArgs:[original['id']])).single;
          final due=current['next_date'] as String;
          if(current['state']!='active' || due.compareTo(today)>0 || (current['end_date']!=null && due.compareTo(current['end_date'] as String)>0))return false;
          final day=CivilSchedule.parse(due);
          final entry=TransactionModel(type:TransactionType.fromStorage(current['type'] as String),amountMinor:current['amount_minor'] as int,
            walletId:current['wallet_id'] as int,currency:AppCurrency.requireCode(current['currency'] as String),categoryId:current['category_id'] as String,
            projectId:current['project_id'] as int?,projectRate:current['project_rate'] as String?,
            note:current['name'] as String,occurredAt:day,createdAt:now??DateTime.now(),updatedAt:now??DateTime.now(),
            recurringRuleId:current['id'] as int,occurrenceDate:due);
          await txn.insert('recurring_occurrences',{'rule_id':current['id'],'due_date':due,'payload':jsonEncode(entry.toMap()),
            'automatic':current['automatic']},conflictAlgorithm:ConflictAlgorithm.ignore);
          final next=(current['next_index'] as int)+1;
          final nextDay=CivilSchedule.at(CivilSchedule.parse(current['start_date'] as String),current['frequency'] as String,next);
          await txn.update('recurring_rules',{'next_index':next,'next_date':CivilSchedule.key(nextDay)},where:'id=?',whereArgs:[current['id']]);
          return true;
        });
      }
    }
    final pending=await database.db.rawQuery("SELECT o.id FROM recurring_occurrences o JOIN recurring_rules r ON o.rule_id=r.id WHERE o.status='pending' AND o.automatic=1 AND r.automatic=1 AND r.state='active' AND o.due_date<=? ORDER BY o.due_date,o.id",[today]);
    for(final occurrence in pending) { if(AccessGuard.locked || AccessGuard.maintenance)break; try { await confirmOccurrence(occurrence['id'] as int); } catch (_) { /* Error is persisted and exposed in the due list. */ } }
  }
  Future<void> confirmOccurrence(int id) async {
    try {
      await database.db.transaction((txn) async {
    AccessGuard.writable();
        final rows=await txn.query('recurring_occurrences',where:'id=?',whereArgs:[id]);
        if(rows.isEmpty)throw StateError('Occurrence not found'); final occurrence=rows.single;
        if(occurrence['status']!='pending')return;
        final rule=(await txn.query('recurring_rules',where:'id=?',whereArgs:[occurrence['rule_id']])).single;
        if(rule['state']!='active')throw StateError('Resume the rule first');
        final payload=Map<String,Object?>.from(jsonDecode(occurrence['payload'] as String) as Map);
        payload['id']=null;
        final model=TransactionModel.fromMap({...payload,'id':0});
        if(Categories.byId(model.categoryId).id=='unknown' || Categories.byId(model.categoryId).type!=model.type)throw StateError('Saved category is no longer valid');
        if(model.type.isExpense) {
          final position=(await txn.query('wallet_positions',where:'id=?',whereArgs:[model.walletId])).single;
          if(model.amountMinor>(position['balance'] as int)-(position['reserved'] as int))throw StateError('Insufficient available funds; entry not recorded');
        }
        final entry=await SqfliteTransactionRepository(database).insertInto(txn,model);
        await txn.update('recurring_occurrences',{'status':'recorded','transaction_id':entry.id,'error':null},where:'id=?',whereArgs:[id]);
      });
    } catch (_) {
      if(!AccessGuard.locked && !AccessGuard.maintenance)await database.db.update('recurring_occurrences',{'error':'Not recorded. Check available funds, wallet/project status, category and manual rate.'},where:"id=? AND status='pending'",whereArgs:[id]);
      rethrow;
    }
  }
  Future<void> skipOccurrence(int id) async {
    AccessGuard.writable();
    await database.db.update('recurring_occurrences',{'status':'skipped','error':null},where:"id=? AND status='pending'",whereArgs:[id]);
  }
}
