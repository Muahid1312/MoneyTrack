import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:moneytrack/features/documents/application/document_service.dart';
import 'package:moneytrack/data/repositories/transaction_repository.dart';
import 'package:moneytrack/data/storage/portable_snapshot.dart';
import 'support/phase4_fixture.dart';
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();late Phase4Fixture f;
  setUp(() async {f=Phase4Fixture();await f.open();});tearDown(() async {await f.close();});
  test('import creates private generated files and removal is transaction-scoped',() async {
    final transactions=SqfliteTransactionRepository(f.database);final first=await transactions.insert(f.entry(100)),second=await transactions.insert(f.entry(200));final repo=AttachmentRepository(f.runtime);
    await repo.import(first.id!,SelectedDocument('../../receipt.jpg',Phase4Fixture.image));final row=(await repo.list(first.id!)).single;
    expect(PortableSnapshot.receiptName.hasMatch(row['file_name'] as String),isTrue);expect(row['original_name'],'receipt.jpg');
    await repo.remove(second.id!,row['id'] as int);expect(await repo.resolve(row),isNotNull);
    await repo.remove(first.id!,row['id'] as int);expect(await repo.list(first.id!),isEmpty);expect(await repo.resolve(row),isNull);
  });
  test('invalid type, excessive size and orphaned transaction imports leave no metadata',() async {
    final repo=AttachmentRepository(f.runtime);
    await expectLater(repo.import(99,SelectedDocument('script.png',Uint8List.fromList([1,2,3]))),throwsFormatException);
    await expectLater(repo.import(99,SelectedDocument('large.jpg',Uint8List(10485761))),throwsArgumentError);
    await expectLater(repo.import(99,SelectedDocument('orphan.jpg',Phase4Fixture.image)),throwsA(anything));
    expect(await f.database.db.query('attachments'),isEmpty);
  });
  test('missing files are reported and cleanup preserves referenced files and unrelated names',() async {
    final tx=await SqfliteTransactionRepository(f.database).insert(f.entry(100));final repo=AttachmentRepository(f.runtime);
    await repo.import(tx.id!,SelectedDocument('receipt.jpg',Phase4Fixture.image));final row=(await repo.list(tx.id!)).single;
    final unrelated=File(p.join(repo.root.path,'user-notes.txt'));await unrelated.writeAsString('Keep');
    final orphan=await PortableSnapshot.receiptFile(repo.root,'22222222222222222222222222222222.jpg');await orphan.writeAsBytes(Phase4Fixture.image);
    await repo.cleanup();expect(await unrelated.exists(),isTrue);expect(await orphan.exists(),isFalse);expect(await repo.resolve(row),isNotNull);
    await (await repo.resolve(row))!.delete();expect(await repo.resolve(row),isNull);
  });
  test('path traversal and linked files are rejected',() async {
    final repo=AttachmentRepository(f.runtime);await repo.root.create(recursive:true);
    await expectLater(PortableSnapshot.receiptFile(repo.root,'../outside.jpg'),throwsFormatException);
    if(!Platform.isWindows){final outside=File(p.join(f.root.path,'outside.jpg'));await outside.writeAsBytes(Phase4Fixture.image);
      await Link(p.join(repo.root.path,'33333333333333333333333333333333.jpg')).create(outside.path);
      await expectLater(PortableSnapshot.receiptFile(repo.root,'33333333333333333333333333333333.jpg'),throwsFormatException);}
  });
}
