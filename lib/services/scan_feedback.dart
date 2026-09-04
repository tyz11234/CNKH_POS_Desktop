import 'package:flutter/services.dart';
import 'pos_repository.dart';

Future<void> playScanFeedback(PosRepository repo) async {
  final mode = await repo.getSetting('scan_feedback', fallback: 'beep');
  if (mode == 'mute') return;
  if (mode == 'vibrate') {
    try { await HapticFeedback.mediumImpact(); } catch (_) {}
    return;
  }
  try {
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.selectionClick();
  } catch (_) {
    try { await HapticFeedback.lightImpact(); } catch (_) {}
  }
}
