import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../data/storage/access_guard.dart';
import '../../../data/storage/app_runtime.dart';
import '../../../data/storage/portable_snapshot.dart';
import '../../security/application/security_service.dart';

class SelectedDocument {
  const SelectedDocument(this.name,this.bytes);final String name;final Uint8List bytes;
}
abstract final class DocumentBridge {
  static const channel=MethodChannel('moneytrack/documents');
  static Future<SelectedDocument?> pick(String kind) async {
    final raw=await channel.invokeMapMethod<String,dynamic>('pick',{'kind':kind});
    await AccessGuard.waitForUnlock();AccessGuard.writable();
    if(raw==null)return null;return SelectedDocument(raw['name'] as String,raw['bytes'] as Uint8List);
  }
  static Future<void> open(File file) async {AccessGuard.writable();await channel.invokeMethod('open',{'path':file.path});}
}
class AttachmentRepository {
  AttachmentRepository(this.runtime);final AppRuntime runtime;
  Directory get root=>runtime.store.receipts;
  Future<List<Map<String,Object?>>> list(int transactionId)=>runtime.database.db.query('attachments',where:'transaction_id=?',whereArgs:[transactionId],orderBy:'created_at,id');
  Future<void> import(int transactionId,SelectedDocument document) async {
    AccessGuard.writable();final bytes=document.bytes;if(bytes.isEmpty||bytes.length>10*1024*1024)throw ArgumentError('Choose a file up to 10 MiB');
    final type=await PortableSnapshot.validateContent(bytes);final extension={'image/jpeg':'jpg','image/png':'png','application/pdf':'pdf'}[type]!;
    final name='${SecureCrypto.random(16).map((v)=>v.toRadixString(16).padLeft(2,'0')).join()}.$extension';
    await root.create(recursive:true);final file=await PortableSnapshot.receiptFile(root,name);
    if(await file.exists())throw StateError('File name collision');
    await file.writeAsBytes(bytes,flush:true);
    try {AccessGuard.writable();var display=p.basename(document.name).replaceAll(RegExp(r'[\x00-\x1f\x7f]'),'');if(display.length>120)display=display.substring(0,120);
      await runtime.database.db.insert('attachments',{'transaction_id':transactionId,'file_name':name,'original_name':display.isEmpty?'Receipt.$extension':display,
        'mime':type,'size':bytes.length,'sha256':await PortableSnapshot.digest(bytes),'created_at':DateTime.now().millisecondsSinceEpoch});
    } catch (_){if(await file.exists())await file.delete();rethrow;}
  }
  Future<File?> resolve(Map<String,Object?> attachment) async {
    final file=await PortableSnapshot.receiptFile(root,attachment['file_name'] as String);
    if(!await file.exists())return null;
    if(await file.length()!=attachment['size']||await PortableSnapshot.digest(await file.readAsBytes())!=attachment['sha256'])throw StateError('Receipt integrity check failed');
    return file;
  }
  Future<void> remove(int transactionId,int id) async {
    AccessGuard.writable();final rows=await runtime.database.db.query('attachments',where:'id=? AND transaction_id=?',whereArgs:[id,transactionId]);if(rows.isEmpty)return;
    await runtime.database.db.delete('attachments',where:'id=? AND transaction_id=?',whereArgs:[id,transactionId]);
    final file=await PortableSnapshot.receiptFile(root,rows.single['file_name'] as String);if(await file.exists())await file.delete();
  }
  Future<void> cleanup() async {
    final names=(await runtime.database.db.query('attachments',columns:['file_name'])).map((r)=>r['file_name']).toSet();
    if(!await root.exists())return;
    await for(final entry in root.list(followLinks:false)){if(entry is File && PortableSnapshot.receiptName.hasMatch(p.basename(entry.path)) && !names.contains(p.basename(entry.path)))await entry.delete();}
  }
}
final attachmentRepositoryProvider=Provider<AttachmentRepository>((ref){final runtime=ref.watch(appRuntimeProvider);if(runtime==null)throw StateError('Storage unavailable');return AttachmentRepository(runtime);});
final attachmentsProvider=FutureProvider.autoDispose.family<List<Map<String,Object?>>,int>((ref,id)=>ref.watch(attachmentRepositoryProvider).list(id));
