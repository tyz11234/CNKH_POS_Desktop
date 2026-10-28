import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'lan_sync.dart';
import 'pos_repository.dart';
import 'scan_feedback.dart';

typedef PaymentReceivedCallback = void Function(Map<String, dynamic> paymentEvent);

/// Broadcast wording requested by the shop: whole ringgit and sen spoken
/// separately, e.g. 3550 cents -> 'DuitNow 收款成功，35 令吉 50 仙'.
String paymentSpeechText(int cents) {
  final rm = cents ~/ 100;
  final sen = cents % 100;
  var amt = '';
  if (rm > 0) amt = '$rm 令吉';
  if (sen > 0) amt = amt.isEmpty ? '$sen 仙' : '$amt $sen 仙';
  if (amt.isEmpty) amt = '0 令吉';
  return 'DuitNow 收款成功，$amt';
}

/// 监听 Linux 云端 /api/v1/pay-ws 推送的 Public Bank 到账通知，自动下载云端 /api/v1/tts 语音并朗读播报
class PaymentBroadcastListener {
  PaymentBroadcastListener._();
  static final PaymentBroadcastListener instance = PaymentBroadcastListener._();

  static const MethodChannel _nativeChannel =
      MethodChannel('com.cnkh.cnkh_pos_desktop/whatsapp_share');

  PosRepository? _repo;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _running = false;
  final List<PaymentReceivedCallback> _listeners = [];

  void addListener(PaymentReceivedCallback cb) {
    if (!_listeners.contains(cb)) _listeners.add(cb);
  }

  void removeListener(PaymentReceivedCallback cb) {
    _listeners.remove(cb);
  }

  Future<void> start({PosRepository? repo}) async {
    if (repo != null) _repo = repo;
    _running = true;
    await _connect();
  }

  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  /// 自动请求云端 /api/v1/tts 合成语音 MP3 并调用系统原生播放器朗读；若失败则回退系统本地 TTS 或提示音
  Future<void> announcePayment(Map<String, dynamic> event) async {
    final r = _repo ?? PosRepository();
    final provided = (event['tts_text']?.toString() ?? '').trim();
    var cents = event['amount_cents'] is num
        ? (event['amount_cents'] as num).toInt()
        : int.tryParse(event['amount_cents']?.toString() ?? '');
    if (cents == null) {
      final rmVal = double.tryParse(event['amount_rm']?.toString() ?? '');
      if (rmVal != null) cents = (rmVal * 100).round();
    }
    final ttsText = provided.isNotEmpty
        ? provided
        : (cents != null ? paymentSpeechText(cents) : 'DuitNow 收款成功');

    // 先触发收银提示音/震动提醒
    unawaited(playScanFeedback(r));

    bool playedMp3 = false;
    try {
      final cfg = await LanSyncClient(r).loadConfig();
      if (cfg != null && cfg.baseUrl.trim().isNotEmpty) {
        final base = Uri.parse(cfg.normalizedBase);
        final qp = <String, String>{'text': ttsText};
        if (cfg.token.trim().isNotEmpty) qp['token'] = cfg.token.trim();
        final ttsUri = base.replace(
          path: '/api/v1/tts',
          queryParameters: qp,
        );
        final resp = await http.get(
          ttsUri,
          headers: <String, String>{
            if (cfg.token.trim().isNotEmpty) 'X-CNKH-Token': cfg.token.trim(),
            if (cfg.token.trim().isNotEmpty) 'X-LAN-Sync-Token': cfg.token.trim(),
          },
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final tmpFile = File(
            '${Directory.systemTemp.path}/cnkh_payment_tts.mp3',
          );
          await tmpFile.writeAsBytes(resp.bodyBytes, flush: true);
          playedMp3 = await _playLocalMp3(tmpFile.path);
        }
      }
    } catch (_) {}

    if (!playedMp3) {
      await _speakFallback(ttsText);
    }
  }

  Future<bool> _playLocalMp3(String path) async {
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        final ok = await _nativeChannel.invokeMethod<bool>(
          'playAudioFile',
          <String, Object?>{'path': path},
        );
        if (ok == true) return true;
      }
      if (Platform.isLinux) {
        for (final player in ['mpv', 'ffplay', 'mpg123', 'cvlc']) {
          try {
            final args = player == 'ffplay'
                ? ['-nodisp', '-autoexit', '-loglevel', 'quiet', path]
                : [path];
            final res = await Process.run(player, args);
            if (res.exitCode == 0) return true;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> _speakFallback(String text) async {
    try {
      if (Platform.isAndroid) {
        await _nativeChannel.invokeMethod<bool>(
          'speakText',
          <String, Object?>{'text': text},
        );
        return;
      }
      if (Platform.isWindows) {
        final safe = text.replaceAll("'", "").replaceAll('"', '');
        await Process.run('powershell', [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('$safe')",
        ]);
      }
    } catch (_) {}
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final r = _repo ?? PosRepository();
      final cfg = await LanSyncClient(r).loadConfig();
      if (cfg == null || cfg.baseUrl.trim().isEmpty) {
        _scheduleReconnect();
        return;
      }
      final base = Uri.parse(cfg.normalizedBase);
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      final qp = <String, String>{};
      if (cfg.token.trim().isNotEmpty) qp['token'] = cfg.token.trim();
      final wsUri = Uri(
        scheme: scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/api/v1/pay-ws',
        queryParameters: qp.isEmpty ? null : qp,
      );

      await _sub?.cancel();
      await _channel?.sink.close();
      _channel = WebSocketChannel.connect(wsUri);
      _sub = _channel!.stream.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
            if (msg['type'] == 'payment_received') {
              unawaited(announcePayment(msg));
              for (final cb in List<PaymentReceivedCallback>.from(_listeners)) {
                cb(msg);
              }
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }
}
