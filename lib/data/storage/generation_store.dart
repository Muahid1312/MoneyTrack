import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/currency.dart';
import '../../features/security/application/security_service.dart';
import '../database/app_database.dart';
import 'portable_snapshot.dart';

class PreparedGeneration {
  const PreparedGeneration(this.id,this.counts);final String id;final Map<String,int> counts;
}
class GenerationStore {
  GenerationStore(this.root,{this.factory,this.legacyPath});
  final Directory root;final DatabaseFactory? factory;final String? legacyPath;
  String? currentId;
  Directory directory(String id){if(!RegExp(r'^[0-9a-f]{32}$').hasMatch(id))throw const FormatException('Unsafe generation');return Directory(p.join(root.path,'generations',id));}
  Directory get current=>directory(currentId!);
  Directory get receipts=>Directory(p.join(current.path,'receipts'));
  File get pointer=>File(p.join(root.path,'active.json'));
  File get journal=>File(p.join(root.path,'restore.json'));
  Future<void> _atomic(File target,Map<String,dynamic> value) async {
    final next=File('${target.path}.next');await next.writeAsString(jsonEncode(value),flush:true);await next.rename(target.path);
  }
  Future<void> _point(String id) async {directory(id);await _atomic(pointer,{'generation':id});}
  Future<Map<String,dynamic>> _read(File file) async {
    if(await file.length()>1024*1024)throw const FormatException('Oversized configuration');return Map<String,dynamic>.from(jsonDecode(await file.readAsString()) as Map);
  }
  Future<void> initialize(SharedPreferences prefs) async {
    await root.create(recursive:true);var forcePreferences=false;
    if(await journal.exists()){
      final state=await _read(journal);final selected=(state['state']=='committed'?state['next']:state['previous']) as String;
      await _point(selected);forcePreferences=true;
    }
    if(!await pointer.exists()){
      final legacy=await AppDatabase.open(factory:factory,path:legacyPath,legacyCurrency:AppCurrency.fromCode(prefs.getString('currency')));
      try {
        final snapshot=await PortableSnapshot.capture(legacy,Directory(p.join(root.path,'legacy-receipts')),prefs);
        final stage=await prepare(snapshot,restoring:false);await _point(stage.id);
      } finally {await legacy.close();}
    }
    currentId=(await _read(pointer))['generation'] as String;directory(currentId!);
    if(forcePreferences||prefs.getString('data_generation')!=currentId){
      final settings=await _read(File(p.join(current.path,'settings.json')));
      await PortableSnapshot.applyPreferences(prefs,settings);await prefs.setString('data_generation',currentId!);
    }
  }
  Future<PreparedGeneration> prepare(Map<String,dynamic> snapshot,{bool restoring=true}) async {
    final id=SecureCrypto.random(16).map((v)=>v.toRadixString(16).padLeft(2,'0')).join();final folder=directory(id);
    if(await folder.exists())throw StateError('Generation collision');await folder.create(recursive:true);
    await File(p.join(folder.path,'pending.json')).writeAsString('{"prepared":true}',flush:true);
    AppDatabase? staged;
    try {
      staged=await AppDatabase.open(factory:factory,path:p.join(folder.path,'moneytrack.db'));
      await PortableSnapshot.populate(staged,Directory(p.join(folder.path,'receipts')),snapshot);
      final settings=Map<String,dynamic>.from(snapshot['settings'] as Map);
      // Notification permissions and the device PIN/biometric keys are not
      // imported. Reminders can be re-enabled after reviewing restored rules.
      if(restoring)settings['local_reminders']=false;
      await _atomic(File(p.join(folder.path,'settings.json')),settings);
      await staged.close();staged=null;
      final databaseFile=File(p.join(folder.path,'moneytrack.db'));
      if(await databaseFile.length()>128*1024*1024)throw StateError('Staging database exceeds the supported limit');
      await _atomic(File(p.join(folder.path,'validated.json')),{'database_sha256':await PortableSnapshot.digestFile(databaseFile),'settings_sha256':await PortableSnapshot.digestFile(File(p.join(folder.path,'settings.json')))});
      final data=snapshot['tables'] as Map;
      return PreparedGeneration(id,{for(final table in PortableSnapshot.tables)table:(data[table] as List).length});
    } catch (_) {await staged?.close();staged=null;if(await folder.exists())await folder.delete(recursive:true);rethrow;}
    finally {await staged?.close();}
  }
  /// Caller has stopped UI/lifecycle writes and closed the old database. The
  /// previous directory is the rollback snapshot; no live file is overwritten.
  Future<void> beginRestore(String next,SharedPreferences prefs) async {
    final previous=currentId!;if(previous==next)throw StateError('Generation already active');
    final candidate=directory(next);final file=File(p.join(candidate.path,'moneytrack.db'));
    final settingsFile=File(p.join(candidate.path,'settings.json'));
    if(await FileSystemEntity.type(file.path,followLinks:false)!=FileSystemEntityType.file||await FileSystemEntity.type(settingsFile.path,followLinks:false)!=FileSystemEntityType.file)throw StateError('Validated stage is missing');
    final manifest=await _read(File(p.join(candidate.path,'validated.json')));
    if(await PortableSnapshot.digestFile(file)!=manifest['database_sha256']||await PortableSnapshot.digestFile(settingsFile)!=manifest['settings_sha256'])throw StateError('Validated stage changed');
    await _atomic(File(p.join(directory(previous).path,'settings.json')),Map<String,dynamic>.from(PortableSnapshot.preferences(prefs)));
    await _atomic(journal,{'version':1,'state':'prepared','previous':previous,'next':next});
    await _point(next);currentId=next;
    AppDatabase? check;
    try {
      check=await AppDatabase.open(factory:factory,path:p.join(current.path,'moneytrack.db'));
      await PortableSnapshot.validate(check.db);
      // Read referenced files again before committing the replacement.
      final settings=await _read(File(p.join(current.path,'settings.json')));
      await PortableSnapshot.applyPreferences(prefs,settings);await prefs.setString('data_generation',next);
      await PortableSnapshot.capture(check,receipts,prefs);
      await _atomic(journal,{'version':1,'state':'committed','previous':previous,'next':next});
    } catch (_) {await rollback(prefs);rethrow;}
    finally {await check?.close();}
  }
  Future<void> rollback(SharedPreferences prefs) async {
    if(!await journal.exists())return;
    final state=await _read(journal);final previous=state['previous'] as String;
    await _point(previous);currentId=previous;
    final settings=await _read(File(p.join(current.path,'settings.json')));
    await PortableSnapshot.applyPreferences(prefs,settings);await prefs.setString('data_generation',previous);
    await journal.delete();
  }
  Future<void> finishOpen() async {
    if(await journal.exists())await journal.delete();
    final marker=File(p.join(current.path,'pending.json'));if(await marker.exists())await marker.delete();
    final generations=Directory(p.join(root.path,'generations'));
    await for(final folder in generations.list(followLinks:false)){
      if(folder is Directory && p.basename(folder.path)!=currentId && RegExp(r'^[0-9a-f]{32}$').hasMatch(p.basename(folder.path)) && await File(p.join(folder.path,'pending.json')).exists())await folder.delete(recursive:true);
    }
  }
  Future<void> discard(String id) async {
    if(id==currentId)return;
    if(await journal.exists()){final state=await _read(journal);if(state['previous']==id||state['next']==id)return;}
    final folder=directory(id);if(await folder.exists())await folder.delete(recursive:true);
  }
}
