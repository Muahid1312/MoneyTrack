import 'dart:async';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/security_service.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key,required this.security,required this.builder});
  final SecurityController security;final Widget Function() builder;
  @override State<AppLockGate> createState()=>_GateState();
}
class _GateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _covered=false,_created=false;DateTime? _background;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);widget.security.addListener(_changed);widget.security.initialize();}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);widget.security.removeListener(_changed);super.dispose();}
  void _changed(){if(mounted)setState((){});}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.inactive){setState(()=>_covered=true);}
    if(state==AppLifecycleState.paused){_background=DateTime.now();if(widget.security.timeoutSeconds==0)widget.security.lock();}
    if(state==AppLifecycleState.resumed){final since=_background;
      if(since!=null && DateTime.now().difference(since).inSeconds>=widget.security.timeoutSeconds)widget.security.lock();
      _background=null;setState(()=>_covered=false);
    }
  }
  @override Widget build(BuildContext context){final security=widget.security;
    if(!_covered && security.ready)WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {await PlatformSecureStore.channel.invokeMethod('privacyReady');} on PlatformException {} on MissingPluginException {}
    });
    if(security.ready && !security.locked)_created=true;
    return Stack(textDirection:TextDirection.ltr,children:[
      if(_created)Offstage(offstage:security.locked||_covered,child:widget.builder()),
      if(!_created || security.locked)MaterialApp(debugShowCheckedModeBanner:false,theme:AppTheme.light(),darkTheme:AppTheme.dark(),home:_UnlockScreen(security:security)),
      if(_covered)const Positioned.fill(child:ColoredBox(color:Color(0xFF0B1512))),
    ]);
  }
}
class _UnlockScreen extends StatefulWidget {
  const _UnlockScreen({required this.security});final SecurityController security;
  @override State<_UnlockScreen> createState()=>_UnlockState();
}
class _UnlockState extends State<_UnlockScreen>{
  final _pin=TextEditingController();
  Timer? _retry;
  @override void dispose(){_retry?.cancel();_pin.dispose();super.dispose();}
  @override Widget build(BuildContext context){final s=widget.security;
    if(s.retrySeconds>0 && !(_retry?.isActive??false))_retry=Timer(const Duration(seconds:1),(){if(mounted)setState((){});});
    return Scaffold(body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:Column(children:[
    const Icon(Icons.lock_outline,size:48),const SizedBox(height:20),Text('Unlock MoneyTrack',style:Theme.of(context).textTheme.headlineSmall),
    if(!s.ready)const CircularProgressIndicator(),
    if(s.ready && s.configured)...[
      pinField(_pin,'App PIN'),const SizedBox(height:16),
      FilledButton(onPressed:s.busy||s.retrySeconds>0?null:() async {final pin=_pin.text;_pin.clear();await s.verify(pin,unlock:true);},child:Text(s.busy?'Verifying…':s.retrySeconds>0?'Try again in ${s.retrySeconds}s':'Unlock')),
      if(s.biometricEnabled)TextButton.icon(onPressed:s.busy?null:s.biometricUnlock,icon:const Icon(Icons.fingerprint),label:const Text('Use biometrics')),
    ],
    if(s.error!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text(s.error!,textAlign:TextAlign.center)),
    if(s.ready&&!s.configured&&s.error!=null)TextButton(onPressed:s.initialize,child:const Text('Retry device security')),
  ]))))));}
}
Widget pinField(TextEditingController controller,String label)=>Padding(padding:const EdgeInsets.symmetric(vertical:10),child:TextField(controller:controller,obscureText:true,
  keyboardType:TextInputType.number,maxLength:12,autocorrect:false,enableSuggestions:false,enableInteractiveSelection:false,
  decoration:InputDecoration(labelText:label,counterText:'')));
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override State<SecuritySettingsScreen> createState()=>_SecuritySettingsState();
}
class _SecuritySettingsState extends State<SecuritySettingsScreen>{
  final _current=TextEditingController(),_next=TextEditingController(),_confirm=TextEditingController();
  final security=SecurityController.instance;String? _message;bool _working=false;late int _timeout;late bool _biometric;
  @override void initState(){super.initState();_timeout=security.timeoutSeconds;_biometric=security.biometricEnabled;security.addListener(_changed);}
  void _changed(){if(mounted)setState((){});}
  @override void dispose(){security.removeListener(_changed);_current.dispose();_next.dispose();_confirm.dispose();super.dispose();}
  Future<void> _run(Future<void> Function() action) async {if(_working)return;setState(()=>_working=true);try{await action();if(mounted)setState(()=>_message='Security settings saved.');}catch(_){if(mounted)setState(()=>_message=security.error??'Could not change security settings. Verify your current PIN and confirm the new PIN.');}finally{_current.clear();_next.clear();_confirm.clear();if(mounted)setState(()=>_working=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('App security')),body:ListView(padding:const EdgeInsets.all(24),children:[
    const Text('App locking controls access to MoneyTrack. The live database is not encrypted by this PIN. Encrypted backups use a separate passphrase.'),
    if(!security.available)const Text('Secure app locking is unavailable on this platform.'),
    if(security.configured)pinField(_current,'Current PIN (required for changes)'),
    pinField(_next,security.configured?'New PIN':'Choose a 6–12 digit PIN'),pinField(_confirm,'Confirm new PIN'),
    FilledButton(onPressed:security.busy||_working||!security.available?null:()=>_run(()=>security.setPin(_current.text,_next.text,_confirm.text)),child:Text(security.configured?'Change PIN':'Enable app lock')),
    if(security.configured)...[
      const SizedBox(height:24),DropdownButtonFormField<int>(isExpanded: true, initialValue:_timeout,decoration:const InputDecoration(labelText:'Lock after backgrounding'),
        items:[for(final value in [0,30,60,300])DropdownMenuItem(value:value,child:Text(value==0?'Immediately':'$value seconds'))],onChanged:(security.busy||_working)?null:(v)=>setState(()=>_timeout=v!)),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Biometric unlock'),subtitle:const Text('Enrollment changes require your app PIN to enable biometrics again.'),value:_biometric,onChanged:(security.busy||_working)?null:(v)=>setState(()=>_biometric=v)),
      OutlinedButton(onPressed:(security.busy||_working)?null:()=>_run(()=>security.changeOptions(_current.text,timeout:_timeout,biometric:_biometric)),child:const Text('Save lock options')),
      OutlinedButton(onPressed:security.lock,child:const Text('Lock now')),
      TextButton(onPressed:(security.busy||_working)?null:()=>_run(()=>security.removePin(_current.text)),child:const Text('Remove app PIN')),
    ],
    if(_message!=null)Text(_message!),
    const Text('There is no recovery PIN. Keep your backup passphrase safe; it is never stored by the app.'),
  ]));
}
