import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:moneytrack/data/database/app_database.dart';
import 'package:moneytrack/data/storage/portable_snapshot.dart';
import 'package:moneytrack/data/storage/generation_store.dart';
import 'package:moneytrack/features/backup/application/backup_codec.dart';
import 'package:moneytrack/data/repositories/planning_repository.dart';
import 'support/phase4_fixture.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Phase4Fixture f;
  setUp(() async {f=Phase4Fixture();await f.open();await f.seed();});
  tearDown(() async {await f.close();});
  test('authenticated round-trip preserves every financial table, receipt and sequence',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);
    final bytes=await BackupCodec.encrypt(snapshot,'correct horse battery staple');
    final decoded=await BackupCodec.decrypt(bytes,'correct horse battery staple');expect(decoded,snapshot);
    final stage=await f.store.prepare(decoded);final db=await AppDatabase.open(factory:databaseFactoryFfi,path:p.join(f.store.directory(stage.id).path,'moneytrack.db'));
    try {
      final copy=await PortableSnapshot.capture(db,Directory(p.join(f.store.directory(stage.id).path,'receipts')),f.prefs);
      expect(copy['tables'],snapshot['tables']);expect(copy['files'],snapshot['files']);expect(copy['sequences'],snapshot['sequences']);
      final before=(await PlanningRepository(db).fetch()).occurrences.length;await PlanningRepository(db).reconcile(now:DateTime(2026,1,5));
      expect((await PlanningRepository(db).fetch()).occurrences.length,before);
    }finally{await db.close();await f.store.discard(stage.id);}
  },timeout:const Timeout(Duration(minutes:3)));
  test('wrong passphrase and modified ciphertext never produce a restore stage',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);
    final bytes=await BackupCodec.encrypt(snapshot,'a strong backup passphrase');
    await expectLater(BackupCodec.decrypt(bytes,'the wrong backup passphrase'),throwsA(isA<SecretBoxAuthenticationError>()));
    final corrupt=List<int>.from(bytes);corrupt[corrupt.length-1]^=1;
    await expectLater(BackupCodec.decrypt(corrupt,'a strong backup passphrase'),throwsA(isA<SecretBoxAuthenticationError>()));
    expect((await f.database.db.query('transactions')).length,(snapshot['tables']['transactions'] as List).length);
  },timeout:const Timeout(Duration(minutes:3)));
  test('fresh salts and nonces change each encrypted backup',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);
    final a=await BackupCodec.encrypt(snapshot,'a strong backup passphrase'),b=await BackupCodec.encrypt(snapshot,'a strong backup passphrase');
    expect(BackupCodec.inspect(a)['salt'],isNot(BackupCodec.inspect(b)['salt']));expect(BackupCodec.inspect(a)['nonce'],isNot(BackupCodec.inspect(b)['nonce']));
    expect(BackupCodec.inspect(a).containsKey('password'),isFalse);
  },timeout:const Timeout(Duration(minutes:3)));
  test('unsupported metadata and excessive input are rejected before key derivation',() async {
    final bad=List<int>.filled(40,0);expect(()=>BackupCodec.inspect(bad),throwsFormatException);
    final oversized=List<int>.filled(PortableSnapshot.maxBytes+1,0);expect(()=>BackupCodec.inspect(oversized),throwsFormatException);
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);snapshot['schema']=999;
    await expectLater(f.store.prepare(snapshot),throwsFormatException);
  });
  test('missing receipt and path traversal are rejected without touching live data',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);
    final changed=jsonDecode(jsonEncode(snapshot)) as Map<String,dynamic>;
    (changed['files'] as List).clear();await expectLater(f.store.prepare(changed),throwsFormatException);
    final unsafe=jsonDecode(jsonEncode(snapshot)) as Map<String,dynamic>;
    unsafe['tables']['attachments'][0]['file_name']='../../escape.pdf';unsafe['files'][0]['name']='../../escape.pdf';
    await expectLater(f.store.prepare(unsafe),throwsFormatException);expect(await File(p.join(f.root.path,'escape.pdf')).exists(),isFalse);
    final attachment=(await f.database.db.query('attachments')).single;await (await PortableSnapshot.receiptFile(f.store.receipts,attachment['file_name'] as String)).delete();
    await expectLater(PortableSnapshot.capture(f.database,f.store.receipts,f.prefs),throwsStateError);
  });
  test('generation replacement and rollback recover database, settings and receipts together',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);final stage=await f.store.prepare(snapshot);final previous=f.store.currentId!;
    await f.database.close();await f.store.beginRestore(stage.id,f.prefs);expect(f.store.currentId,stage.id);expect(f.prefs.getBool('local_reminders'),isFalse);
    await f.store.rollback(f.prefs);expect(f.store.currentId,previous);expect(f.prefs.getBool('local_reminders'),isTrue);
    f.database=await AppDatabase.open(factory:databaseFactoryFfi,path:p.join(f.store.current.path,'moneytrack.db'));
    expect((await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs))['tables'],snapshot['tables']);
    await f.store.discard(stage.id);
  });
  test('interrupted prepared journal recovers previous data even after partial preference writes',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);final stage=await f.store.prepare(snapshot);final previous=f.store.currentId!;
    await File(p.join(f.store.current.path,'settings.json')).writeAsString(jsonEncode(snapshot['settings']),flush:true);
    await f.store.journal.writeAsString(jsonEncode({'version':1,'state':'prepared','previous':previous,'next':stage.id}),flush:true);
    await f.store.pointer.writeAsString(jsonEncode({'generation':stage.id}),flush:true);
    await f.prefs.setString('user_name','Partially replaced');await f.prefs.setString('data_generation',previous);
    final recovered=GenerationStore(f.store.root,factory:databaseFactoryFfi);await recovered.initialize(f.prefs);
    expect(recovered.currentId,previous);expect(f.prefs.getString('user_name'),'Test user');await recovered.finishOpen();
    expect(await recovered.directory(stage.id).exists(),isFalse);
  });
  test('a missing or changed validated stage cannot replace live data',() async {
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);final stage=await f.store.prepare(snapshot);final previous=f.store.currentId;
    final file=File(p.join(f.store.directory(stage.id).path,'moneytrack.db'));await file.delete();
    await expectLater(f.store.beginRestore(stage.id,f.prefs),throwsStateError);expect(f.store.currentId,previous);expect(await file.exists(),isFalse);
    expect((await f.database.db.query('transactions')).length,(snapshot['tables']['transactions'] as List).length);await f.store.discard(stage.id);
  });
  test('security credentials and unknown settings are not portable',() async {
    await f.prefs.setString('pin','not a real pin');await f.prefs.setBool('device_lock_required',true);
    final snapshot=await PortableSnapshot.capture(f.database,f.store.receipts,f.prefs);expect((snapshot['settings'] as Map).containsKey('pin'),isFalse);expect((snapshot['settings'] as Map).containsKey('device_lock_required'),isFalse);
    snapshot['settings']['device_lock_required']=false;await expectLater(f.store.prepare(snapshot),throwsFormatException);
  });
}
