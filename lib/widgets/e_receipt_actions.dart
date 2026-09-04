import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../services/bluetooth_printer.dart';
import '../services/e_receipt.dart';
import '../services/pos_repository.dart';
import '../theme/cnkh_theme.dart';

/// Prompt for name+phone if missing, then share print-layout PDF via WhatsApp.
Future<void> sendEReceiptFlow(
  BuildContext context, {
  required SaleRecord sale,
  required PosRepository repo,
}) async {
  var phone = (sale.customerPhone ?? '').trim();
  var name = (sale.customerName ?? '').trim();

  if (phone.isEmpty) {
    final nameCtrl = TextEditingController(text: name);
    final phoneCtrl = TextEditingController();
    var saveCustomer = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('电子收据 PDF / E-receipt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '姓名 / Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '手机号 / Phone',
                  hintText: '01x-xxx xxxx',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('保存为客户 / Save as customer',
                    style: TextStyle(fontSize: 12)),
                value: saveCustomer,
                onChanged: (v) => setLocal(() => saveCustomer = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('发送 PDF')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    name = nameCtrl.text.trim();
    phone = phoneCtrl.text.trim();
    if (normalizeMyPhone(phone).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效手机号 / Invalid phone'),
          backgroundColor: CnkhColors.danger,
        ),
      );
      return;
    }
    if (saveCustomer && name.isNotEmpty) {
      await repo.upsertCustomer(
        Customer(id: AppDatabase.newId(), name: name, phone: phone),
      );
    }
  }

  final storeName =
      await repo.getSetting('store_name', fallback: kStoreName);
  final contactMsg =
      await maybeEnsureContact(name: name.isEmpty ? phone : name, phoneRaw: phone);
  if (!context.mounted) return;
  try {
    final result = await shareEReceiptPdf(
      sale: sale,
      phoneRaw: phone,
      storeName: storeName.isEmpty ? kStoreName : storeName,
    );
    if (!context.mounted) return;
    final msg = contactMsg.isEmpty ? result : '$result\n$contactMsg';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('发送失败 / Share failed: $e'),
        backgroundColor: CnkhColors.danger,
      ),
    );
  }
}

Future<void> showSaleSuccessSheet(
  BuildContext context, {
  required SaleRecord sale,
  required PosRepository repo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('✓ 收款成功 / Paid',
                style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                      color: CnkhColors.success,
                    )),
            const SizedBox(height: 8),
            Text('${sale.receiptNo}  ·  ${formatRmPlain(sale.totalCents)}'),
            Text(sale.paymentMethod,
                style: const TextStyle(color: CnkhColors.muted)),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366)),
                onPressed: () async {
                  await sendEReceiptFlow(ctx, sale: sale, repo: repo);
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('电子收据 PDF / E-receipt',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final bt = BluetoothPrinterService(repo);
                final msg = await bt.tryPrintSale(sale);
                if (!ctx.mounted) return;
                if (msg == 'bt_off') {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('蓝牙打印未开启 / BT printer off')),
                  );
                } else if (msg == 'ok') {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('已发送蓝牙小票 / Printed')),
                  );
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: CnkhColors.danger),
                  );
                }
              },
              icon: const Icon(Icons.print),
              label: const Text('蓝牙打印小票 / BT print'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('完成 / Done'),
            ),
          ],
        ),
      ),
    ),
  );
}
