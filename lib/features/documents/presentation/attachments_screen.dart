import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/document_service.dart';

class AttachmentsScreen extends ConsumerStatefulWidget {
  const AttachmentsScreen({super.key,required this.transactionId});final int transactionId;
  @override ConsumerState<AttachmentsScreen> createState()=>_AttachmentsState();
}
class _AttachmentsState extends ConsumerState<AttachmentsScreen>{
  bool _busy=false;String? _message;
  Future<void> _pick(String kind) async {if(_busy)return;setState((){_busy=true;_message=null;});
    try {final document=await DocumentBridge.pick(kind);if(document!=null){await ref.read(attachmentRepositoryProvider).import(widget.transactionId,document);ref.invalidate(attachmentsProvider(widget.transactionId));}}
    catch (_){if(mounted)setState(()=>_message='Could not import. Choose a JPEG, PNG or PDF up to 10 MiB and unlock the app first.');}
    finally {if(mounted)setState(()=>_busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Receipts & documents')),body:ListView(padding:const EdgeInsets.all(24),children:[
    const Text('Selected files are copied into private app storage. Removing a receipt does not delete the original photo or document.'),
    Wrap(spacing:10,children:[for(final kind in ['camera','gallery','document'])OutlinedButton.icon(onPressed:_busy?null:()=>_pick(kind),icon:Icon(kind=='camera'?Icons.camera_alt_outlined:kind=='gallery'?Icons.photo_outlined:Icons.description_outlined),label:Text(kind=='camera'?'Camera':kind=='gallery'?'Gallery':'PDF document'))]),
    if(_busy)const LinearProgressIndicator(),if(_message!=null)Text(_message!),
    ref.watch(attachmentsProvider(widget.transactionId)).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(_,_)=>TextButton(onPressed:()=>ref.invalidate(attachmentsProvider(widget.transactionId)),child:const Text('Retry loading receipts')),
      data:(rows)=>Column(children:[if(rows.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No receipts attached.')),
        for(final row in rows)ListTile(contentPadding:EdgeInsets.zero,title:Text(row['original_name'] as String),subtitle:Text('${row['mime']} · ${row['size']} bytes'),
          leading:Icon(row['mime']=='application/pdf'?Icons.picture_as_pdf_outlined:Icons.image_outlined),
          onTap:() async {try {final file=await ref.read(attachmentRepositoryProvider).resolve(row);if(!context.mounted)return;
            if(file==null){setState(()=>_message='This file is missing. Restore it from a complete backup, or remove its reference.');return;}
            if(row['mime']=='application/pdf')await DocumentBridge.open(file);
            else await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>_ImagePreview(file:file,title:row['original_name'] as String)));
          }catch(_){if(mounted)setState(()=>_message='The file could not be opened or failed its integrity check.');}},
          trailing:IconButton(tooltip:'Remove attachment',icon:const Icon(Icons.delete_outline),onPressed:_busy?null:() async {
            final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Remove attachment?'),content:const Text('Only this transaction’s private copy is removed.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Remove'))]));
            if(yes==true){try {await ref.read(attachmentRepositoryProvider).remove(widget.transactionId,row['id'] as int);ref.invalidate(attachmentsProvider(widget.transactionId));}catch(_){if(mounted)setState(()=>_message='Could not remove this attachment.');}}
          }))]))
  ]));
}
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.file,required this.title});final File file;final String title;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(title)),body:Center(child:InteractiveViewer(child:Image.file(file,cacheWidth:1600,errorBuilder:(_,_,_)=>const Text('This image cannot be decoded.')))));
}
