import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/planning.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../transactions/presentation/transaction_actions.dart';
import '../../wallets/application/wallet_providers.dart';
import '../application/planning_providers.dart';
import '../application/reminder_service.dart';
import 'planning_forms.dart';

Future<bool> planningAction(BuildContext context,WidgetRef ref,Future<void> Function() action) async {
  try { await action(); }
  catch (_) { if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Not recorded. Check available funds, outstanding principal, references and wallet/project status.')));return false; }
  try { await refreshPlanning(ref); }
  catch (_) { if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Saved. The display could not refresh; reopen this screen to reload stored records.'))); }
  return true;
}
Widget planningError(WidgetRef ref)=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
  const Text('Could not load planning records'),TextButton(onPressed:()=>ref.invalidate(planningProvider),child:const Text('Retry'))]));

class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});
  @override
  ConsumerState<PlanningScreen> createState()=>_PlanningState();
}
class _PlanningState extends ConsumerState<PlanningScreen> {
  bool _enabled=false,_changing=false;
  @override
  void initState(){super.initState();ReminderService().active().then((v){if(mounted)setState(()=>_enabled=v);});}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Planning')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      Text('Plan ahead',style:Theme.of(context).textTheme.headlineMedium),
      const Text('Debt principal, reserved savings and scheduled ledger entries stay separate from everyday income and spending.'),
      const SizedBox(height:20),
      for(final item in [(Icons.handshake_outlined,'Debts & loans',const DebtsScreen()),
        (Icons.savings_outlined,'Savings goals',const GoalsScreen()),(Icons.event_repeat,'Recurring & upcoming',const RecurringScreen())])
        Card(child:ListTile(leading:Icon(item.$1),title:Text(item.$2),trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>item.$3)))),
      const SizedBox(height:20),
      if(ref.watch(planningBusyProvider))const LinearProgressIndicator(),
      if(ref.watch(planningErrorProvider)!=null)Text(ref.watch(planningErrorProvider)!),
      OutlinedButton.icon(icon:const Icon(Icons.sync),label:const Text('Reconcile due entries'),
        onPressed:ref.watch(planningBusyProvider)?null:() async {
          ref.read(planningBusyProvider.notifier).state=true;
          try { await planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.reconcile()); }
          finally { ref.read(planningBusyProvider.notifier).state=false; }
        }),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Local reminders'),value:_enabled,
        subtitle:const Text('Android notifications for debts, savings and recurring dates. No financial entry is created by a reminder.'),
        onChanged:_changing?null:(v) async {
          setState(()=>_changing=true);
          try {
            final enabled=await ReminderService().setEnabled(v);
            if(mounted)setState(()=>_enabled=enabled);
            final data=await ref.read(planningProvider.future);if(data!=null)await ReminderService().refresh(data);
            if(v && !enabled && context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Notifications are unavailable or permission was denied. All financial features still work.')));
          } catch (_) { if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not enable reminders. You can still review upcoming items here.'))); }
          finally {if(mounted)setState(()=>_changing=false);}
        }),
      const Text('Reminders use local calendar dates around 09:00. Android may delay delivery. Pending entries are reconciled when the app opens or resumes. Automatic recording is bookkeeping only; it never sends a payment.'),
    ]));
}

