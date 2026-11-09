import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/planning.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/models/wallet.dart';
import '../../projects/application/project_providers.dart';
import '../../wallets/application/wallet_providers.dart';
import '../../wallets/domain/exchange_rate.dart';
import '../application/planning_providers.dart';
import '../domain/schedule.dart';

Future<void> _finishSaved(BuildContext context,WidgetRef ref) async {
  try { await refreshPlanning(ref); }
  catch (_) { if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Saved. Reopen this screen to refresh stored records.'))); }
  if(context.mounted)Navigator.pop(context);
}
String? _required(String? value)=>(value??'').trim().isEmpty?'This field is required':null;
String? _date(String? value){if((value??'').isEmpty)return null;try{CivilSchedule.parse(value!);return null;}catch(_){return 'Use a valid YYYY-MM-DD date';}}
List<Wallet> _wallets(WidgetRef ref)=>ref.watch(walletsProvider).valueOrNull?.wallets.where((w)=>!w.archived).toList()??[];
Wallet? _selected(List<Wallet> wallets,int? id)=>id==null?wallets.firstOrNull:wallets.where((w)=>w.id==id).firstOrNull;
Widget _walletPicker(List<Wallet> wallets,Wallet? wallet,ValueChanged<int?>? onChanged)=>DropdownButtonFormField<int>(
  key:ValueKey(wallet?.id),initialValue:wallet?.id,isExpanded:true,decoration:const InputDecoration(labelText:'Wallet · currency'),
  items:[for(final w in wallets)DropdownMenuItem(value:w.id,child:Text('${w.name} · ${w.currency.code}',overflow:TextOverflow.ellipsis))],onChanged:onChanged,
  validator:(v)=>v==null?'Create or restore a wallet first':null);
Widget _field(TextEditingController controller,String label,{bool required=false,bool date=false,int? maxLength})=>Padding(
  padding:const EdgeInsets.symmetric(vertical:8),child:TextFormField(controller:controller,maxLength:maxLength,
    decoration:InputDecoration(labelText:label,hintText:date?'YYYY-MM-DD':null),keyboardType:date?TextInputType.datetime:TextInputType.text,
    validator:date?(v){if(required && (v??'').isEmpty)return 'This field is required';return _date(v);}:required?_required:null));
Widget _amount(TextEditingController controller,AppCurrency currency,String label)=>Padding(padding:const EdgeInsets.symmetric(vertical:12),
  child:TextFormField(controller:controller,keyboardType:const TextInputType.numberWithOptions(decimal:true),
    decoration:InputDecoration(labelText:'$label (${currency.code})'),validator:(v)=>(Money.parseMinor(v??'',currency)??0)>0?null:'Enter a valid positive amount'));
Widget _errorNotice(String? message,BuildContext context)=>message==null?const SizedBox.shrink():Padding(padding:const EdgeInsets.symmetric(vertical:12),
  child:Text(message,style:TextStyle(color:Theme.of(context).colorScheme.error)));

class DebtForm extends ConsumerStatefulWidget {
  const DebtForm({super.key,this.debt});final Debt? debt;
  @override
  ConsumerState<DebtForm> createState()=>_DebtFormState();
}
class _DebtFormState extends ConsumerState<DebtForm> {
  final _form=GlobalKey<FormState>();late final TextEditingController _contact,_note,_due;
  final _principal=TextEditingController(),_reference=TextEditingController();
  bool _borrowed=true,_saving=false;int? _walletId;String? _error;
  @override
  void initState(){super.initState();_contact=TextEditingController(text:widget.debt?.contact??'');_note=TextEditingController(text:widget.debt?.note??'');_due=TextEditingController(text:widget.debt?.dueDate??'');}
  @override
  void dispose(){for(final c in [_contact,_note,_due,_principal,_reference]){c.dispose();}super.dispose();}
  @override
  Widget build(BuildContext context){final wallets=_wallets(ref),wallet=_selected(wallets,_walletId);
    return Scaffold(appBar:AppBar(title:Text(widget.debt==null?'New debt':'Edit debt details')),body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(24),children:[
      _field(_contact,'Contact / person',required:true,maxLength:100),
      if(widget.debt==null)...[
        SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(_borrowed?'Money I owe (borrowed)':'Money owed to me (lent)'),value:_borrowed,onChanged:_saving?null:(v)=>setState(()=>_borrowed=v)),
        _walletPicker(wallets,wallet,_saving?null:(id)=>setState((){_walletId=id;_principal.clear();})),
        _amount(_principal,wallet?.currency??AppCurrency.usd,'Original principal'),
        _field(_reference,'Unique bank/cash reference',required:true,maxLength:100),
        const Text('Records the original cash movement now. Borrowing is not income; lending is not an expense. Existing historical debts must not be entered again as a new cash movement.'),
      ],
      _field(_due,'Due date (optional)',date:true),_field(_note,'Notes (optional)',maxLength:1000),_errorNotice(_error,context),
      FilledButton(onPressed:_saving?null:() async {
        if(_saving || !_form.currentState!.validate())return;setState((){_saving=true;_error=null;});
        try {
          final repo=ref.read(planningRepositoryProvider)!;
          if(widget.debt==null)await repo.createDebt(contact:_contact.text,borrowed:_borrowed,principalMinor:Money.parseMinor(_principal.text,wallet!.currency)!,walletId:wallet.id!,reference:_reference.text,dueDate:_due.text,note:_note.text);
          else await repo.editDebt(widget.debt!.id,contact:_contact.text,dueDate:_due.text,note:_note.text);
          await _finishSaved(context,ref);
        } catch (_) {if(mounted)setState((){_saving=false;_error='Not recorded. Check the reference, dates and available wallet funds.';});}
      },child:Text(_saving?'Saving…':'Save debt'))
    ])));
  }
}
class RepaymentForm extends ConsumerStatefulWidget {
  const RepaymentForm({super.key,required this.debt,this.settle=false});final Debt debt;final bool settle;
  @override
  ConsumerState<RepaymentForm> createState()=>_RepaymentState();
}
class _RepaymentState extends ConsumerState<RepaymentForm> {
  final _form=GlobalKey<FormState>();final _amountController=TextEditingController(),_rate=TextEditingController(),_reference=TextEditingController();
  int? _walletId;bool _saving=false;String? _error;
  @override
  void initState(){super.initState();final wallets=ref.read(walletsProvider).valueOrNull?.wallets.where((w)=>!w.archived).toList()??<Wallet>[];
    final same=wallets.where((w)=>w.currency==widget.debt.currency).firstOrNull;_walletId=same?.id??wallets.firstOrNull?.id;
    if(widget.settle && same!=null)_amountController.text=Money.plain(widget.debt.remainingMinor,widget.debt.currency);}
  @override
  void dispose(){_amountController.dispose();_rate.dispose();_reference.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){final wallets=_wallets(ref),wallet=_selected(wallets,_walletId);final same=wallet?.currency==widget.debt.currency;
    String? preview;
    try {final minor=Money.parseMinor(_amountController.text,wallet?.currency??AppCurrency.usd);if(minor!=null&&minor>0)preview=Money.format(ExchangeRate.parse(same?'1':_rate.text).convert(minor,wallet!.currency,widget.debt.currency),widget.debt.currency);}catch(_){}
    return Scaffold(appBar:AppBar(title:Text(widget.settle?'Settle principal':'Record repayment')),body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(24),children:[
      Text('${widget.debt.contact} · Outstanding ${Money.format(widget.debt.remainingMinor,widget.debt.currency)}'),
      const Text('Principal only. Interest or fees belong in a separate income/expense entry.'),const SizedBox(height:16),
      _walletPicker(wallets,wallet,_saving?null:(id)=>setState((){_walletId=id;_amountController.clear();_rate.clear();})),
      TextFormField(controller:_amountController,onChanged:(_)=>setState((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:'Wallet cash amount (${wallet?.currency.code??''})'),validator:(v)=>(Money.parseMinor(v??'',wallet?.currency??AppCurrency.usd)??0)>0?null:'Enter a positive amount'),
      if(!same)TextFormField(controller:_rate,onChanged:(_)=>setState((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:'Manual rate: 1 ${wallet?.currency.code??'wallet currency'} in ${widget.debt.currency.code}',helperText:'The rate and both amounts are saved. No rate is fetched.'),
        validator:(v){try{ExchangeRate.parse(v??'');return null;}catch(_){return 'Enter a valid positive rate';}}),
      if(preview!=null)Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text('Principal repaid: $preview')),
      _field(_reference,'Unique repayment reference',required:true,maxLength:100),_errorNotice(_error,context),
      FilledButton(onPressed:_saving?null:() async {
        if(_saving || !_form.currentState!.validate()||wallet==null)return;
        final minor=Money.parseMinor(_amountController.text,wallet.currency)!;
        try {final converted=ExchangeRate.parse(same?'1':_rate.text).convert(minor,wallet.currency,widget.debt.currency);
          if(widget.settle && converted!=widget.debt.remainingMinor){setState(()=>_error='For settlement, the converted principal must equal the outstanding amount.');return;}
          setState((){_saving=true;_error=null;});
          await ref.read(planningRepositoryProvider)!.repay(widget.debt.id,walletId:wallet.id!,walletMinor:minor,rate:same?'1':_rate.text,reference:_reference.text);
          await _finishSaved(context,ref);
        } catch (_) {if(mounted)setState((){_saving=false;_error='Not recorded. Check for overpayment, duplicate reference or insufficient available funds.';});}
      },child:Text(_saving?'Saving…':'Record principal repayment'))
    ])));
  }
}
class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({super.key,this.goal});final SavingsGoal? goal;
  @override
  ConsumerState<GoalForm> createState()=>_GoalFormState();
}
class _GoalFormState extends ConsumerState<GoalForm> {
  final _form=GlobalKey<FormState>();late final TextEditingController _name,_target,_dateController;int? _walletId;int _color=0xFF10B981;String _icon='savings';
  bool _saving=false;String? _error;
  @override
  void initState(){super.initState();final g=widget.goal;_walletId=g?.walletId;_name=TextEditingController(text:g?.name??'');_target=TextEditingController(text:g==null?'':Money.plain(g.targetMinor,g.currency));_dateController=TextEditingController(text:g?.targetDate??'');_color=g?.row['color'] as int? ??_color;_icon=g?.row['icon'] as String? ??_icon;}
  @override
  void dispose(){_name.dispose();_target.dispose();_dateController.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){final wallets=_wallets(ref),wallet=_selected(wallets,_walletId);return Scaffold(appBar:AppBar(title:Text(widget.goal==null?'New savings goal':'Edit savings goal')),
    body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(24),children:[
      _field(_name,'Goal name',required:true,maxLength:100),_walletPicker(wallets,wallet,widget.goal!=null||_saving?null:(id)=>setState((){_walletId=id;_target.clear();})),
      const Text('Reserve funds inside this wallet. The wallet and currency stay fixed after creation.'),
      _amount(_target,wallet?.currency??widget.goal?.currency??AppCurrency.usd,'Target amount'),_field(_dateController,'Target date (optional)',date:true),
      DropdownButtonFormField<String>(isExpanded: true, initialValue:_icon,decoration:const InputDecoration(labelText:'Icon'),items:[for(final icon in ['savings','home','travel','education'])DropdownMenuItem(value:icon,child:Text(icon))],onChanged:(v)=>setState(()=>_icon=v!)),
      Wrap(spacing:12,children:[for(final color in [0xFF10B981,0xFF3B82F6,0xFF8B5CF6,0xFFF97316])IconButton(tooltip:'Goal color',icon:Icon(_color==color?Icons.check_circle:Icons.circle,color:Color(color)),onPressed:()=>setState(()=>_color=color))]),
      _errorNotice(_error,context),FilledButton(onPressed:_saving?null:() async {
        if(_saving || !_form.currentState!.validate()||wallet==null)return;setState((){_saving=true;_error=null;});
        try {await ref.read(planningRepositoryProvider)!.saveGoal(id:widget.goal?.id,goalName:_name.text,walletId:wallet.id!,targetMinor:Money.parseMinor(_target.text,wallet.currency)!,targetDate:_dateController.text,color:_color,icon:_icon);
          await _finishSaved(context,ref);
        } catch (_) {if(mounted)setState((){_saving=false;_error='Could not save. Check the active wallet, target and date.';});}
      },child:Text(_saving?'Saving…':'Save goal'))
    ])));
  }
}
class RecurringForm extends ConsumerStatefulWidget {
  const RecurringForm({super.key,this.rule});final RecurringRule? rule;
  @override
  ConsumerState<RecurringForm> createState()=>_RecurringFormState();
}
class _RecurringFormState extends ConsumerState<RecurringForm> {
  final _form=GlobalKey<FormState>();late final TextEditingController _name,_amountController,_start,_end,_rate;
  TransactionType _type=TransactionType.expense;String _category='other',_frequency='monthly';int? _walletId,_projectId;
  bool _automatic=false,_saving=false;String? _error;
  @override
  void initState(){super.initState();final r=widget.rule;_name=TextEditingController(text:r?.name??'');_amountController=TextEditingController(text:r==null?'':Money.plain(r.amountMinor,r.currency));
    _start=TextEditingController(text:r?.row['start_date'] as String? ??CivilSchedule.key(DateTime.now()));_end=TextEditingController(text:r?.endDate??'');_rate=TextEditingController(text:r?.row['project_rate'] as String? ??'');
    if(r!=null){_type=TransactionType.fromStorage(r.row['type'] as String);_category=r.row['category_id'] as String;_frequency=r.row['frequency'] as String;_walletId=r.walletId;_projectId=r.row['project_id'] as int?;_automatic=r.automatic;}}
  @override
  void dispose(){for(final c in [_name,_amountController,_start,_end,_rate]){c.dispose();}super.dispose();}
  @override
  Widget build(BuildContext context){final wallets=_wallets(ref),wallet=_selected(wallets,_walletId);final projects=ref.watch(projectsProvider).valueOrNull?.projects.where((p)=>!p.isArchived).toList();
    final project=projects?.where((p)=>p.id==_projectId).firstOrNull;
    return Scaffold(appBar:AppBar(title:Text(widget.rule==null?'New recurring rule':'Edit recurring rule')),
      body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(24),children:[
        _field(_name,'Rule name',required:true,maxLength:100),
        DropdownButtonFormField<TransactionType>(isExpanded: true, initialValue:_type,decoration:const InputDecoration(labelText:'Type'),
          items:[for(final t in TransactionType.values)DropdownMenuItem(value:t,child:Text(t.label))],onChanged:_saving?null:(v)=>setState((){_type=v!;_category=_type.isIncome?'other_income':'other';})),
        const SizedBox(height:16),_walletPicker(wallets,wallet,_saving?null:(id)=>setState((){_walletId=id;_amountController.clear();_rate.clear();})),
        _amount(_amountController,wallet?.currency??AppCurrency.usd,'Amount'),
        DropdownButtonFormField<String>(isExpanded: true, key:ValueKey(_type),initialValue:_category,decoration:const InputDecoration(labelText:'Category'),
          items:[for(final c in Categories.forType(_type))DropdownMenuItem(value:c.id,child:Text(c.name))],onChanged:(v)=>setState(()=>_category=v!)),
        const SizedBox(height:16),DropdownButtonFormField<int>(initialValue:project?.id??0,isExpanded:true,decoration:const InputDecoration(labelText:'Project (optional)'),
          items:[const DropdownMenuItem(value:0,child:Text('No project')),for(final p in projects??[])DropdownMenuItem<int>(value:p.id,child:Text('${p.name} · ${p.currency.code}',overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>setState((){_projectId=v==0?null:v;_rate.clear();})),
        if(project!=null && project.currency!=wallet?.currency)_field(_rate,'Fixed manual project rate',required:true),
        if(project!=null)const Text('For a foreign-currency project, this explicitly entered rate is retained per occurrence. Review it when rates change. Client receipts must be recorded separately with their unique payment reference.'),
        const SizedBox(height:16),DropdownButtonFormField<String>(isExpanded: true, initialValue:_frequency,decoration:const InputDecoration(labelText:'Frequency'),
          items:[for(final f in ['daily','weekly','monthly','yearly'])DropdownMenuItem(value:f,child:Text(f))],onChanged:(v)=>setState(()=>_frequency=v!)),
        _field(_start,'Start date',date:true,required:true),_field(_end,'End date (optional)',date:true),
        const Text('Dates follow the device-local calendar. Month-end and leap-day schedules retain their original anchor. A past start date catches up all missed occurrences. Pending occurrences keep their original amount and rate when a rule is edited.'),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Automatic ledger recording'),subtitle:const Text('Off: review and confirm each occurrence. On: creates bookkeeping entries on open/resume, never bank payments.'),value:_automatic,onChanged:(v)=>setState(()=>_automatic=v)),
        _errorNotice(_error,context),FilledButton(onPressed:_saving?null:() async {
          if(_saving || !_form.currentState!.validate()||wallet==null)return;setState((){_saving=true;_error=null;});
          try {await ref.read(planningRepositoryProvider)!.saveRule(id:widget.rule?.id,ruleName:_name.text,type:_type,amountMinor:Money.parseMinor(_amountController.text,wallet.currency)!,walletId:wallet.id!,categoryId:_category,
            projectId:_projectId,projectRate:_rate.text,frequency:_frequency,startDate:_start.text,endDate:_end.text.isEmpty?null:_end.text,automatic:_automatic);
            try { await ref.read(planningRepositoryProvider)!.reconcile(); } catch (_) { if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Rule saved. Review pending entries after the next reconciliation.'))); }
            await _finishSaved(context,ref);
          } catch (_) {if(mounted)setState((){_saving=false;_error='Could not save. Check start/end dates, wallet, project and manual rate.';});}
        },child:Text(_saving?'Saving…':'Save recurring rule'))
      ])));
  }
}
