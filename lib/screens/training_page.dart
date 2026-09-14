import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Screenshots are captured from the application's actual widgets in CI.
/// Arrow coordinates are measured from the same rendered widget tree.
class TrainingPage extends StatelessWidget {
  const TrainingPage({super.key});
  static const lessons = <(String, String, String)>[
    ("登录与权限", "login", "使用自己的账号和 PIN 登录；管理员管理设置和税务资料，员工按授权收银。首次安装由店主设置管理员 PIN。不要共享管理员账号。"),
    ("商品销售", "sale", "在真实收银页搜索商品或扫码加购，核对数量和折扣，再结账。断网时仍可保存本地销售；不要反复创建同一笔交易。"),
    ("收款", "payment", "核对现金、银行卡、DuitNow 或赊账方式。DuitNow 必须核实实际到账；二维码展示不等于到账确认。检查实收和找零后完成销售。"),
    ("退款", "refund", "在销售记录找到原单，由有权限人员执行作废并填写原因。作废会按原销售恢复库存；银行卡或电子钱包退款仍需在支付渠道办理。已验证 e-Invoice 的调整需另行处理，作废销售不会自动取消税务发票。"),
    ("库存", "stock", "在库存盘点页核对实际数量后保存调整。手机待同步时先同步，再做盘点。遇到库存不足，核对电脑最新库存，不要重复出单绕过限制。"),
    ("手机连接电脑", "pair", "电脑和手机连接同一可信 Wi-Fi。电脑打开配对页显示二维码，手机使用右上角扫码配对。过期时在电脑刷新二维码；不要把配对二维码发给店外人员。"),
    ("数据同步", "sync", "在设置检查电脑地址和配对连接，执行同步。系统先上传手机待处理操作，再拉取电脑数据。失败时保留手机数据，检查 Wi-Fi、电脑程序和防火墙后重试。不要先清空手机。"),
    ("数据备份", "backup", "在电脑备份/还原页创建备份，保存到独立介质并定期验证还原。手机先同步到电脑后纳入电脑备份。换电脑或 Windows 用户后，MyInvois 凭据需要重新输入；保留原税务提交记录。"),
    ("e-Invoice 设置", "einvoice_setup", "仅在 Desktop 设置 → e-Invoice Setup 由管理员填写公司名称、TIN、BRN、地址、MSIC、联系方式、商品分类和适用税务资料。先选择 Sandbox，保存 Client ID / Secret，再 Test Connection。正式环境使用独立凭据。"),
    ("e-Invoice 提交", "einvoice_history", "Desktop 的 Submission History 中选销售，填写真实买方税务资料，生成并核对 Invoice JSON，再确认提交环境和金额。Submitted 表示已接收；查询到 Validated 才算验证通过。手机通过 LAN 同步获取状态。"),
    ("常见错误处理", "einvoice_history", "Pending：尚未提交。Rejected：核对资料及 MyInvois 验证结果。凭据错误：在电脑重新保存对应环境凭据。结果未知：先到 MyInvois 查找 UUID，再用核对 UUID 恢复状态，切勿重复提交。取消受官方期限限制；超期或退款应在 Portal 办理相应调整单。"),
  ];
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CNKH POS Employee Training')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('使用本版本真实页面截图 · 展开课程查看操作说明。截图中的资料为培训测试数据。'),
      const SizedBox(height: 12),
      for (var i = 0; i < lessons.length; i++) Card(child: ExpansionTile(
        title: Text('${i+1}. ${lessons[i].$1}'),
        childrenPadding: const EdgeInsets.all(16),
        children: [Text(lessons[i].$3, style: const TextStyle(height: 1.6)), const SizedBox(height: 12), TrainingScreenshot(name: lessons[i].$2),
          if (lessons[i].$2 == 'einvoice_setup') ...[
            const SizedBox(height: 12),
            const Text('向下滚动填写凭据，保存后测试连接：'),
            const TrainingScreenshot(name: 'einvoice_credentials'),
          ],
        ],
      )),
    ]),
  );
}
class TrainingScreenshot extends StatelessWidget {
  const TrainingScreenshot({super.key, required this.name});
  final String name;
  @override Widget build(BuildContext context) => FutureBuilder<String>(
    future: rootBundle.loadString('assets/training/$name.json'),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return Text(snapshot.hasError ? '截图未打包：请安装正式发布版本，或按 README 生成真实页面截图。' : '载入截图…');
      final meta = jsonDecode(snapshot.data!) as Map<String, dynamic>;
      return InteractiveViewer(minScale: 1, maxScale: 4, child: AspectRatio(
        aspectRatio: (meta['width'] as num)/(meta['height'] as num),
        child: CustomPaint(foregroundPainter: _Arrow(Offset((meta['x'] as num).toDouble(), (meta['y'] as num).toDouble())),
          child: Image.asset('assets/training/$name.png', fit: BoxFit.contain)),
      ));
    },
  );
}
class _Arrow extends CustomPainter {
  const _Arrow(this.target);
  final Offset target;
  @override void paint(Canvas canvas, Size size) {
    final end = Offset(target.dx*size.width, target.dy*size.height);
    final start = end + Offset(end.dx > size.width*.5 ? -size.width*.14 : size.width*.14, end.dy > size.height*.5 ? -size.height*.08 : size.height*.08);
    final paint = Paint()..color = Colors.red..strokeWidth = 3..style = PaintingStyle.stroke;
    canvas.drawLine(start,end,paint);
    final angle = math.atan2(end.dy-start.dy,end.dx-start.dx);
    final path = Path()..moveTo(end.dx-12*math.cos(angle-.45),end.dy-12*math.sin(angle-.45))..lineTo(end.dx,end.dy)..lineTo(end.dx-12*math.cos(angle+.45),end.dy-12*math.sin(angle+.45));
    canvas.drawPath(path,paint);
  }
  @override bool shouldRepaint(_Arrow oldDelegate) => oldDelegate.target != target;
}
