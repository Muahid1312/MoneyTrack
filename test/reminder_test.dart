import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/data/models/planning.dart';
import 'package:moneytrack/features/planning/application/reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const empty=PlanningSnapshot(debts:[],postings:[],goals:[],savingsEvents:[],rules:[],occurrences:[]);
  setUp((){SharedPreferences.setMockInitialValues({});debugDefaultTargetPlatformOverride=TargetPlatform.android;});
  tearDown((){debugDefaultTargetPlatformOverride=null;TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ReminderService.channel,null);});
  test('permission denial leaves reminders disabled without affecting records',() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ReminderService.channel,(call) async=>call.method=='request'?false:true);
    final service=ReminderService();expect(await service.setEnabled(true),isFalse);expect(await service.enabled(),isFalse);
    await service.refresh(empty);
  });
  test('disable cancels scheduled reminders and persists the preference',() async {
    final calls=<MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ReminderService.channel,(call) async {calls.add(call);return true;});
    final service=ReminderService();expect(await service.setEnabled(true),isTrue);await service.setEnabled(false);
    expect(await service.enabled(),isFalse);expect(calls.any((c)=>c.method=='replace' && (c.arguments as List).isEmpty),isTrue);
  });
  test('unavailable native bridge is handled as unavailable permission',() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ReminderService.channel,(_) async=>throw MissingPluginException());
    expect(await ReminderService().setEnabled(true),isFalse);
  });
}
