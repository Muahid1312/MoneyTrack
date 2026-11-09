import 'dart:async';
import '../../../data/repositories/providers.dart';
import '../../../data/storage/access_guard.dart';
import '../../security/application/security_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/planning.dart';
import '../../../data/repositories/planning_repository.dart';
import '../../transactions/application/transactions_controller.dart';
import '../../wallets/application/wallet_providers.dart';
import 'reminder_service.dart';

final planningRepositoryProvider=Provider<PlanningRepository?>((ref)=>null);
final planningProvider=FutureProvider<PlanningSnapshot?>((ref) async {
  ref.watch(transactionsProvider);
  return ref.watch(planningRepositoryProvider)?.fetch();
});
final planningBusyProvider=StateProvider<bool>((ref)=>false);
final planningErrorProvider=StateProvider<String?>((ref)=>null);

Future<void> refreshPlanning(WidgetRef ref) async {
  ref.invalidate(transactionsProvider);
  await ref.read(transactionsProvider.future);
  ref.invalidate(walletsProvider); ref.invalidate(planningProvider);
  final data=await ref.read(planningProvider.future);
  if(data!=null) {
    try { await ReminderService().refresh(data); }
    catch (_) { ref.read(planningErrorProvider.notifier).state='Reminders could not be scheduled. Your financial records are unaffected.'; }
  }
}

class PlanningLifecycle extends ConsumerStatefulWidget {
  const PlanningLifecycle({super.key,required this.child});
  final Widget child;
  @override
  ConsumerState<PlanningLifecycle> createState()=>_LifecycleState();
}
class _LifecycleState extends ConsumerState<PlanningLifecycle> with WidgetsBindingObserver {
  bool _running=false;
  bool _wasLocked=true;
  Timer? _midnight;
  void _refreshClock() {
    if (!mounted) return;
    ref.invalidate(clockProvider);
    _midnight?.cancel();
    final now=DateTime.now();
    _midnight=Timer(DateTime(now.year,now.month,now.day+1).difference(now),_refreshClock);
  }
  void _securityChanged() {
    final locked=SecurityController.instance.locked;
    if (_wasLocked && !locked) { _refreshClock(); _reconcile(); }
    _wasLocked=locked;
  }
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);SecurityController.instance.addListener(_securityChanged);WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) { _refreshClock(); _reconcile(); } });}
  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);SecurityController.instance.removeListener(_securityChanged);_midnight?.cancel();super.dispose();}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed) { _refreshClock(); _reconcile(); }}
  Future<void> _reconcile() async {
    final repo=ref.read(planningRepositoryProvider); if(repo==null || _running || AccessGuard.locked || AccessGuard.maintenance)return;
    _running=true;ref.read(planningBusyProvider.notifier).state=true;
    try { await repo.reconcile();if(mounted)await refreshPlanning(ref); }
    catch (_) { if(mounted)ref.read(planningErrorProvider.notifier).state='Some recurring entries need attention. Open Planning to review pending entries.'; }
    finally { _running=false;if(mounted)ref.read(planningBusyProvider.notifier).state=false; }
  }
  @override
  Widget build(BuildContext context)=>widget.child;
}
