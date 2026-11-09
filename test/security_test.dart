import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/data/storage/access_guard.dart';
import 'package:moneytrack/features/security/application/security_service.dart';
import 'package:moneytrack/features/security/presentation/security_widgets.dart';

class MemorySecureStore implements SecureStore {
  String? value;bool allowBiometric=false;bool unavailable=false;
  @override Future<String?> read() async {if(unavailable)throw StateError('Device security unavailable');return value;}
  @override Future<void> write(String? next) async {value=next;}
  @override Future<bool> biometric(bool enroll) async=>allowBiometric;
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown((){AccessGuard.setLocked(false);AccessGuard.maintenance=false;});
  test('salted PIN verifiers differ and no plaintext PIN is stored',() async {
    final a=MemorySecureStore(),b=MemorySecureStore();final first=SecurityController(a),second=SecurityController(b);
    await first.initialize();await second.initialize();await first.setPin('','246810','246810');await second.setPin('','246810','246810');
    expect(jsonDecode(a.value!)['salt'],isNot(jsonDecode(b.value!)['salt']));expect(jsonDecode(a.value!)['verifier'],isNot(jsonDecode(b.value!)['verifier']));
    expect(a.value, isNot(contains('246810')));expect(await first.verify('246810'),isTrue);expect(await first.verify('111111'),isFalse);
  },timeout:const Timeout(Duration(minutes:2)));
  test('attempt limits persist across controller restart',() async {
    final store=MemorySecureStore();final security=SecurityController(store);await security.initialize();await security.setPin('','246810','246810');security.lock();
    for(var i=0;i<5;i++){expect(await security.verify('111111',unlock:true),isFalse);}
    expect(security.retrySeconds,greaterThan(0));final restarted=SecurityController(store);await restarted.initialize();
    expect(restarted.locked,isTrue);expect(restarted.retrySeconds,greaterThan(0));expect(await restarted.verify('246810',unlock:true),isFalse);
  },timeout:const Timeout(Duration(minutes:3)));
  test('settings changes and PIN removal require the existing PIN',() async {
    final store=MemorySecureStore();final security=SecurityController(store);await security.initialize();
    await expectLater(security.setPin('','246810','246811'),throwsArgumentError);await security.setPin('','246810','246810');
    await expectLater(security.removePin('000000'),throwsStateError);expect(security.configured,isTrue);
    await expectLater(security.changeOptions('000000',timeout:30,biometric:false),throwsStateError);
    await security.setPin('246810','135790','135790');expect(await security.verify('135790'),isTrue);
    await security.removePin('135790');expect(store.value,isNull);expect(security.configured,isFalse);
  },timeout:const Timeout(Duration(minutes:3)));
  test('biometric failure retains the PIN fallback and never unlocks',() async {
    final store=MemorySecureStore()..allowBiometric=true;final security=SecurityController(store);await security.initialize();await security.setPin('','246810','246810');
    await security.changeOptions('246810',timeout:0,biometric:true);security.lock();store.allowBiometric=false;
    expect(await security.biometricUnlock(),isFalse);expect(security.locked,isTrue);expect(await security.verify('246810',unlock:true),isTrue);
  },timeout:const Timeout(Duration(minutes:2)));
  test('unavailable or corrupted secure storage fails closed',() async {
    final broken=MemorySecureStore()..unavailable=true;final security=SecurityController(broken);await security.initialize();expect(security.locked,isTrue);expect(security.error,isNotNull);
    final corrupt=MemorySecureStore()..value='{"version":999}';final other=SecurityController(corrupt);await other.initialize();expect(other.locked,isTrue);
  });
  test('malformed secure configuration fields fail closed',() async {
    final store=MemorySecureStore();final original=SecurityController(store);
    await original.initialize();await original.setPin('','246810','246810');
    final record=jsonDecode(store.value!) as Map<String,dynamic>;
    record['timeout']='never';store.value=jsonEncode(record);
    final restarted=SecurityController(store);await restarted.initialize();
    expect(restarted.locked,isTrue);expect(restarted.error,isNotNull);
  },timeout:const Timeout(Duration(minutes:2)));
  testWidgets('cold start hides protected screens and backgrounding locks immediately',(tester) async {
    final store=MemorySecureStore()..allowBiometric=true;final security=SecurityController(store);
    await tester.runAsync(() async {await security.initialize();await security.setPin('','246810','246810');await security.changeOptions('246810',timeout:0,biometric:true);});
    await tester.pumpWidget(AppLockGate(security:security,builder:()=>const MaterialApp(home:Scaffold(body:Text('Protected financial records')))));
    await tester.pumpAndSettle();expect(find.text('Protected financial records'),findsNothing);
    await tester.tap(find.text('Use biometrics'));await tester.pumpAndSettle();expect(find.text('Protected financial records'),findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();expect(find.text('Protected financial records'),findsNothing);
  });
}
