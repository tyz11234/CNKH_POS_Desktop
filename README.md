# 黄金发宝号 · CNKH POS Desktop

用于 Windows 电脑的门店收银与管理系统。电脑作为店内局域网权威主机，与 [CNKH POS Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK) 配套使用，核心收银与店内同步不依赖云服务器。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。

> 更新日期：**2026-09-06**。Desktop v0.3.3 对应 Mobile v1.9.0 OCR Purchase。

## 当前版本

| 项目 | 当前版本 |
| --- | --- |
| Desktop 源码 | **0.3.3+6** |
| Desktop 正式 Release | **`v0.3.3`** |
| Mobile 正式 Release | **`v1.9.0-mobile` / 1.9.0+25** |
| LAN 协议 | `cnkh-sync:v1` |
| OCR 同步 | 已支持 |

Desktop Release：
https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.3

Mobile v1.9.0 Release：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 收银 | 商品搜索、条码加购、购物车、行折扣、整单折扣、挂单与取单 |
| 收款 | 现金、银行卡、DuitNow、赊账、找零及欠款记录 |
| 商品与库存 | 商品、分类、成本与售价、进货、盘点、供应商管理 |
| 客户与销售 | 客户资料、今日与历史销售、销售详情、作废 |
| 小票与报表 | 小票模板、电子收据 PDF、WhatsApp 分享、销售与成本毛利报表、日结 |
| 局域网同步 | 二维码配对、HTTP 对账、WebSocket 变更通知、离线操作重试 |
| OCR 进货同步 | 接收 Mobile OCR Purchase 元数据、费用字段和 `purchase_reverse` 撤销 |
| 账号 | 管理员与员工权限、PIN 验证、员工 PIN 设置 |

现有收银金额、折扣、舍入规则和页面布局保持不变。

## OCR 进货同步

OCR 识别本身只在 Android Mobile 本机运行。Desktop 不做拍照 OCR，而是继续作为局域网权威主机。

完整流程：

```text
Mobile 拍照 / 相册
      ↓
本机 ML Kit OCR
      ↓
Draft
      ↓
商品匹配 / 异常检查
      ↓
人工确认
      ↓
Mobile 原子入库
      ↓
Persistent Outbox
      ↓
Desktop /api/v1/mutations
```

只有 Mobile 用户点击 **确认并入库** 后，才会产生正式 `purchase` mutation；未确认 OCR Draft 不会传到 Desktop，也不会修改 Desktop 库存。

### Desktop 接收的 OCR 数据

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
- OCR 原始数量 / 原始成本 / 原始小计
- Unit / Conversion 等进货行信息

收到尚未处理的 `purchase` operation 后，Desktop 会在事务内保存 Purchase、更新库存与成本、写 `stock_moves`、保存 OCR 元数据，并把 operation ID 写入 `sync_applied_operations`。同一 operation 重试不会再次加库存。

### OCR 进货撤销

Mobile 管理员撤销进货时会发送：

```text
kind = purchase_reverse
```

Desktop 会：

- 保留原 Purchase，不物理删除
- 标记为 reversed
- 回退本次进货增加的库存
- 生成负数库存流水
- 在安全条件下恢复进货前成本
- 保存撤销人员、时间、原因和备注
- 写 `purchase_reversals`
- 写 audit log
- 记录 operation ID，保证重复提交幂等

## 数据库兼容

OCR 同步字段采用增量迁移：

- 不清空旧数据库
- 不重建既有销售数据
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

Desktop 不保存 Mobile 的本地图片路径，因为该路径只在手机文件系统有效；原始单据图片保留在 Mobile 本机。

## 连接手机端

1. Windows 电脑与 Android 手机连接同一个 Wi-Fi / LAN。
2. Desktop 打开 LAN / 扫码配对页面并显示二维码。
3. Mobile 扫描二维码。
4. Mobile 保存 Desktop 地址和 Token。
5. 之后自动 WebSocket 重连、HTTP 对账和 Outbox 重试。

默认端口：**8787**。

二维码前缀：

```text
cnkh-sync:v1|
```

电脑需要保持运行，手机才能与其同步；手机断线时仍可本地销售和处理 OCR 草稿，恢复连接后自动重试已确认业务。

## 首次登录

1. 首次运行选择管理员 `admin`。
2. 输入自定 **6–12 位数字 PIN**。
3. 按提示再次输入相同 PIN 完成初始化。
4. 管理员可在用户管理为 `staff`、`staff2` 等员工设置 PIN。

PIN 连续输错 5 次会锁定 5 分钟。Desktop 与 Mobile 的账号凭据分别在本机管理，LAN 配对不会自动同步 PIN。

## 稳定性与同步行为

- 结账与扣库存使用同一数据库事务
- 作废回补库存并防重复回补
- 保存 Desktop / Mobile 商品与客户 ID 对照
- Mobile 销售、作废、资料修改、进货、盘点使用持久 Outbox
- 电脑确认后才从 Outbox 移除
- 重试不重复入库或扣库存
- 历史销售保存成交时成本
- 盘点/资料冲突不会静默覆盖
- OCR Purchase 与 `purchase_reverse` 同样使用 operation ID 幂等处理

详细稳定性说明见 [RELIABILITY_NOTES.md](RELIABILITY_NOTES.md)。

## 下载与安装

Desktop Releases：
https://github.com/tyz11234/CNKH_POS_Desktop/releases

配套 Mobile：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile

Windows 安装时请保留完整 Release 目录，包括 EXE、DLL 与 data 目录，不要只复制 `cnkh_pos_desktop.exe`。

## 开发与验证

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build windows --release
```

输出目录：

```text
build/windows/x64/runner/Release/
```

OCR 配套改动已验证：

- Desktop `flutter analyze`：通过
- Desktop tests：通过
- Windows Release build：通过
- OCR Purchase mutation：通过
- `purchase_reverse` 幂等测试：通过
- Desktop / Mobile 真实 HTTP / 断线重连回归：通过
- Mobile OCR `flutter analyze`：通过
- Mobile 32 项 tests：通过
- Mobile Android Release APK：通过

已验证 OCR Desktop 构建：
https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34023163144

Desktop / Mobile 联调：
https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34023163116

## 本次不包含

- Windows 摄像头 OCR
- 云 OCR
- AI / LLM OCR
- MyInvois / Malaysia e-Invoice
- 无人工确认自动入库
- 云端多门店同步

## 相关入口

- Mobile v1.9.0：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.9.0-mobile
- Mobile Flutter 源码：https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main
- Desktop OCR 同步 PR #7：https://github.com/tyz11234/CNKH_POS_Desktop/pull/7
- Desktop 稳定性修复 PR #6：https://github.com/tyz11234/CNKH_POS_Desktop/pull/6
