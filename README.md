# 黄金发宝号 · CNKH POS Desktop

用于 Windows 电脑的门店收银与管理系统。电脑作为店内局域网权威主机，与 [CNKH POS Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK) 配套使用，核心收银与店内同步不依赖云服务器。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。

> README 最后更新：**2026-09-06**。当前正式配套为 **Desktop v0.3.3 + Mobile v1.9.0 OCR Purchase**。

## 当前正式版本

| 项目 | 当前版本 |
| --- | --- |
| Desktop | **0.3.3+6** |
| Desktop 正式 Release | **`v0.3.3`** |
| 配套 Mobile | **1.9.0+25 / `v1.9.0-mobile`** |
| LAN 协议 | `cnkh-sync:v1` |
| OCR 同步 | **已支持** |

推荐配套：**Desktop v0.3.3 + Mobile v1.9.0**。

### 正式下载

Desktop v0.3.3 Release：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3

直接下载 Windows x64 ZIP：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v0.3.3/CNKH_POS_Desktop-windows-x64-v0.3.3-6.zip

Mobile v1.9.0 Release：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile

Desktop ZIP SHA-256：

```text
42949029d88d77ccbb32e78fc70d5a59cdee6d9f12e5cd2eeecaf92caf11c96e
```

Desktop v0.3.3 发布提交：

```text
56788a34eecbe79ded14ea311180983f6a3876ba
```

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 收银 | 商品搜索、条码加购、购物车、行折扣、整单折扣、挂单与取单 |
| 收款 | 现金、银行卡、DuitNow、赊账、找零及欠款记录 |
| 商品与库存 | 商品、分类、成本与售价、进货、盘点、供应商管理 |
| 客户与销售 | 客户资料、今日与历史销售、销售详情、作废 |
| 小票与报表 | 小票模板、电子收据 PDF、WhatsApp 分享、销售与成本毛利报表、日结 |
| 局域网同步 | QR 配对、HTTP 对账、WebSocket 变更通知、离线操作重试 |
| OCR 进货同步 | 接收 Mobile OCR Purchase 元数据、费用字段和 `purchase_reverse` 撤销 |
| 账号 | 管理员与员工权限、PIN 验证、员工 PIN 设置 |

现有收银金额、折扣、舍入规则和页面布局保持不变。

## OCR 进货架构

OCR 识别本身只在 Android Mobile 本机运行。Desktop 不负责拍照 OCR，而是继续作为店内局域网权威主机。

完整流程：

```text
Mobile 拍照 / 相册
      ↓
本机 ML Kit OCR
      ↓
OCR Draft
      ↓
商品匹配 / 异常检查
      ↓
人工确认
      ↓
Mobile SQLite 原子入库
      ↓
Persistent Outbox
      ↓
Desktop /api/v1/mutations
```

只有 Mobile 用户点击 **确认并入库** 后，才会产生正式 `purchase` mutation；未确认 Draft 不会上传 Desktop，也不会改变 Desktop 库存。

## Desktop 接收的 OCR Purchase 数据

原有 `purchase` mutation 继续使用，并兼容：

- Invoice No
- Invoice Date
- Discount
- Tax / SST
- Delivery Fee
- Other Fee
- `source = ocr`
- Mobile Draft ID
- OCR Raw Text
- Operator
- OCR 原始数量
- OCR 原始成本
- OCR 原始小计
- Unit / Conversion 等进货行信息

Desktop 收到新的 operation 后，会在数据库事务内：

- 保存 Purchase
- 更新库存
- 更新成本
- 写 `stock_moves`
- 保存 OCR 元数据
- 记录 `sync_applied_operations`

同一个 operation 重试不会再次加库存。

## OCR 进货撤销

Mobile 管理员撤销 OCR 进货时会发送：

```text
kind = purchase_reverse
```

Desktop 会：

- 保留原 Purchase
- 标记为 reversed
- 回退本次进货库存
- 写负数库存流水
- 在安全条件下恢复进货前成本
- 保存撤销人员 / 时间 / 原因 / 备注
- 写 `purchase_reversals`
- 写 audit log
- 记录 operation ID

重复提交不会重复扣库存。

## 数据库兼容

OCR 同步采用增量迁移：

