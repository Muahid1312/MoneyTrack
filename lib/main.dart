import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'data/storage/access_guard.dart';
import 'data/storage/app_runtime.dart';
import 'data/storage/generation_store.dart';
import 'data/storage/portable_snapshot.dart';
import 'features/documents/application/document_service.dart';
import 'features/reports/application/report_exporter.dart';
import 'features/security/application/security_service.dart';
import 'features/security/presentation/security_widgets.dart';
import 'features/planning/application/reminder_service.dart';

import 'app/app.dart';
import 'data/database/app_database.dart';
import 'data/repositories/planning_repository.dart';
import 'data/repositories/project_repository.dart';
import 'data/repositories/providers.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/repositories/wallet_repository.dart';
import 'features/planning/application/planning_providers.dart';
import 'features/projects/application/project_providers.dart';
import 'features/transactions/application/transactions_controller.dart';
import 'features/wallets/application/wallet_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts are bundled in assets/google_fonts; never hit the network.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/google_fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Plus Jakarta Sans'], license);
    yield LicenseEntryWithLineBreaks(['DejaVu Sans'], await rootBundle.loadString('assets/report_fonts/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks(['Noto Sans Arabic'], await rootBundle.loadString('assets/report_fonts/NOTO-LICENSE.txt'));
  });

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    statusBarColor: Colors.transparent,
  ));

  await _launchApplication();
}

ProviderContainer? _currentContainer;
AppDatabase? _currentDatabase;
GenerationStore? _generationStore;

Future<void> _replaceGeneration(PreparedGeneration stage) async {
  final store=_generationStore!;final prefs=await SharedPreferences.getInstance();
  AccessGuard.maintenance=true;
  runApp(const MaterialApp(home:Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[CircularProgressIndicator(),Text('Replacing validated data…')])))));
  await WidgetsBinding.instance.endOfFrame;
  _currentContainer?.dispose();_currentContainer=null;
  await _currentDatabase?.close();_currentDatabase=null;
  try {
    // Cancel old OS reminder metadata before selecting a different financial set.
    try {await ReminderService.channel.invokeMethod('replace',[]);} on MissingPluginException {} on PlatformException {}
    await store.beginRestore(stage.id,prefs);
    RuntimeNotice.message='Backup restored and verified. Review recurring rules before re-enabling reminders.';
    if(!await _launchApplication())throw StateError('Restored data could not be opened');
  } catch (_) {
    await store.rollback(prefs);
    RuntimeNotice.message='Restore failed. The previous financial data and settings were recovered.';
    await _launchApplication();
    rethrow;
  } finally {AccessGuard.maintenance=false;}
}
Future<bool> _launchApplication() async {
  AppDatabase? database;
  try {
    AccessGuard.maintenance=true;
    final prefs=await SharedPreferences.getInstance();
    final support=await getApplicationSupportDirectory();
    final store=_generationStore??=GenerationStore(Directory(p.join(support.path,'moneytrack-data')));
    await store.initialize(prefs);
    try {
      if(await FileSystemEntity.type(p.join(store.current.path,'moneytrack.db'),followLinks:false)!=FileSystemEntityType.file)throw StateError('Active database missing');
      database=await AppDatabase.open(path:p.join(store.current.path,'moneytrack.db'));
      await PortableSnapshot.validate(database.db);
    } catch (_) {
      await database?.close();database=null;
      if(!await store.journal.exists())rethrow;
      await store.rollback(prefs);
      if(await FileSystemEntity.type(p.join(store.current.path,'moneytrack.db'),followLinks:false)!=FileSystemEntityType.file)throw StateError('Active database missing');
      database=await AppDatabase.open(path:p.join(store.current.path,'moneytrack.db'));
      await PortableSnapshot.validate(database.db);
      RuntimeNotice.message='An interrupted replacement was rolled back. Previous data was recovered.';
    }
    final activeDatabase=database;
    if(activeDatabase==null)throw StateError('Database unavailable');
    final runtime=AppRuntime(database:activeDatabase,store:store,preferences:prefs,restore:_replaceGeneration);
    final container=ProviderContainer(overrides:[
      appRuntimeProvider.overrideWithValue(runtime),
      planningRepositoryProvider.overrideWithValue(PlanningRepository(activeDatabase)),
      projectRepositoryProvider.overrideWithValue(ProjectRepository(activeDatabase)),
      walletRepositoryProvider.overrideWithValue(WalletRepository(activeDatabase)),
      transactionRepositoryProvider.overrideWithValue(SqfliteTransactionRepository(activeDatabase)),
      settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
    ]);
    try {
      await container.read(transactionsProvider.future);
      await container.read(walletsProvider.future);
      await AttachmentRepository(runtime).cleanup();
      await ReportExporter.cleanup();
      await store.finishOpen();
    } catch (_) {container.dispose();await activeDatabase.close();database=null;rethrow;}
    _currentContainer=container;_currentDatabase=database;
    AccessGuard.maintenance=false;
    runApp(AppLockGate(security:SecurityController.instance,builder:()=>UncontrolledProviderScope(container:container,child:const MoneyTrackApp())));
    return true;
  } catch (_) {
    await database?.close();
    AccessGuard.maintenance=false;
    // Error text deliberately excludes SQLite arguments and sensitive values.
    runApp(MaterialApp(home:Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.lock_outline,size:48),const SizedBox(height:16),
      const Text('Could not open your financial data',textAlign:TextAlign.center),
      const Text('Stored generations have not been reset. Retry opening the app; keep app data intact if recovery is needed.',textAlign:TextAlign.center),
      FilledButton(onPressed:_launchApplication,child:const Text('Retry')),
    ])))))));
    WidgetsBinding.instance.addPostFrameCallback((_) async {try {await PlatformSecureStore.channel.invokeMethod('privacyReady');}catch(_){}});
    return false;
  }
}
