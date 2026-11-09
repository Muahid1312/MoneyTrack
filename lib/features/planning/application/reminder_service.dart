import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/planning.dart';

class ReminderService {
  static const channel=MethodChannel('moneytrack/reminders');
  bool get supported => !kIsWeb && defaultTargetPlatform==TargetPlatform.android;
  Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool('local_reminders')??false;
  Future<bool> active() async {
    if (!supported || !await enabled()) return false;
    try { return await channel.invokeMethod<bool>('allowed') ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }
  Future<bool> setEnabled(bool enabled) async {
    var allowed=false;
    if(enabled && supported) {
      try { allowed=await channel.invokeMethod<bool>('request')??false; } on PlatformException { allowed=false; }
      on MissingPluginException { allowed=false; }
    }
    await (await SharedPreferences.getInstance()).setBool('local_reminders',enabled && allowed);
    if(!(enabled && allowed) && supported) {
      try { await channel.invokeMethod('replace',[]); }
      on PlatformException { /* The in-app upcoming list remains available. */ }
      on MissingPluginException { /* Unsupported native host. */ }
    }
    return enabled && allowed;
  }
  Future<void> refresh(PlanningSnapshot data) async {
    if(!supported)return;
    if(!await enabled()) { await channel.invokeMethod('replace',[]);return; }
    if(await channel.invokeMethod<bool>('allowed')!=true)return;
    final items=<Map<String,Object>>[];
    void add(int id,int kind,String date,String title,String body,{Map<String,Object> extra=const {}}) {
      final stable=(id*8+kind)%2147483647;
      items.add({'id':stable,'key':'$kind:$id:$date','date':date,'title':title,'body':body,...extra});
    }
    for(final d in data.debts.where((d)=>d.remainingMinor>0 && d.dueDate!=null)) {
      add(d.id,1,d.dueDate!,'Debt due: ${d.contact}','Principal is still outstanding. Open MoneyTrack to review or record a repayment.');
    }
    for(final g in data.goals.where((g)=>g.status=='active' && g.allocatedMinor<g.targetMinor && g.targetDate!=null)) {
      add(g.id,2,g.targetDate!,'Savings deadline: ${g.name}','Your target is not fully reserved yet. This is a reminder only.');
    }
    for(final r in data.rules.where((r)=>r.state=='active')) {
      final pending=data.occurrences.where((o)=>o.ruleId==r.id && o.status=='pending').toList();
      if(pending.isNotEmpty)add(r.id,3,pending.last.dueDate,'Recurring entry awaiting review: ${r.name}',
        'One or more occurrences need review. A reminder is not proof of payment.');
      if(!r.finished)add(r.id,4,r.nextDate,'Recurring entry due: ${r.name}',
        'Review MoneyTrack when convenient. This reminder does not make a payment or create a ledger entry.',extra:{
          'frequency':r.row['frequency'] as String,'start_date':r.row['start_date'] as String,
          'next_index':r.row['next_index'] as int,'key_base':'4:${r.id}',
          if(r.endDate!=null)'end_date':r.endDate!,
        });
    }
    await channel.invokeMethod('replace',items);
  }
}