- 不清空旧数据库
- 不重建旧销售数据
- 不改变旧 Purchase 字段含义
- 旧版普通进货继续可读
- 新字段对旧记录使用默认值

新增兼容字段/表包括：

- `purchases.invoice_no`
- `purchases.invoice_date`
- `purchases.discount_cents`
- `purchases.tax_cents`
- `purchases.delivery_fee_cents`
- `purchases.other_fee_cents`
- `purchases.source`
- `purchases.draft_id`
- `purchases.ocr_raw_text`
- `purchases.reversed*`
- `purchase_reversals`
- `purchase_audit_log`

Desktop 不保存 Mobile 本地图片路径，因为该路径只对手机文件系统有效。原始进货单图片保留在 Mobile 本机。

## 连接手机端

1. 安装并启动 **Desktop v0.3.3**。
2. Android 安装 **Mobile v1.9.0**。
3. 两台设备连接同一 Wi-Fi / LAN。
4. Desktop 打开 LAN / 扫码配对页面。
5. Mobile 扫描二维码。
6. Mobile 保存 Desktop 地址和 Token。

默认端口：**8787**。

二维码前缀：

```text
cnkh-sync:v1|
```

手机断线期间仍可本地收银与处理 OCR；恢复连接后自动上传已确认业务。

## 首次登录

1. 首次运行选择管理员 `admin`。
2. 输入自定 **6–12 位数字 PIN**。
3. 再输入一次完成初始化。
4. 管理员可为 `staff`、`staff2` 等员工设置 PIN。

PIN 连续输错 5 次会锁定 5 分钟。Desktop 与 Mobile 的账号凭据分别本机管理，LAN 配对不会自动同步 PIN。

## 稳定性与同步行为

- 结账与扣库存使用同一数据库事务
- 作废回补库存并防重复回补
- 保存两端商品 / 客户 ID 对照
- Mobile 销售、作废、资料修改、进货、盘点使用持久 Outbox
- Desktop ACK 后才从 Outbox 移除
- 重试不会重复销售、重复入库或重复回补
- 新销售保存成交时成本
- 历史销售查询不再受 200 条默认截断
- 盘点 / 资料冲突不会静默覆盖
- OCR `purchase` 使用 operation ID 幂等
- `purchase_reverse` 同样幂等

详细稳定性说明见 [RELIABILITY_NOTES.md](RELIABILITY_NOTES.md)。

## 下载与安装

Desktop Releases：
https://github.com/tyz11234/CNKH_POS_Desktop/releases

当前正式版：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3

Windows 安装：

1. 下载 `CNKH_POS_Desktop-windows-x64-v0.3.3-6.zip`。
2. 完整解压。
3. 保留 EXE、DLL 与 data 目录结构。
4. 运行 `cnkh_pos_desktop.exe`。
5. 配套 Mobile 建议更新到 v1.9.0。

不要只复制 EXE 文件。

## 开发与验证

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build windows --release
```

输出：

```text
build/windows/x64/runner/Release/
```

### v0.3.3 正式 CI

https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34024473482

已通过：

- Flutter 环境准备
- `flutter pub get`
- `flutter analyze`
- Desktop tests
- Windows Release build
- Artifact 上传
- GitHub Release 创建

OCR 配套功能已验证：

- OCR Purchase mutation
- OCR 元数据保存
- `purchase_reverse` 幂等
- Desktop / Mobile HTTP 回归
- 初始断线重连
- ACK 丢失重试
- 原有销售 / 作废 / 盘点同步回归

配套 Mobile v1.9.0 也已通过 32 项 Flutter tests、Android Release APK、R8 和 Chinese + Latin ML Kit bundled model 打包。

## 当前不包含

- Windows 摄像头 OCR
- 云 OCR
- AI / LLM OCR
- MyInvois / Malaysia e-Invoice
- 无人工确认自动入库
- 云端多门店同步

## 相关入口

- Desktop v0.3.3：https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3
- Mobile v1.9.0：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile
- Mobile Flutter 源码：https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main
- Desktop OCR Sync PR #7：https://github.com/tyz11234/CNKH_POS_Desktop/pull/7
- Mobile OCR PR #6：https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/6
- 稳定性修复 PR #6：https://github.com/tyz11234/CNKH_POS_Desktop/pull/6