class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});
  @override
  ConsumerState<DebtsScreen> createState()=>_DebtsState();
}
class _DebtsState extends ConsumerState<DebtsScreen> {
  String _status='All';
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Debts & loans')),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const DebtForm())),icon:const Icon(Icons.add),label:const Text('New debt')),
    body:ref.watch(planningProvider).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(_,_)=>planningError(ref),data:(data){
      final debts=data?.debts.where((d)=>_status=='All'||d.status(DateTime.now())==_status).toList()??<Debt>[];
      return ListView(padding:const EdgeInsets.fromLTRB(20,16,20,100),children:[
        DropdownButtonFormField<String>(isExpanded: true, initialValue:_status,decoration:const InputDecoration(labelText:'Status'),
          items:[for(final s in ['All','Active','Partially paid','Overdue','Settled'])DropdownMenuItem(value:s,child:Text(s))],onChanged:(v)=>setState(()=>_status=v!)),
        const SizedBox(height:16),if(debts.isEmpty)const Text('No matching debts. Record borrowing or lending to begin.'),
        for(final d in debts)Card(child:ListTile(title:Text(d.contact),
          subtitle:Text('${d.borrowed?'Money I owe':'Money owed to me'} · ${d.status(DateTime.now())}${d.dueDate==null?'':'\nDue ${d.dueDate}'}'),
          trailing:Text('${Money.format(d.remainingMinor,d.currency)}\n${d.currency.code}'),
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>DebtDetailScreen(id:d.id)))))
      ]);
    }));
}
class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key,required this.id});final int id;
  @override
  Widget build(BuildContext context,WidgetRef ref)=>ref.watch(planningProvider).when(
    loading:()=>Scaffold(appBar:AppBar(),body:const Center(child:CircularProgressIndicator())),
    error:(_,_)=>Scaffold(appBar:AppBar(),body:planningError(ref)),data:(data){
      final d=data?.debts.where((d)=>d.id==id).firstOrNull;
      if(d==null)return Scaffold(appBar:AppBar(),body:const Center(child:Text('Debt not found')));
      return Scaffold(appBar:AppBar(title:Text(d.contact),actions:[IconButton(tooltip:'Edit nonfinancial details',icon:const Icon(Icons.edit_outlined),
        onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>DebtForm(debt:d))))]),
        body:ListView(padding:const EdgeInsets.all(24),children:[
          Text(d.borrowed?'Money I owe':'Money owed to me',style:Theme.of(context).textTheme.titleLarge),
          Text(d.status(DateTime.now())),Text('Created ${DateTime.fromMillisecondsSinceEpoch(d.row['created_at'] as int).toLocal()}'),
          Text('Principal: ${Money.format(d.principalMinor,d.currency)} (${d.currency.code})'),
          Text('Repaid: ${Money.format(d.repaidMinor,d.currency)}'),
          Text('Outstanding: ${Money.format(d.remainingMinor,d.currency)}',style:Theme.of(context).textTheme.headlineSmall),
          if(d.dueDate!=null)Text('Due ${d.dueDate}'),if(d.note.isNotEmpty)Text(d.note),
          const SizedBox(height:16),const Text('Principal movements are cash movements, never income or expenses. Interest and fees can be recorded separately as ordinary transactions.'),
          if(d.remainingMinor>0)Wrap(spacing:12,children:[
            FilledButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>RepaymentForm(debt:d))),child:const Text('Record repayment')),
            OutlinedButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>RepaymentForm(debt:d,settle:true))),child:const Text('Settle outstanding principal'))]),
          const Divider(height:32),Text('Wallet movement history',style:Theme.of(context).textTheme.titleLarge),
          for(final p in data!.postings.where((p)=>p.debtId==id))Column(crossAxisAlignment:CrossAxisAlignment.start,children:[ListTile(contentPadding:EdgeInsets.zero,isThreeLine:true,
            title:Text('${p.origin?'Original principal':'Repayment'}${p.voided?' · Voided':''}'),
            subtitle:Text('${ref.watch(walletsProvider).valueOrNull?.wallets.where((w)=>w.id==p.walletId).firstOrNull?.name??'Wallet'} · ${p.reference}\n${Money.format(p.principalMinor,d.currency)} principal · rate ${p.rate}\n${p.occurredAt.toLocal()}'),
            trailing:Text(Money.format(p.signedMinor,p.currency,signed:true))),
              if(!p.origin && !p.voided)TextButton(onPressed:() async {
                final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Void repayment?'),content:const Text('This reverses the wallet movement and restores outstanding principal. The audit record remains.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Void'))]));
                if(yes==true && context.mounted)await planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.voidRepayment(p.id));
              },child:const Text('Void'))]),
        ]));
    });
}

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Savings goals')),
    floatingActionButton:FloatingActionButton.extended(icon:const Icon(Icons.add),label:const Text('New goal'),
      onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const GoalForm()))),
    body:ref.watch(planningProvider).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(_,_)=>planningError(ref),data:(data)=>ListView(padding:const EdgeInsets.fromLTRB(20,16,20,100),children:[
      const Text('Goals reserve money inside a wallet. Reserved savings are already included in wallet balances, so they are never added to total cash again.'),
      if(data?.goals.isEmpty??true)const Padding(padding:EdgeInsets.all(24),child:Text('No savings goals yet.')),
      for(final g in data?.goals??<SavingsGoal>[])Card(child:ListTile(leading:Icon(const {'savings':Icons.savings_outlined,'home':Icons.home_outlined,'travel':Icons.flight_outlined,'education':Icons.school_outlined}[g.row['icon']]??Icons.savings_outlined,color:Color(g.row['color'] as int)),
        title:Text(g.name),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${g.status} · ${g.currency.code}${g.targetDate==null?'':' · Due ${g.targetDate}'}'),
          LinearProgressIndicator(value:g.progress.clamp(0.0,1.0).toDouble()),
          Text('${Money.format(g.allocatedMinor,g.currency)} / ${Money.format(g.targetMinor,g.currency)}')]),
        onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>GoalDetailScreen(id:g.id)))))
    ])));
}
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key,required this.id});final int id;
  Future<void> _move(BuildContext context,WidgetRef ref,SavingsGoal goal,bool withdraw) async {
    final controller=TextEditingController();final form=GlobalKey<FormState>();
    final reference='goal-${DateTime.now().microsecondsSinceEpoch}';
    final result=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(withdraw?'Withdraw reservation':'Reserve savings'),
      content:Form(key:form,child:TextFormField(controller:controller,keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:'Amount (${goal.currency.code})',helperText:withdraw?'Releases reserved funds. No income is recorded.':'Reserves available wallet funds. No expense is recorded.',helperMaxLines:2),
        validator:(v)=>(Money.parseMinor(v??'',goal.currency)??0)>0?null:'Enter a positive amount')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:(){if(form.currentState!.validate())Navigator.pop(ctx,true);},child:Text(withdraw?'Withdraw':'Reserve'))]));
    if(result==true && context.mounted)await planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.goalEvent(id,Money.parseMinor(controller.text,goal.currency)!*(withdraw?-1:1),reference));
    controller.dispose();
  }
  @override
  Widget build(BuildContext context,WidgetRef ref)=>ref.watch(planningProvider).when(loading:()=>Scaffold(appBar:AppBar(),body:const Center(child:CircularProgressIndicator())),
    error:(_,_)=>Scaffold(appBar:AppBar(),body:planningError(ref)),data:(data){
      final g=data?.goals.where((g)=>g.id==id).firstOrNull;if(g==null)return Scaffold(appBar:AppBar(),body:const Center(child:Text('Goal not found')));
      final wallets=ref.watch(walletsProvider).valueOrNull;
      return Scaffold(appBar:AppBar(title:Text(g.name),actions:[IconButton(tooltip:'Edit goal',icon:const Icon(Icons.edit_outlined),
        onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>GoalForm(goal:g))))]),body:ListView(padding:const EdgeInsets.all(24),children:[
          Text('${Money.format(g.allocatedMinor,g.currency)} reserved',style:Theme.of(context).textTheme.headlineSmall),
          Text('Target ${Money.format(g.targetMinor,g.currency)} · ${g.status}'),
          LinearProgressIndicator(value:g.progress.clamp(0.0,1.0).toDouble()),Text('${(g.progress*100).toStringAsFixed(1)}% funded'),
          if(g.targetDate!=null)Text('Target date ${g.targetDate}'),
          if(wallets!=null)...[Text('Wallet cash: ${Money.format(wallets.balances[g.walletId]??0,g.currency)}'),
            Text('Wallet reserved across goals: ${Money.format(wallets.reserved[g.walletId]??0,g.currency)}'),
            Text('Available wallet cash: ${Money.format(wallets.available(g.walletId),g.currency)}')],
          const Text('Allocations stay inside this wallet and do not increase net worth.'),const SizedBox(height:16),
          if(g.status!='archived')Wrap(spacing:12,runSpacing:8,children:[
            FilledButton(onPressed:()=>_move(context,ref,g,false),child:const Text('Allocate')),
            OutlinedButton(onPressed:()=>_move(context,ref,g,true),child:const Text('Withdraw')),
            if(g.status!='completed' && g.allocatedMinor>=g.targetMinor)OutlinedButton(onPressed:()=>planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.goalStatus(id,'completed')),child:const Text('Mark completed'))]),
          TextButton(onPressed:()=>planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.goalStatus(id,g.status=='archived'?'active':'archived')),child:Text(g.status=='archived'?'Restore goal':'Archive goal (keep reservations)')),
          Text('Contribution history',style:Theme.of(context).textTheme.titleLarge),
          for(final e in data!.savingsEvents.where((e)=>e['goal_id']==id))ListTile(contentPadding:EdgeInsets.zero,
            title:Text((e['delta_minor'] as int)>0?'Reserved':'Withdrawn'),subtitle:Text('${DateTime.fromMillisecondsSinceEpoch(e['occurred_at'] as int).toLocal()}'),
            trailing:Text(Money.format(e['delta_minor'] as int,g.currency,signed:true)))
        ]));
    });
}

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Recurring & upcoming')),
    floatingActionButton:FloatingActionButton.extended(icon:const Icon(Icons.add),label:const Text('New rule'),
      onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const RecurringForm()))),
    body:ref.watch(planningProvider).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(_,_)=>planningError(ref),data:(data){
      if(data==null)return const Center(child:Text('Planning storage unavailable'));
      final pending=data.occurrences.where((o)=>o.status=='pending').toList();
      return ListView(padding:const EdgeInsets.fromLTRB(20,16,20,100),children:[
        const Text('Due items are reminders to review your ledger. Recording confirms a bookkeeping entry; it does not make a bank payment.'),
        OutlinedButton.icon(icon:const Icon(Icons.sync),label:const Text('Check missed occurrences'),
          onPressed:()=>planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.reconcile())),
        Text('Awaiting confirmation',style:Theme.of(context).textTheme.titleLarge),
        if(pending.isEmpty)const Text('No pending occurrences.'),
        for(final o in pending)_OccurrenceTile(occurrence:o),
        const Divider(height:32),Text('Rules & next due dates',style:Theme.of(context).textTheme.titleLarge),
        if(data.rules.isEmpty)const Text('No recurring rules yet. Salary, rent and subscriptions can be scheduled here.'),
        for(final r in data.rules)Card(child:Column(children:[ListTile(title:Text(r.name),
          subtitle:Text('${r.state}${r.finished?' · Finished':' · Next ${r.nextDate}'}\n${r.automatic?'Automatic ledger recording':'Confirmation required'} · ${r.row['frequency']}'),
          trailing:Text('${Money.format(r.amountMinor,r.currency)}\n${r.currency.code}'),
          onTap:r.state=='cancelled'?null:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>RecurringForm(rule:r)))),
          if(r.state!='cancelled')Wrap(spacing:12,children:[TextButton(onPressed:()=>planningAction(context,ref,() async {
            await ref.read(planningRepositoryProvider)!.ruleState(r.id,r.state=='paused'?'active':'paused');
            await ref.read(planningRepositoryProvider)!.reconcile();
          }),child:Text(r.state=='paused'?'Resume':'Pause')),
          TextButton(onPressed:() async {
            final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Cancel rule?'),content:const Text('Future occurrences stop and pending ones are skipped. Recorded financial history remains.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Keep rule')),TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Cancel rule'))]));
            if(yes==true && context.mounted)await planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.ruleState(r.id,'cancelled'));
          },child:const Text('Cancel rule'))])])),
        ExpansionTile(title:const Text('Execution history'),children:[for(final o in data.occurrences.where((o)=>o.status!='pending'))_OccurrenceTile(occurrence:o)]),
      ]);
    }));
}
class _OccurrenceTile extends ConsumerWidget {
  const _OccurrenceTile({required this.occurrence});final RecurringOccurrence occurrence;
  @override
  Widget build(BuildContext context,WidgetRef ref){
    final o=occurrence;final payload=jsonDecode(o.row['payload'] as String) as Map;
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${payload['note']} · ${o.dueDate}',style:Theme.of(context).textTheme.titleMedium),
      Text('Scheduled ${payload['type']=='income'?'income':'expense'} · ${Money.format(payload['amount_minor'] as int,AppCurrency.requireCode(payload['currency'] as String))} (${payload['currency']}) · ${o.status}${o.status=='recorded'&&o.transactionId==null?' (entry deleted; history retained)':''}'),
      if(o.error!=null)Text(o.error!),
      if(o.status=='recorded' && o.transactionId!=null)TextButton(onPressed:() async {
        final tx=ref.read(transactionsProvider).valueOrNull?.where((t)=>t.id==o.transactionId).firstOrNull;
        if(tx==null)return;
        await TransactionActions.openEditor(context,ref,existing:tx);
        if(context.mounted)await refreshPlanning(ref);
      },child:const Text('View recorded entry (current values)')),
      if(o.status=='pending')Wrap(spacing:12,children:[TextButton(onPressed:()=>planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.confirmOccurrence(o.id)),child:const Text('Confirm ledger entry')),
        TextButton(onPressed:()=>planningAction(context,ref,()=>ref.read(planningRepositoryProvider)!.skipOccurrence(o.id)),child:const Text('Skip occurrence'))])
    ])));
  }
}
