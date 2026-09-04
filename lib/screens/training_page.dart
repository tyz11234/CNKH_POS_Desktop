import 'package:flutter/material.dart';
import '../theme/cnkh_theme.dart';

class TrainingPage extends StatelessWidget {
  const TrainingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final steps = <(String, IconData, String)>[
      (
        '1. 配对 / Pair',
        Icons.qr_code_2,
        '在旧版 PC（-CNKH_POS_V5）顶栏「同步/配对」显示二维码。\n'
            '本桌面端顶栏「扫码配对」或设置里手填 http://电脑IP:8787。\n'
            '同一局域网；配对码约 7 分钟有效。',
      ),
      (
        '2. 收银 / POS',
        Icons.point_of_sale,
        '左侧商品网格搜索/分类/扫码加购；右侧购物车挂单、折扣、结账。\n'
            '结账支持现金/卡/DuitNow/赊账；找零对话框不遮挡折扣行。',
      ),
      (
        '3. 发收据 / E-receipt',
        Icons.picture_as_pdf,
        '结账成功后点「电子收据 PDF」。\n'
            '桌面端用系统分享（可选 WhatsApp Desktop）；PDF 缓存 7 天可配置路径。\n'
            '「今日」销售列表可重发。',
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('培训 / Training')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('三步上手 / 3-step guide',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('配对 → 收银 → 发收据', style: TextStyle(color: CnkhColors.muted)),
          const SizedBox(height: 16),
          for (final s in steps)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: CnkhColors.softBlue,
                      child: Icon(s.$2, color: CnkhColors.navy),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(s.$3, style: const TextStyle(height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
