import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/database/project_migration.dart';
import 'package:moneytrack/data/database/planning_migration.dart';
import 'package:moneytrack/data/database/documents_migration.dart';
import 'package:moneytrack/data/repositories/project_repository.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();sqfliteFfiInit();
  Future<void> legacy(String path,{bool conflict=false}) async {
    final db=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(version:3,onCreate:(db,_) async {
      await db.execute('''CREATE TABLE wallets(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,type TEXT NOT NULL,
        currency TEXT NOT NULL,opening_minor INTEGER NOT NULL,archived INTEGER NOT NULL DEFAULT 0)''');
      await db.execute('''CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT,type TEXT NOT NULL,amount_minor INTEGER NOT NULL,
        category_id TEXT NOT NULL,note TEXT NOT NULL DEFAULT '',occurred_at INTEGER NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
        wallet_id INTEGER REFERENCES wallets(id),currency TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE transfers(id INTEGER PRIMARY KEY AUTOINCREMENT,source_id INTEGER NOT NULL REFERENCES wallets(id),
        destination_id INTEGER NOT NULL REFERENCES wallets(id),source_minor INTEGER NOT NULL,destination_minor INTEGER NOT NULL,
        source_currency TEXT NOT NULL,destination_currency TEXT NOT NULL,rate TEXT NOT NULL,note TEXT NOT NULL DEFAULT '',occurred_at INTEGER NOT NULL)''');
      await migrateProjectsV3(db);
      if(conflict)await db.execute('CREATE TABLE savings_goals(legacy_marker TEXT)');
    }));
    await db.insert('wallets',{'id':1,'name':'Cash','type':'cash','currency':'USD','opening_minor':1000});
    await db.insert('wallets',{'id':2,'name':'Bank','type':'bank','currency':'USD','opening_minor':0});
    await db.insert('projects',{'id':9,'name':'Renovation','type':'personal','currency':'USD','budget_minor':1000,'start_date':0,'status':'active','created_at':0,'updated_at':0});
    await db.insert('transactions',{'id':17,'type':'expense','amount_minor':100,'category_id':'other','note':'Keep me',
      'occurred_at':100,'created_at':100,'updated_at':100,'wallet_id':1,'currency':'USD','project_id':9,'project_currency':'USD','project_amount_minor':100,'project_rate':'1'});
    await db.insert('transfers',{'id':5,'source_id':1,'destination_id':2,'source_minor':50,'destination_minor':50,'source_currency':'USD','destination_currency':'USD','rate':'1','occurred_at':100});
    await db.close();
  }
  test('v3 upgrade preserves wallet/project records and initializes empty planning ledgers',() async {
    final dir=await Directory.systemTemp.createTemp('v3-v4-');final path='${dir.path}/legacy.db';await legacy(path);
    final db=await AppDatabase.open(factory:databaseFactoryFfi,path:path);
    try {
      expect(await db.db.getVersion(),AppDatabase.schemaVersion);final wallets=await WalletRepository(db).fetch();
      expect(wallets.balances[1],850);expect(wallets.balances[2],50);expect(wallets.reserved.values,everyElement(0));
      final projects=await ProjectRepository(db).fetch();expect(projects.projects.single.id,9);expect(projects.transactions.single.id,17);
      expect(projects.transactions.single.projectAmountMinor,100);expect(projects.transactions.single.note,'Keep me');
      expect(await db.db.query('debts'),isEmpty);expect(await db.db.query('savings_goals'),isEmpty);expect(await db.db.query('recurring_rules'),isEmpty);
      expect(await db.db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
    } finally {await db.close();await dir.delete(recursive:true);}
  });
  test('MoneyTrack 2.0 upgrade preserves populated wallet balances, reservations and transaction IDs',() async {
    final dir=await Directory.systemTemp.createTemp('moneytrack-2-to-3-');
    final path='${dir.path}/moneytrack.db';
    try {
      await legacy(path);
      final old=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(
        version:5,onUpgrade:(db,_,__) async {
          await migratePlanningV4(db);
          await migrateDocumentsV5(db);
        }));
      await old.insert('wallets',{'id':3,'name':'Afghan cash','type':'cash','currency':'AFN','opening_minor':2000000});
      await old.insert('savings_goals',{'id':11,'name':'Rainy day','wallet_id':3,'currency':'AFN','target_minor':750000,'created_at':10});
      await old.insert('savings_events',{'id':13,'goal_id':11,'delta_minor':500000,'reference':'Saved','occurred_at':11});
      final positions=await old.query('wallet_positions',orderBy:'id');
      final txs=await old.query('transactions',orderBy:'id');
      final wallets=await old.query('wallets',orderBy:'id');
      await old.close();
      final upgraded=await AppDatabase.open(factory:databaseFactoryFfi,path:path);
      try {
        expect(await upgraded.db.getVersion(),6);
        expect(await upgraded.db.query('wallet_positions',orderBy:'id'),positions);
        expect(await upgraded.db.query('wallets',orderBy:'id'),wallets);
        expect(await upgraded.db.query('transactions',orderBy:'id'),txs);
        expect(txs.single['id'],17);
        expect((await upgraded.db.query('savings_goals')).single['emergency'],0);
        expect((await upgraded.db.query('savings_events')).single['id'],13);
      } finally {await upgraded.close();}
    } finally {await dir.delete(recursive:true);}
  });
  test('late migration failure rolls back v4 tables and preserves v3 financial history',() async {
    final dir=await Directory.systemTemp.createTemp('v4-fail-');final path='${dir.path}/legacy.db';await legacy(path,conflict:true);
    await expectLater(AppDatabase.open(factory:databaseFactoryFfi,path:path),throwsA(isA<DatabaseException>()));
    final raw=await databaseFactoryFfi.openDatabase(path);
    try {
      expect(await raw.getVersion(),3);expect((await raw.query('transactions')).single['id'],17);expect((await raw.query('projects')).single['id'],9);
      expect((await raw.query('transfers')).single['id'],5);
      expect(await raw.rawQuery("SELECT name FROM sqlite_master WHERE name='debts'"),isEmpty);
      expect((await raw.rawQuery('PRAGMA table_info(transactions)')).any((c)=>c['name']=='recurring_rule_id'),isFalse);
    } finally {await raw.close();await dir.delete(recursive:true);}
  });
}
