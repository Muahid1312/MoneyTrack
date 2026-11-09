import 'dart:async';

/// UI lock and maintenance barriers also stop lifecycle-generated writes.
abstract final class AccessGuard {
  static bool locked = false;
  static bool maintenance = false;
  static Completer<void>? _unlock;
  static void setLocked(bool value) {
    locked=value;
    if(value) { _unlock??=Completer<void>(); }
    else { _unlock?.complete(); _unlock=null; }
  }
  static Future<void> waitForUnlock() async { if(locked)await (_unlock??=Completer<void>()).future; }
  static void writable() {
    if(locked || maintenance)throw StateError('Unlock the app and finish data maintenance before recording changes');
  }
}
