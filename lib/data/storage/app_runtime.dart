import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/app_database.dart';
import 'generation_store.dart';

class AppRuntime {
  AppRuntime({required this.database,required this.store,required this.preferences,required this.restore});
  final AppDatabase database;final GenerationStore store;final SharedPreferences preferences;
  final Future<void> Function(PreparedGeneration stage) restore;
}
final appRuntimeProvider=Provider<AppRuntime?>((ref)=>null);
abstract final class RuntimeNotice {static String? message;}
