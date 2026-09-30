import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/pos_repository.dart';
import '../services/einvoice/einvoice_service.dart';
import '../services/einvoice/myinvois_client.dart';

class EInvoiceSetupScreen extends StatefulWidget {
  const EInvoiceSetupScreen({super.key, required this.repo});
  final PosRepository repo;
  @override State<EInvoiceSetupScreen> createState() => _EInvoiceSetupScreenState();
}
class _EInvoiceSetupScreenState extends State<EInvoiceSetupScreen> {
  late final service = EInvoiceService(widget.repo);
  static const fields = <String, String>{
    'name': 'Company Name / 公司名称', 'tin': 'TIN', 'brn': 'BRN',
    'msic': 'MSIC（五位）', 'activity': 'Business Activity / 业务描述',
    'address': 'Address / 地址', 'city': 'City / 城市', 'state': 'State Code / 州代码 01–17',
    'postcode': 'Postcode', 'phone': 'Phone / 电话 +60…', 'email': 'Email（选填）',
    'sst': 'SST Registration（未注册填 NA）', 'ttx': 'Tourism Tax Registration（未注册填 NA）',
    'classification': 'MyInvois Classification（三位）', 'tax_rate': '含税售价中的税率 %（不适用填 0）',
    'exemption_reason': 'Tax Exemption Reason（税种 E 必填）',
  };
  late final inputs = {for (final key in fields.keys) key: TextEditingController()};
  final clientId = TextEditingController(), secret = TextEditingController(), search = TextEditingController();
  String environment = 'sandbox', taxType = '06', message = '', certificateName = '';
  bool busy = true;
  List<Map<String, Object?>> rows = [];
  bool get admin => widget.repo.auth.currentUser?.role == AppRole.admin;
  @override void initState() { super.initState(); _load(); }
  @override void dispose() { service.dispose(); for (final c in inputs.values) { c.dispose(); } clientId.dispose(); secret.dispose(); search.dispose(); super.dispose(); }
  Future<void> _load() async {
    try {
      final profile = await (await service.settings).load(environment: environment);
      for (final key in inputs.keys) { inputs[key]!.text = '${profile[key] ?? (['sst','ttx'].contains(key) ? 'NA' : '')}'; }
      inputs['tax_rate']!.text = '${(profile['tax_rate_basis_points'] as num? ?? 0) / 100}';
      taxType = '${profile['tax_type'] ?? '06'}';
      certificateName = await (await service.settings).signingCertificateName(environment) ?? '';
      clientId.clear(); secret.clear(); rows = await service.history(environment, receipt: search.text.trim());
    } catch (_) { message = '读取设置失败，请重试'; }
    if (mounted) setState(() => busy = false);
  }
  Future<void> _run(Future<void> Function() action) async {
    setState(() { busy = true; message = ''; });
    try { await action(); rows = await service.history(environment, receipt: search.text.trim()); if (mounted) setState(() => message = '操作完成'); }
    catch (e) { if (mounted) setState(() => message = e is FormatException || e is StateError || e is ArgumentError || e is MyInvoisException ? '$e' : '连接或操作失败，请检查网络和 MyInvois 配置'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _save() async {
    final old = await (await service.settings).load(environment: environment, credentials: clientId.text.isEmpty || secret.text.isEmpty);
    final rate = double.tryParse(inputs['tax_rate']!.text);
    if (rate == null || rate < 0 || rate > 100 || !rate.isFinite) throw const FormatException('税率须为 0–100');
    await service.saveSettings({
      for (final e in inputs.entries) e.key: e.value.text.trim(),
      'environment': environment, 'tax_type': taxType, 'tax_rate_basis_points': (rate*100).round(),
    }, clientId.text.isEmpty ? '${old['client_id'] ?? ''}' : clientId.text, secret.text.isEmpty ? '${old['client_secret'] ?? ''}' : secret.text);
    clientId.clear(); secret.clear();
  }
  Future<String?> _prompt(String title, {String hint = '', bool obscure = false}) async {
    final c = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: Text(title), content: TextField(controller: c, obscureText: obscure, enableSuggestions: !obscure, autocorrect: false, decoration: InputDecoration(helperText: hint)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('返回')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('确认'))]));
    // Dialog route may still animate after completion; let its field dispose first.
    return value;
  }
  Future<void> _importCertificate() async {
    final password = await _prompt('PFX/P12 证书密码', obscure: true);
    if (password == null) return;
    await _run(() async {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pfx','p12'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw StateError('无法读取所选证书文件');
      await service.saveSigningCertificate(environment, bytes, password, file.name);
      certificateName = file.name;
    });
  }
  Future<void> _prepare(Map<String, Object?> row, {bool correction = false}) async {
    if (correction) {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('生成单独的更正尝试？'),
        content: Text('原发票 ${row['document_invoice_no'] ?? row['receipt_no']} 的 UUID 和 Invalid 记录会保留。新尝试会使用新的发票号码；请先核对 MyInvois 验证错误及买方资料。只有确认原文件状态后才继续。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('返回')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续更正'))],
      ));
      if (confirmed != true) return;
    }
    final saved = jsonDecode(row['buyer_json'] as String) as Map<String, dynamic>;
    final labels = {'name': 'Buyer Name', 'tin': 'Buyer TIN', 'id_type': 'ID Type: BRN / NRIC / PASSPORT / ARMY', 'id_number': 'ID Number', 'address': 'Address', 'city': 'City', 'state': 'State Code 01–17', 'postcode': 'Postcode', 'phone': 'Phone +60…', 'sst': 'SST / NA'};
    final controls = {for (final key in labels.keys) key: TextEditingController(text: '${saved[key] ?? (key == 'name' ? row['customer_name'] ?? '' : key == 'phone' ? row['customer_phone'] ?? '' : key == 'id_type' ? 'BRN' : key == 'sst' ? 'NA' : '')}')};
    final buyer = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
      title: Text('${correction ? '更正尝试' : '买方资料'} · ${row['receipt_no']}'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('资料仅用于本张 e-Invoice，不修改原销售。请填写真实资料。'),
        if (correction) const Text('这会新增一份独立提交记录，并保留原 Invalid UUID。'),
        for (final e in labels.entries) Padding(padding: const EdgeInsets.only(top: 12), child: TextField(controller: controls[e.key], decoration: InputDecoration(labelText: e.value))),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('返回')), FilledButton(onPressed: () => Navigator.pop(context, {for (final e in controls.entries) e.key: e.value.text.trim()}), child: const Text('生成 Invoice'))],
    ));
    if (buyer == null) return;
    await _run(() async {
      final json = correction
          ? await service.prepareCorrection(row['sale_id'] as String, environment, buyer)
          : await service.prepare(row['sale_id'] as String, environment, buyer);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Invoice JSON · 已生成，尚未提交'), content: SizedBox(width: 720, child: SingleChildScrollView(child: SelectableText(const JsonEncoder.withIndent('  ').convert(jsonDecode(json))))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))]));
    });
  }
  Future<void> _submit(Map<String, Object?> row) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text('提交到 ${environment == 'production' ? 'Production 正式环境' : 'Sandbox 测试环境'}'), content: Text('发票 ${row['document_invoice_no'] ?? row['receipt_no']} · RM ${((row['total_cents'] as int)/100).toStringAsFixed(2)}\n确认公司、买方和税务资料正确后提交。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('返回')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('提交'))]));
    if (confirmed == true) await _run(() => service.submitPendingInvoice(row['sale_id'] as String, environment: environment));
  }
  @override Widget build(BuildContext context) => DefaultTabController(length: 2, child: Scaffold(
    appBar: AppBar(title: const Text('e-Invoice Setup'), bottom: const TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.white, tabs: [Tab(text: '设置 / Setup'), Tab(text: 'Submission History')])),
    body: Column(children: [
      if (busy) const LinearProgressIndicator(),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(message)),
      Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(initialValue: environment, decoration: const InputDecoration(labelText: 'Environment'), items: const [DropdownMenuItem(value: 'sandbox', child: Text('Sandbox 测试')), DropdownMenuItem(value: 'production', child: Text('Production 正式'))], onChanged: busy ? null : (v) { setState(() { environment = v!; busy = true; }); _load(); })),
      Expanded(child: TabBarView(children: [
        ListView(padding: const EdgeInsets.all(16), children: [
          const Text('仅 Desktop 调用 MyInvois。凭据和数字证书加密保存；更换电脑或 Windows 用户后需重新输入。先在 Sandbox 测试。'),
          for (final e in fields.entries) Padding(padding: const EdgeInsets.only(top: 12), child: TextField(controller: inputs[e.key], enabled: admin && !busy, decoration: InputDecoration(labelText: e.value))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(key: ValueKey('$environment:$taxType'), initialValue: taxType, decoration: const InputDecoration(labelText: 'Tax Type（整单相同税种，售价含税）'), items: [for (final code in ['01','02','03','04','05','06','E']) DropdownMenuItem(value: code, child: Text(code == '06' ? '06 · Not applicable' : code == 'E' ? 'E · Exempt' : code))], onChanged: !admin || busy ? null : (v) => setState(() => taxType = v!)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('本模块仅支持整单相同税种、税率和分类。混合税率、汇总发票、贷项/退款票请使用 MyInvois Portal。请核实本店适用税务资料。')),
          TextField(controller: clientId, enabled: admin && !busy, obscureText: true, decoration: const InputDecoration(labelText: 'Client ID（留空保留已保存值）')),
          const SizedBox(height: 12), TextField(controller: secret, enabled: admin && !busy, obscureText: true, enableSuggestions: false, autocorrect: false, decoration: const InputDecoration(labelText: 'Client Secret（留空保留已保存值）')),
          const SizedBox(height: 12), Text('MyInvois 数字证书：${certificateName.isEmpty ? '尚未导入' : certificateName}'),
          const SizedBox(height: 8), OutlinedButton(onPressed: admin && !busy ? _importCertificate : null, child: const Text('导入 PFX/P12 数字证书')),
          const SizedBox(height: 16), Wrap(spacing: 12, children: [
            FilledButton(onPressed: admin && !busy ? () => _run(_save) : null, child: const Text('保存 / Save')),
            OutlinedButton(onPressed: admin && !busy ? () => _run(() => service.testConnection(environment)) : null, child: const Text('Test Connection（已保存配置）')),
          ]),
        ]),
        ListView(padding: const EdgeInsets.all(16), children: [
          const Text('显示最近 500 笔；可按单号搜索旧记录。Pending 尚未提交；Submitted 已接收；Validated 验证通过；Rejected 为同步拒收；Invalid 为取得 UUID 后验证失败。更正会新建独立记录并保留原 UUID。取消 e-Invoice 不会退款或改动库存。'),
          TextField(controller: search, decoration: const InputDecoration(labelText: '搜索 Invoice / Receipt Number'), onSubmitted: (_) => _run(() async {})),
          TextButton(onPressed: busy ? null : () => _run(() async {}), child: const Text('刷新本地列表')),
          for (final row in rows) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['receipt_no']} · ${row['status']}', style: Theme.of(context).textTheme.titleMedium),
            if (row['document_id'] != null && row['document_invoice_no'] != row['receipt_no']) Text('本次发票号码：${row['document_invoice_no']} · 尝试 ${row['attempt_no']}'),
            Text('${row['customer_name'] ?? ''} · RM ${((row['total_cents'] as int)/100).toStringAsFixed(2)}'),
            if ('${row['error_message']}'.isNotEmpty) Text('${row['error_message']}'),
            if ('${row['document_uuid']}'.isNotEmpty) SelectableText('UUID: ${row['document_uuid']}'),
            if (admin) Wrap(spacing: 8, children: [
              if (row['is_latest_attempt'] == true && row['voided'] != 1 && ['pending','rejected'].contains(row['status']) && row['document_uuid'] == '' && (row['status'] == 'rejected' || row['submission_uid'] == '')) TextButton(onPressed: busy ? null : () => _prepare(row), child: const Text('买方资料 / 生成')),
              if (row['is_latest_attempt'] == true && row['voided'] != 1 && row['status'] == 'invalid' && '${row['document_uuid']}'.isNotEmpty) TextButton(onPressed: busy ? null : () => _prepare(row, correction: true), child: const Text('生成更正尝试')),
              if (row['is_latest_attempt'] == true && row['document_id'] != null && row['status'] == 'pending' && row['voided'] != 1 && row['document_uuid'] == '' && row['submission_uid'] == '') FilledButton(onPressed: busy ? null : () => _submit(row), child: const Text('提交')),
              if (row['submission_uid'] != '') TextButton(onPressed: busy ? null : () => _run(() => service.refresh(row['document_id'] as String)), child: const Text('查询 MyInvois')),
              if (row['document_id'] != null && (['needs_review','submitting'].contains(row['status']) || (row['status'] == 'pending' && (row['document_uuid'] != '' || row['submission_uid'] != '')))) TextButton(onPressed: busy ? null : () async {
                final uuid = await _prompt('核对 Portal 中的 UUID', hint: '结果未知时先查询 Portal，不要重复提交');
                if (uuid == null || uuid.trim().isEmpty) return;
                final uid = '${row['submission_uid'] ?? ''}'.isNotEmpty
                    ? '${row['submission_uid']}' : await _prompt('Portal 中的 Submission UID');
                if (uid == null || uid.trim().isEmpty) return;
                await _run(() => service.reconcile(row['document_id'] as String, uuid, submissionUid: uid));
              }, child: const Text('核对 UUID')),
              if (row['document_id'] != null && row['status'] == 'invalid' && '${row['document_uuid']}'.isNotEmpty) TextButton(onPressed: busy ? null : () async { final uuid = await _prompt('查看 Invalid 文件的验证详情 UUID'); if (uuid != null && uuid.trim().isNotEmpty) await _run(() => service.reconcile(row['document_id'] as String, uuid)); }, child: const Text('查看验证详情')),
              if (row['document_uuid'] != '' && ['submitted','validated'].contains(row['status'])) TextButton(onPressed: busy ? null : () async { final reason = await _prompt('取消 e-Invoice 原因', hint: '受 MyInvois 取消期限限制；不会退款'); if (reason != null) await _run(() => service.cancel(row['document_id'] as String, reason)); }, child: const Text('取消 e-Invoice')),
            ]),
          ]))),
        ]),
      ])),
    ]),
  ));
}
