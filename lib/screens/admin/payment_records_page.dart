import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/lan_sync.dart';
import '../../services/pos_repository.dart';
import '../../theme/cnkh_theme.dart';

/// 收款记录 / Payment Records
///
/// Reads the cloud payment ledger (Public Bank DuitNow QR arrivals detected
/// by the ai_helper from bank notification emails) via GET /api/v1/payments.
/// Every record carries the bank transaction reference （流水号） and amount.
class PaymentRecordsPage extends StatefulWidget {
  final PosRepository repo;

  const PaymentRecordsPage({super.key, required this.repo});

  @override
  State<PaymentRecordsPage> createState() => _PaymentRecordsPageState();
}

class _PaymentRecordsPageState extends State<PaymentRecordsPage> {
  bool _loading = true;
  String? _error;
  bool _notConfigured = false;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notConfigured = false;
    });
    try {
      final cfg = await LanSyncClient(widget.repo).loadConfig();
      if (cfg == null || cfg.baseUrl.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _notConfigured = true;
          _loading = false;
        });
        return;
      }
      final uri = Uri.parse('${cfg.normalizedBase}/api/v1/payments?limit=300');
      final resp = await http.get(
        uri,
        headers: {
          'X-LAN-Sync-Token': cfg.token,
          'X-CNKH-Token': cfg.token,
        },
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw StateError('服务器返回 ${resp.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items = ((data['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _summary = Map<String, dynamic>.from(
            (data['summary'] as Map?) ?? const {});
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  static String _rm(int cents) {
    final sign = cents < 0 ? '-' : '';
    final absCents = cents.abs();
    final ringgit = absCents ~/ 100;
    final sen = (absCents % 100).toString().padLeft(2, '0');
    final digits = ringgit.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${sign}RM $buf.$sen';
  }

  static String _fmtTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  Widget _statCard(String label, int cents, int count) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: CnkhColors.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(_rm(cents),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text('$count 笔',
                  style: const TextStyle(
                      color: CnkhColors.muted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收款记录 / Payment Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新 Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notConfigured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '尚未配置云端同步地址。\n请先到「设置 → 局域网同步」填写服务器地址与令牌，\n收款记录会从云端读取。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('读取收款记录失败：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试 Retry')),
            ],
          ),
        ),
      );
    }
    final todayCents = (_summary['today_cents'] as num?)?.toInt() ?? 0;
    final todayCount = (_summary['today_count'] as num?)?.toInt() ?? 0;
    final monthCents = (_summary['month_cents'] as num?)?.toInt() ?? 0;
    final monthCount = (_summary['month_count'] as num?)?.toInt() ?? 0;
    final totalCents = (_summary['total_cents'] as num?)?.toInt() ?? 0;
    final totalCount = (_summary['total_count'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statCard('今日收款 Today', todayCents, todayCount),
              _statCard('本月 This Month', monthCents, monthCount),
              _statCard('累计 Total', totalCents, totalCount),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Public Bank · DuitNow QR 到账（来源：银行通知邮件）',
            style: TextStyle(color: CnkhColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('暂无收款记录')),
            )
          else
            ..._items.map(
              (it) => Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined,
                      color: CnkhColors.primary),
                  title: Text(
                    _rm((it['amount_cents'] as num?)?.toInt() ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '流水号 Ref: ${it['ref_no'] ?? '-'}\n${_fmtTime('${it['time'] ?? ''}') }',
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
