import 'dart:isolate';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/storage/access_guard.dart';

abstract interface class SecureStore {
  Future<String?> read();
  Future<void> write(String? value);
  Future<bool> biometric(bool enroll);
}
class PlatformSecureStore implements SecureStore {
  static const channel=MethodChannel('moneytrack/security');
  @override Future<String?> read()=>channel.invokeMethod<String>('read');
  @override Future<void> write(String? value)=>channel.invokeMethod<void>('write',value);
  @override Future<bool> biometric(bool enroll) async=>await channel.invokeMethod<bool>(enroll?'enroll':'authenticate')??false;
}
abstract final class SecureCrypto {
  static List<int> random(int length){final r=Random.secure();return List<int>.generate(length,(_)=>r.nextInt(256));}
  static Future<List<int>> derive(String password,List<int> salt,{int memory=19456,int iterations=2}) =>
      Isolate.run(() => _derive(password, salt, memory, iterations));
  static Future<List<int>> _derive(String password,List<int> salt,int memory,int iterations) async {
    final secret=SecretKeyData(utf8.encode(password),overwriteWhenDestroyed:true);
    SecretKey? result;
    try {result=await Argon2id(memory:memory,iterations:iterations,parallelism:1,hashLength:32).deriveKey(secretKey:secret,nonce:salt);
      return List<int>.from(await result.extractBytes());}
    finally {secret.destroy();result?.destroy();}
  }
  static bool equal(List<int> a,List<int> b){if(a.length!=b.length)return false;var difference=0;for(var i=0;i<a.length;i++){difference|=a[i]^b[i];}return difference==0;}
}
class SecurityController extends ChangeNotifier {
  SecurityController(this.store);
  static final instance=SecurityController(PlatformSecureStore());
  final SecureStore store;
  Map<String,dynamic>? _record;
  bool ready=false,locked=true,available=true,busy=false;
  String? error;
  bool get configured=>_record!=null;
  bool get biometricEnabled=>_record?['biometric']==true;
  int get timeoutSeconds=>(_record?['timeout'] as int?)??0;
  int get retrySeconds{final until=(_record?['until'] as int?)??0;final remaining=until-DateTime.now().millisecondsSinceEpoch;return remaining<=0?0:(remaining+999)~/1000;}
  Future<void> initialize() async {
    ready=false;locked=true;_record=null;AccessGuard.setLocked(true);
    try {
      if(store is PlatformSecureStore && !(Platform.isAndroid||Platform.isIOS)){available=false;locked=false;}
      else {
        final value=await store.read();
        if(value==null && store is PlatformSecureStore && (await SharedPreferences.getInstance()).getBool('device_lock_required')==true)throw StateError('Device lock credentials are missing');
        if(value!=null){final r=jsonDecode(value) as Map<String,dynamic>;
          if(r['version']!=1 || base64Decode(r['salt'] as String).length!=32 || base64Decode(r['verifier'] as String).length!=32 || r['biometric'] is! bool || ![0,30,60,300].contains(r['timeout']) || r['failures'] is! int || (r['failures'] as int)<0 || r['until'] is! int || (r['until'] as int)<0)throw const FormatException('Invalid lock configuration');
          _record=r;
        }
        locked=configured;
      }
      error=null;
    } catch (_) {locked=true;error='The device lock could not be opened. Keep app data intact and try unlocking the device or restarting the app.';}
    ready=true;AccessGuard.setLocked(locked);notifyListeners();
  }
  void lock(){if(!configured)return;locked=true;AccessGuard.setLocked(true);notifyListeners();}
  Future<bool> verify(String pin,{bool unlock=false}) async {
    if(busy || _record==null)return false;
    if(retrySeconds>0){error='Try again in $retrySeconds seconds.';notifyListeners();return false;}
    busy=true;error=null;notifyListeners();
    try {
      // Persist an attempt before doing expensive work; killing the process
      // during verification does not reset the attempt counter.
      final attempts=(_record!['failures'] as int? ??0)+1;_record!['failures']=attempts;
      if(attempts>=5){final exponent=min(attempts-5,5);_record!['until']=DateTime.now().millisecondsSinceEpoch+min(900,30*(1<<exponent))*1000;}
      await _persist();
      if(!RegExp(r'^\d{6,12}$').hasMatch(pin)){error='Enter your 6–12 digit PIN.';return false;}
      final actual=await SecureCrypto.derive(pin,base64Decode(_record!['salt'] as String));
      final ok=SecureCrypto.equal(actual,base64Decode(_record!['verifier'] as String));actual.fillRange(0,actual.length,0);
      if(ok){_record!['failures']=0;_record!['until']=0;await _persist();
        if(unlock){locked=false;AccessGuard.setLocked(false);}return true;}
      await _persist();error=retrySeconds>0?'Too many attempts. Try again in $retrySeconds seconds.':'Incorrect PIN.';return false;
    } catch (_) {locked=true;AccessGuard.setLocked(true);error='Could not verify the device lock. Try again.';return false;}
    finally {busy=false;notifyListeners();}
  }
  Future<bool> biometricUnlock() async {
    if(!biometricEnabled || busy || retrySeconds>0)return false;
    busy=true;error=null;notifyListeners();
    try {final ok=await store.biometric(false);if(ok){locked=false;AccessGuard.setLocked(false);}else{error='Biometric unlock was unavailable or cancelled. Use your app PIN.';}return ok;}
    catch (_){error='Biometrics changed or are unavailable. Use your app PIN.';return false;}
    finally {busy=false;notifyListeners();}
  }
  Future<void> setPin(String current,String next,String confirmation) async {
    final alreadyConfigured=configured;
    if(configured && !await verify(current))throw StateError('Current PIN verification failed');
    if(!RegExp(r'^\d{6,12}$').hasMatch(next)||next!=confirmation)throw ArgumentError('Choose and confirm a 6–12 digit PIN');
    if(busy)throw StateError('Verification is already in progress');busy=true;notifyListeners();
    List<int>? hash;
    try {final salt=SecureCrypto.random(32);hash=await SecureCrypto.derive(next,salt);
      final record=<String,dynamic>{'version':1,'salt':base64Encode(salt),'verifier':base64Encode(hash),'failures':0,'until':0,'timeout':timeoutSeconds,'biometric':false};
      await store.write(jsonEncode(record));
      if(store is PlatformSecureStore)await (await SharedPreferences.getInstance()).setBool('device_lock_required',true);
      _record=record;
      if(!alreadyConfigured){locked=false;AccessGuard.setLocked(false);}
    } finally {if(hash!=null)hash.fillRange(0,hash.length,0);busy=false;notifyListeners();}
  }
  Future<void> removePin(String current) async {if(!await verify(current))throw StateError('PIN verification failed');if(store is PlatformSecureStore)await (await SharedPreferences.getInstance()).setBool('device_lock_required',false);await store.write(null);_record=null;locked=false;AccessGuard.setLocked(false);notifyListeners();}
  Future<void> changeOptions(String current,{required int timeout,required bool biometric}) async {
    if(![0,30,60,300].contains(timeout)||!await verify(current))throw StateError('PIN verification failed');
    if(biometric && !await store.biometric(true))throw StateError('Biometric enrollment was cancelled or is unavailable');
    final next=<String,dynamic>{..._record!,'timeout':timeout,'biometric':biometric};
    await store.write(jsonEncode(next));_record=next;notifyListeners();
  }
  Future<void> _persist()=>store.write(jsonEncode(_record));
}
