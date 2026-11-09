import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../data/storage/access_guard.dart';
import '../../../data/storage/app_runtime.dart';
import '../../../data/storage/generation_store.dart';
import '../../../data/storage/portable_snapshot.dart';
import '../../documents/application/document_service.dart';
import '../../reports/application/report_exporter.dart';
import '../../security/application/security_service.dart';
import '../../security/presentation/security_widgets.dart';
import '../application/backup_codec.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override ConsumerState<BackupScreen> createState()=>_BackupState();
}
class _BackupState extends ConsumerState<BackupScreen>{
  final _exportPass=TextEditingController(),_confirm=TextEditingController(),_restorePass=TextEditingController(),_pin=TextEditingController();
  SelectedDocument? _selected;bool _busy=false;String? _message;
  @override void dispose(){for(final c in [_exportPass,_confirm,_restorePass,_pin]){c.dispose();}super.dispose();}
  Future<void> _export() async {
    if(_busy)return;setState(()=>_busy=true);
    try {AccessGuard.writable();if(_exportPass.text!=_confirm.text)throw ArgumentError('Passphrases must match');
      final runtime=ref.read(appRuntimeProvider)!;AccessGuard.maintenance=true;
      List<int> encrypted;
      try {final snapshot=await PortableSnapshot.capture(runtime.database,runtime.store.receipts,runtime.preferences);encrypted=await BackupCodec.encrypt(snapshot,_exportPass.text);}
      finally {AccessGuard.maintenance=false;_exportPass.clear();_confirm.clear();}
      await AccessGuard.waitForUnlock();AccessGuard.writable();
      final folder=Directory(p.join((await getTemporaryDirectory()).path,'exports'));await folder.create(recursive:true);
      final token=SecureCrypto.random(12).map((v)=>v.toRadixString(16).padLeft(2,'0')).join();final file=File(p.join(folder.path,'moneytrack-backup-$token.mtbackup'));
      await file.writeAsBytes(encrypted,flush:true);
      if(context.mounted)await ReportExporter.share(file,origin:Rect.fromLTWH(MediaQuery.sizeOf(context).width/2,MediaQuery.sizeOf(context).height/2,1,1));
      if(mounted)setState(()=>_message='Encrypted backup created. Keep its passphrase separately; it cannot be recovered by the app.');
    }catch(_){if(mounted)setState(()=>_message='Backup was not exported. Use matching passphrases of at least 12 characters and check for missing receipts or the 32 MiB backup limit.');}
    finally {AccessGuard.maintenance=false;_exportPass.clear();_confirm.clear();if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _choose() async {if(_busy)return;setState(()=>_busy=true);
    try {final file=await DocumentBridge.pick('backup');if(file!=null){BackupCodec.inspect(file.bytes);setState((){_selected=file;_message='Format recognized. Enter the backup passphrase to authenticate and validate it.';});}}
    catch(_){if(mounted)setState(()=>_message='Unsupported, unreadable or oversized backup. Live data is unchanged.');}
    finally {if(mounted)setState(()=>_busy=false);}}
  Future<void> _restore() async {
    if(_busy||_selected==null)return;setState(()=>_busy=true);PreparedGeneration? stage;
    final runtime=ref.read(appRuntimeProvider)!;
    try {AccessGuard.writable();final security=SecurityController.instance;
      if(security.configured&&!await security.verify(_pin.text))throw StateError('App PIN verification failed');_pin.clear();
      AccessGuard.maintenance=true;
      try {final snapshot=await BackupCodec.decrypt(_selected!.bytes,_restorePass.text);stage=await runtime.store.prepare(snapshot);}
      finally {AccessGuard.maintenance=false;_restorePass.clear();}
      await AccessGuard.waitForUnlock();AccessGuard.writable();if(!context.mounted)return;
      final chosen=stage!;
      final yes=await showDialog<bool>(context:context,barrierDismissible:false,builder:(ctx)=>AlertDialog(title:const Text('Replace current financial data?'),content:SingleChildScrollView(child:Text(
        'The backup was authenticated and validated.\n\n${chosen.counts['transactions']} transactions\n${chosen.counts['wallets']} wallets\n${chosen.counts['projects']} projects\n${chosen.counts['debts']} debts\n${chosen.counts['savings_goals']} savings goals\n${chosen.counts['attachments']} receipts\n\nThis replaces the current financial data and settings. The previous data generation is retained for rollback if replacement fails. The app will reload and require its existing PIN when configured. Device lock credentials are retained. Re-enable reminders after reviewing restored rules.')),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Replace and reload'))]));
      if(yes==true){await runtime.restore(chosen);stage=null;}
    }catch(_){if(mounted)setState(()=>_message='Restore was not completed. Check the app PIN and backup passphrase. Corrupt, incomplete or incompatible backups are rejected; the current or rollback generation is retained.');}
    finally {AccessGuard.maintenance=false;_restorePass.clear();_pin.clear();if(stage!=null)await runtime.store.discard(stage!.id);if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:!_busy,child:Scaffold(appBar:AppBar(title:const Text('Encrypted backup & restore')),body:ListView(padding:const EdgeInsets.all(24),children:[
    const Text('Portable backups include financial records, receipts and app preferences. AES-256-GCM encryption uses a separate passphrase. Device PIN verifiers, biometric keys and platform permissions are never exported.'),
    const Text('All receipts must be present. Portable backups are limited to 32 MiB, including up to 16 MiB of receipt content. No unencrypted backup is produced.'),
    const SizedBox(height:20),Text('Create encrypted backup',style:Theme.of(context).textTheme.titleLarge),
    TextField(controller:_exportPass,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'Backup passphrase (at least 12 characters)')),
    TextField(controller:_confirm,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'Confirm backup passphrase')),
    FilledButton.icon(onPressed:_busy?null:_export,icon:const Icon(Icons.lock_outline),label:const Text('Encrypt and export backup')),
    const Divider(height:32),Text('Validate and restore',style:Theme.of(context).textTheme.titleLarge),
    OutlinedButton.icon(onPressed:_busy?null:_choose,icon:const Icon(Icons.folder_open),label:const Text('Choose encrypted backup')),
    if(_selected!=null)...[Text(_selected!.name),TextField(controller:_restorePass,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'Backup passphrase')),
      if(SecurityController.instance.configured)pinField(_pin,'Current app PIN'),
      FilledButton(onPressed:_busy?null:_restore,child:const Text('Authenticate, validate and review restore'))],
    if(_busy)...[const LinearProgressIndicator(),const Text('Processing locally. Keep the app open; live data is not replaced until validation and confirmation finish.')],
    if(_message!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text(_message!)),
  ])));
}
