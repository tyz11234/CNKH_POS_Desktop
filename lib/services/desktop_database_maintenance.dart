import 'dart:async';

/// Coordinates background database polling with file-level maintenance such as
/// backup restore. Work already inside [run] drains before a pause completes;
/// new work waits until [resume].
class DesktopDatabaseMaintenance {
  DesktopDatabaseMaintenance._();
  static final DesktopDatabaseMaintenance shared =
      DesktopDatabaseMaintenance._();

  bool _paused = false;
  int _active = 0;
  Completer<void>? _resumeGate;
  Completer<void>? _idleGate;

  Future<T> run<T>(Future<T> Function() action) async {
    while (_paused) {
      await (_resumeGate ??= Completer<void>()).future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_active == 0) {
        final idle = _idleGate;
        _idleGate = null;
        if (idle != null && !idle.isCompleted) idle.complete();
      }
    }
  }

  Future<void> pauseAndDrain() async {
    _paused = true;
    if (_active == 0) return;
    await (_idleGate ??= Completer<void>()).future;
  }

  void resume() {
    _paused = false;
    final gate = _resumeGate;
    _resumeGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}
