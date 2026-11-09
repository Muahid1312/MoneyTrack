import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageDescriptor, ImmutableBuffer;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/currency.dart';
import '../../features/planning/domain/schedule.dart';
import '../../features/wallets/domain/exchange_rate.dart';
import '../database/app_database.dart';

abstract final class PortableSnapshot {
  static const tables=['wallets','projects','project_categories','debts','savings_goals','recurring_rules','transactions','transfers','project_allocations','debt_postings','savings_events','recurring_occurrences','attachments'];
  static const preferenceKeys=['theme_mode','currency','monthly_budget_minor','user_name','hide_balance','local_reminders',
    'budget_AFN','budget_USD','budget_EUR','budget_PKR','budget_JPY','budget_KWD'];
  static const maxBytes=32*1024*1024;
  static final receiptName=RegExp(r'^[0-9a-f]{32}\.(jpg|png|pdf)$');
  static Future<String> digest(List<int> bytes) async=>(await Sha256().hash(bytes)).bytes.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
  static Future<String> digestFile(File file) async {
    final sink=Sha256().toSync().newHashSink();
    await for(final chunk in file.openRead()){sink.add(chunk);}sink.close();
    return (await sink.hash()).bytes.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
  }
  static Future<String> validateContent(List<int> bytes) async {
    final type=mime(bytes);
    if(type.startsWith('image/')){
      final buffer=await ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));ImageDescriptor? descriptor;
      try {descriptor=await ImageDescriptor.encoded(buffer);if(descriptor.width<=0||descriptor.height<=0||descriptor.width>20000||descriptor.height>20000||descriptor.width*descriptor.height>40000000)throw const FormatException('Image dimensions exceed the supported limit');}
      finally {descriptor?.dispose();buffer.dispose();}
    }
    return type;
  }
  static String mime(List<int> b) {
    if(b.length>=8 && b.take(8).join(',')=='137,80,78,71,13,10,26,10')return 'image/png';
    if(b.length>=3 && b[0]==255 && b[1]==216 && b[2]==255)return 'image/jpeg';
    if(b.length>=5 && ascii.decode(b.take(5).toList(),allowInvalid:true)=='%PDF-')return 'application/pdf';
    throw const FormatException('Only JPEG, PNG and PDF files are supported');
  }
  static Future<File> receiptFile(Directory root,String name) async {
    if(!receiptName.hasMatch(name))throw const FormatException('Unsafe receipt filename');
    final file=File(p.join(root.path,name));
    if(await FileSystemEntity.type(file.path,followLinks:false)==FileSystemEntityType.link)throw const FormatException('Linked files are not supported');
    return file;
  }
  static Map<String,Object?> preferences(SharedPreferences prefs)=>{for(final key in preferenceKeys)if(prefs.containsKey(key))key:prefs.get(key)};
  static void validatePreferences(Map<String,dynamic> values) {
    if(values.keys.any((k)=>!preferenceKeys.contains(k)))throw const FormatException('Unsupported configuration key');
    for(final e in values.entries){final v=e.value;
      if(e.key.startsWith('budget_')||e.key=='monthly_budget_minor'){if(v is! int||v<0||v>AppInfo.maxAmountMinor)throw const FormatException('Invalid budget');}
      else if(e.key=='currency'){AppCurrency.requireCode(v as String);}
      else if(e.key=='theme_mode'){if(!['system','dark','light'].contains(v))throw const FormatException('Invalid theme');}
      else if(e.key=='user_name'){if(v is! String||v.length>1000)throw const FormatException('Invalid name');}
      else if(v is! bool)throw const FormatException('Invalid preference');
    }
  }
  static Future<void> applyPreferences(SharedPreferences prefs,Map<String,dynamic> values) async {
    validatePreferences(values);
    for(final key in preferenceKeys){await prefs.remove(key);}
    for(final e in values.entries){final v=e.value;if(v is int)await prefs.setInt(e.key,v);else if(v is bool)await prefs.setBool(e.key,v);else if(v is String)await prefs.setString(e.key,v);}
  }
  /// Logical SQLite snapshot: every table and every referenced receipt is read
  /// while holding one SQLite transaction. No live SQLite file is copied.
  static Future<Map<String,dynamic>> capture(AppDatabase database,Directory receipts,SharedPreferences prefs) => database.db.transaction((txn) async {
    await validate(txn);
    final data=<String,dynamic>{};var count=0;
    for(final table in tables){final rows=await txn.query(table,orderBy:'id');count+=rows.length;if(count>100000)throw StateError('Backup exceeds 100,000 records');data[table]=rows;}
    final files=<Map<String,dynamic>>[];var total=0;
    for(final raw in data['attachments'] as List){final row=raw as Map;final file=await receiptFile(receipts,row['file_name'] as String);
      if(!await file.exists())throw StateError('A referenced receipt is missing; repair or remove it before backing up');
      final bytes=await file.readAsBytes();total+=bytes.length;
      if(total>16*1024*1024||bytes.length!=row['size']||await digest(bytes)!=row['sha256']||await validateContent(bytes)!=row['mime'])throw StateError('Receipt integrity or backup size check failed');
      files.add({'name':row['file_name'],'data':base64Encode(bytes)});
    }
    return {'schema':AppDatabase.schemaVersion,'tables':data,'sequences':await txn.query('sqlite_sequence',orderBy:'name'),
      'settings':preferences(prefs),'files':files};
  });
  static Future<void> populate(AppDatabase database,Directory receipts,Map<String,dynamic> snapshot) async {
    if(snapshot['schema']!=AppDatabase.schemaVersion)throw const FormatException('Unsupported database version');
    final data=Map<String,dynamic>.from(snapshot['tables'] as Map);
    if(data.keys.toSet().difference(tables.toSet()).isNotEmpty||tables.any((t)=>!data.containsKey(t)))throw const FormatException('Unexpected database tables');
    validatePreferences(Map<String,dynamic>.from(snapshot['settings'] as Map));
    await receipts.create(recursive:true);
    final metadata=<String,Map<String,dynamic>>{};
    for(final row in data['attachments'] as List){final r=Map<String,dynamic>.from(row as Map);final name=r['file_name'] as String;
      if(metadata.containsKey(name)||!receiptName.hasMatch(name)||!name.endsWith({'image/jpeg':'.jpg','image/png':'.png','application/pdf':'.pdf'}[r['mime']]??'unsupported'))throw const FormatException('Invalid receipt metadata');metadata[name]=r;}
    final files=snapshot['files'] as List;if(files.length!=metadata.length||files.length>1000)throw const FormatException('Missing or extra receipts');
    final seen=<String>{};var total=0;
    for(final entry in files){final row=entry as Map;final name=row['name'] as String;final info=metadata[name];
      if(info==null||!seen.add(name))throw const FormatException('Invalid receipt reference');
      final encoded=row['data'] as String;if(encoded.length>14*1024*1024)throw const FormatException('Receipt too large');
      final bytes=base64Decode(encoded);total+=bytes.length;
      if(total>16*1024*1024||bytes.isEmpty||bytes.length>10*1024*1024||bytes.length!=info['size']||await digest(bytes)!=info['sha256']||await validateContent(bytes)!=info['mime'])throw const FormatException('Receipt integrity check failed');
      final file=await receiptFile(receipts,name);await file.writeAsBytes(bytes,flush:true);
    }
    await database.db.transaction((txn) async {
      // Only a fresh staging database is populated. Its own trusted trigger DDL
      // is retained, suspended during bulk insertion, then restored and checked.
      final triggers=await txn.query('sqlite_master',columns:['name','sql'],where:"type='trigger'");
      await txn.execute('PRAGMA defer_foreign_keys=ON');
      for(final trigger in triggers){final name=trigger['name'] as String;if(!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(name))throw StateError('Unexpected trigger');await txn.execute('DROP TRIGGER "$name"');}
      for(final table in tables.reversed){await txn.delete(table);}
      var count=0;
      for(final table in tables){
        final columns=await txn.rawQuery('PRAGMA table_info("$table")');final types={for(final c in columns)c['name'] as String:(c['type'] as String).toUpperCase()};
        final rows=data[table] as List;count+=rows.length;if(count>100000)throw const FormatException('Too many records');
        for(final raw in rows){final row=Map<String,Object?>.from(raw as Map);
          if(row.keys.length!=types.length||row.keys.any((key)=>!types.containsKey(key))||row['id'] is! int||(row['id'] as int)<=0)throw const FormatException('Invalid row');
          for(final e in row.entries){if(e.value==null)continue;if(types[e.key]=='INTEGER' && e.value is! int)throw const FormatException('Invalid integer');if(types[e.key]=='TEXT' && e.value is! String)throw const FormatException('Invalid text');}
          await txn.insert(table,row);
        }
      }
      for(final trigger in triggers){await txn.execute(trigger['sql'] as String);}
      await txn.delete('sqlite_sequence');
      final seenSequences=<String>{};
      for(final raw in snapshot['sequences'] as List){final row=raw as Map;final name=row['name'];final seq=row['seq'];
        if(name is! String||!tables.contains(name)||!seenSequences.add(name)||seq is! int||seq<0)throw const FormatException('Invalid sequence');
        final max=(await txn.rawQuery('SELECT COALESCE(MAX(id),0) AS n FROM "$name"')).single['n'] as int;
        await txn.insert('sqlite_sequence',{'name':name,'seq':seq<max?max:seq});
      }
      await validate(txn);
    });
  }
  static Future<void> validate(DatabaseExecutor db) async {
    if((await db.rawQuery('PRAGMA integrity_check')).single.values.single!='ok'||(await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty)throw const FormatException('Database integrity check failed');
    Future<void> reject(String sql) async {if((await db.rawQuery(sql)).isNotEmpty)throw const FormatException('Financial integrity check failed');}
    await reject("SELECT id FROM wallets WHERE currency NOT IN ('AFN','USD','EUR','PKR','JPY','KWD')");
    await reject('SELECT id FROM wallet_positions WHERE reserved<0 OR (reserved>0 AND balance<reserved)');
    await reject('SELECT w.id FROM wallets w JOIN wallet_positions p ON p.id=w.id WHERE w.archived=1 AND p.reserved>0');
    await reject("SELECT t.id FROM transactions t WHERE t.amount_minor>99999999999 OR t.wallet_id IS NULL OR NOT EXISTS(SELECT 1 FROM wallets w WHERE w.id=t.wallet_id AND w.currency=t.currency)");
    await reject("SELECT id FROM debts d WHERE (SELECT COUNT(*) FROM debt_postings p WHERE p.debt_id=d.id AND kind='origin' AND voided=0)!=1 OR principal_minor<COALESCE((SELECT SUM(principal_minor) FROM debt_postings p WHERE p.debt_id=d.id AND kind='repayment' AND voided=0),0)");
    await reject("SELECT id FROM savings_goals g WHERE COALESCE((SELECT SUM(delta_minor) FROM savings_events WHERE goal_id=g.id),0)<0 OR NOT EXISTS(SELECT 1 FROM wallets w WHERE w.id=g.wallet_id AND w.currency=g.currency) OR (status='completed' AND target_minor>COALESCE((SELECT SUM(delta_minor) FROM savings_events WHERE goal_id=g.id),0))");
    final wallets={for(final row in await db.query('wallets'))row['id']:row};
    final projects={for(final row in await db.query('projects'))row['id']:row};
    for(final row in await db.query('projects')){AppCurrency.requireCode(row['currency'] as String);}
    final debts={for(final row in await db.query('debts'))row['id']:row};
    for(final row in await db.query('debts')){AppCurrency.requireCode(row['currency'] as String);if(row['due_date']!=null)CivilSchedule.parse(row['due_date'] as String);}
    for(final p in await db.query('debt_postings')){final debt=debts[p['debt_id']]!;
      final source=AppCurrency.requireCode(p['currency'] as String),target=AppCurrency.requireCode(debt['currency'] as String);
      if(wallets[p['wallet_id']]!['currency']!=source.code)throw const FormatException('Debt wallet currency mismatch');
      final direction=(debt['type']=='borrowed' && p['kind']=='origin')||(debt['type']=='lent' && p['kind']=='repayment')?1:-1;
      if(direction!=p['direction']||ExchangeRate.parse(p['rate'] as String).convert(p['wallet_minor'] as int,source,target)!=p['principal_minor'])throw const FormatException('Invalid debt conversion');
      if(p['kind']=='origin'&&(p['voided']!=0||p['principal_minor']!=debt['principal_minor']||source!=target||p['rate']!='1'))throw const FormatException('Invalid principal origin');
    }
    for(final row in await db.query('transfers')){
      final source=AppCurrency.requireCode(row['source_currency'] as String),target=AppCurrency.requireCode(row['destination_currency'] as String);
      if(wallets[row['source_id']]!['currency']!=source.code||wallets[row['destination_id']]!['currency']!=target.code||ExchangeRate.parse(row['rate'] as String).convert(row['source_minor'] as int,source,target)!=row['destination_minor'])throw const FormatException('Invalid transfer conversion');
    }
    final categories={for(final c in await db.query('project_categories'))c['id']:c};
    final transactions={for(final t in await db.query('transactions'))t['id']:t};
    for(final t in transactions.values){
      if(t['project_id']==null){if(t['project_amount_minor']!=null||t['project_currency']!=null||t['project_rate']!=null||t['project_category_id']!=null||t['client_receipt']!=0||t['payment_reference']!=null)throw const FormatException('Unassigned project data');}
      else{final project=projects[t['project_id']]!;final target=AppCurrency.requireCode(project['currency'] as String);
        if(t['project_currency']!=target.code||t['project_rate']==null||ExchangeRate.parse(t['project_rate'] as String).convert(t['amount_minor'] as int,AppCurrency.requireCode(t['currency'] as String),target)!=t['project_amount_minor'])throw const FormatException('Project conversion mismatch');
        if(t['project_category_id']!=null && categories[t['project_category_id']]!['project_id']!=t['project_id'])throw const FormatException('Category project mismatch');
        if(t['client_receipt']==1&&(t['type']!='income'||project['type']!='business'||t['payment_reference'] is! String||(t['payment_reference'] as String).trim().isEmpty))throw const FormatException('Invalid client receipt');
        if(t['client_receipt']==0&&t['payment_reference']!=null)throw const FormatException('Invalid payment reference');
      }
    }
    final rules={for(final r in await db.query('recurring_rules'))r['id']:r};
    for(final rule in rules.values){final start=CivilSchedule.parse(rule['start_date'] as String);
      if(CivilSchedule.key(CivilSchedule.at(start,rule['frequency'] as String,rule['next_index'] as int))!=rule['next_date'])throw const FormatException('Invalid recurrence cursor');
      if(rule['end_date']!=null)CivilSchedule.parse(rule['end_date'] as String);
      if(wallets[rule['wallet_id']]!['currency']!=rule['currency'])throw const FormatException('Recurring wallet currency mismatch');
    }
    final occurrenceKeys=<String,int?>{};
    for(final o in await db.query('recurring_occurrences')){
      final payload=Map<String,dynamic>.from(jsonDecode(o['payload'] as String) as Map);
      if(payload['recurring_rule_id']!=o['rule_id']||payload['occurrence_date']!=o['due_date']||!wallets.containsKey(payload['wallet_id'])||wallets[payload['wallet_id']]!['currency']!=payload['currency'])throw const FormatException('Invalid occurrence template');
      CivilSchedule.parse(o['due_date'] as String);
      if(payload['amount_minor'] is! int || (payload['amount_minor'] as int)<=0 || (payload['amount_minor'] as int)>AppInfo.maxAmountMinor || !['income','expense'].contains(payload['type']) || payload['client_receipt']!=0 || (payload['project_id']!=null && !projects.containsKey(payload['project_id'])))throw const FormatException('Invalid occurrence amount or project');
      if(o['transaction_id']!=null){final t=transactions[o['transaction_id']];if(o['status']!='recorded'||t==null||t['recurring_rule_id']!=o['rule_id']||t['occurrence_date']!=o['due_date'])throw const FormatException('Invalid occurrence link');}
      occurrenceKeys['${o['rule_id']}:${o['due_date']}']=o['transaction_id'] as int?;
    }
    for(final t in transactions.values){if(t['recurring_rule_id']!=null && occurrenceKeys['${t['recurring_rule_id']}:${t['occurrence_date']}']!=t['id'])throw const FormatException('Missing recurring history');}
    await reject("SELECT id FROM project_allocations a WHERE NOT EXISTS(SELECT 1 FROM projects p WHERE p.id=a.project_id AND p.type='personal')");
    for(final row in await db.query('savings_goals')){if(row['target_date']!=null)CivilSchedule.parse(row['target_date'] as String);}
  }
}
