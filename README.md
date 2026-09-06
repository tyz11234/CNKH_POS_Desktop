# 黄金发宝号 · CNKH POS Desktop

用于 Windows 电脑的门店收银与管理系统。电脑作为店内局域网权威主机，与 [CNKH POS Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK) 配套使用，核心收银与店内同步不依赖云服务器。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。

[下载与构建](#下载与安装) · [首次登录](#首次登录) · [手机配对](#连接手机端) · [OCR 进货同步](#ocr-进货同步) · [修复说明](RELIABILITY_NOTES.md)

> 更新日期：**2026-09-06**。Desktop `main` 已包含稳定性修复及 Mobile v1.9.0 OCR 进货同步兼容。

## 当前状态

| 项目 | 状态 |
| --- | --- |
| Desktop 源码 | `main`，已包含稳定性修复及 OCR 进货同步兼容 |
| 配套 Mobile 源码 | [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)，版本 **1.9.0+25** |
| LAN 协议 | `cnkh-sync:v1`，OCR 功能未更换协议版本 |
| Desktop OCR 同步 PR | [#7 Support OCR purchase metadata and reversals](https://github.com/tyz11234/CNKH_POS_Desktop/pull/7)，已合并 |
| OCR 配套 Windows 构建 | [Actions 34023163144](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34023163144)，通过 |
| Desktop↔Mobile 联调 | [Actions 34023163116](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34023163116)，通过 |
| 最近正式 Desktop Release | [v0.3.2](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2) |
| Desktop 源码版本字段 | `0.3.2+5`；本次 OCR 配套同步没有改 Desktop UI 或业务版本号 |

OCR 文字识别本身只在 Android Mobile 本机运行；Desktop 不负责拍照或 OCR 推理，Desktop 继续承担店内局域网权威主机和最终同步落库角色。

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 收银 | 商品搜索、条码加购、购物车、行折扣、整单折扣、挂单与取单 |
| 收款 | 现金、银行卡、DuitNow、赊账、找零及欠款记录 |
| 商品与库存 | 商品、分类、成本与售价、进货、盘点、供应商管理 |
| 客户与销售 | 客户资料、今日与历史销售、销售详情、作废 |
| 小票与报表 | 小票模板、电子收据 PDF、WhatsApp 分享、销售与成本毛利报表、日结 |
| 局域网同步 | 显示配对二维码、接收手机业务、同步库存与销售、HTTP 对账及 WebSocket 变更通知 |
| OCR 进货同步 | 接收 Mobile OCR Purchase 元数据、费用字段和 `purchase_reverse` 撤销操作 |
| 账号 | 管理员与员工权限、实际 PIN 验证、员工 PIN 设置 |

现有收银金额、折扣、舍入规则和页面布局保持不变。DuitNow 收款码展示不等同于银行自动到账确认。

## OCR 进货同步

Mobile v1.9.0 新增本机 OCR 智能进货。完整 OCR 流程发生在手机端：

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
Mobile 本地原子入库
      ↓
Persistent Outbox
      ↓
Desktop /api/v1/mutations
```

Desktop 不信任未确认 OCR 草稿，也不会因为手机刚扫描一张单据就修改库存。只有 Mobile 用户明确确认进货后，才会产生正式 `purchase` mutation。

### Desktop 接收的 OCR Purchase 数据

原有 `purchase` mutation 继续使用，没有新开另一套同步协议。OCR 版本额外兼容以下可选字段：

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
- OCR 行的原始数量 / 原始成本 / 原始小计
- Unit / Conversion 等进货行信息

这些字段用于追溯和显示，不改变 Desktop 原有销售金额和收银计算规则。

### Desktop 落库行为

收到一个尚未处理的 OCR `purchase` operation 后，Desktop 会在事务中：

1. 保存正式 Purchase
2. 更新对应商品库存
3. 在有成本时更新商品成本
4. 写入 `stock_moves`
5. 保存 Invoice / OCR 元数据
6. 写入 OCR purchase audit 记录
7. 将 operation ID 写入 `sync_applied_operations`

同一个 operation ID 再次重试时，不会再次加库存。

### OCR 进货撤销同步

Mobile 管理员撤销已确认 OCR 进货时，会产生：

```text
kind = purchase_reverse
```

Desktop 收到后会：

- 找到原 Purchase
- 保留原 Purchase，不物理删除
- 将 Purchase 标记为 reversed
- 生成负数库存流水
- 回退本次进货增加的库存
- 在安全条件下恢复进货前成本
- 保存撤销人员、时间、原因和备注
- 写入 `purchase_reversals`
- 写入 audit log
- 记录 operation ID，保证重试幂等

如果同一个撤销 operation 因断线重发，不会重复扣库存。

### 数据库兼容方式

Desktop 对 OCR 字段使用增量兼容迁移：

- 不清空旧数据库
- 不重建现有销售资料
- 不修改旧 Purchase 的既有字段含义
- 旧版普通进货仍然可读取
- 新 OCR 字段对旧记录使用默认值

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

Desktop 不保存 Mobile 的本地图片路径，因为该路径只在手机文件系统有效；原始单据图片仍保留在 Mobile 本机。

## 下载与安装

### 当前已验证构建

Desktop OCR 配套构建：

- [Windows Release 构建](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34023163144)
- [Desktop / Mobile LAN 联调](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34023163116)
- [Mobile v1.9.0 正式构建](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34023967305)

登录 GitHub 后，在运行页面下方 **Artifacts** 可下载对应构建。Actions 产物有保留期限，过期后可通过源码重新构建。

Windows 安装步骤：

1. 下载并解压 Windows artifact；若其中还有程序 ZIP，再解压一层。
2. 保留完整程序目录，包括 DLL 与 `data` 文件夹。
3. 运行 `cnkh_pos_desktop.exe`，不要只复制 EXE。
4. 配套更新 Mobile v1.9.0 后，再进行 OCR 进货同步测试。

### 既有正式发布

[v0.3.2 Release](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2) · [所有 Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases)

v0.3.2 是此前正式发布版本；OCR 进货同步兼容已进入 `main`，如正式 Release 页面尚未产生更新包，请以当前 `main` 构建或 Actions artifact 为准。

## 首次登录

首次运行修复版，或从尚未设置真实 PIN 的旧版升级时：

1. 在原登录页选择管理员，用户名使用 `admin`。
2. 输入自定的 **6–12 位数字 PIN**，点击登录。
3. 按提示再次输入同一 PIN，完成初始化并登录。
4. 在用户管理列表点选员工，为员工设置 PIN。

预置员工账号包括 `staff`、`staff2`，需要管理员先分配 PIN。登录页的角色选项不会提升账号权限，实际角色以数据库账号记录为准。

PIN 连续输错 5 次会锁定 5 分钟。恢复出厂业务数据时保留管理员 PIN，员工 PIN 需重新设置。两端账号凭据分别在本机管理，配对不会自动同步 PIN。

## 连接手机端

1. 电脑与 Android 手机连接同一 Wi-Fi 或可互通的局域网。
2. 启动电脑端，打开 LAN / 扫码配对页面，显示二维码。
3. 手机端点击扫码配对，扫描电脑二维码。
4. 手机保存电脑地址和配对令牌，完成同步。

默认端口为 **8787**，二维码前缀为 `cnkh-sync:v1|`。若连接失败，检查电脑是否运行、IP 是否变化，以及 Windows 防火墙是否允许该程序在专用网络通信。

电脑需要保持运行，手机才能与其同步；手机暂时断线仍可本地开单和处理 OCR 进货草稿，恢复连接后自动重试已确认业务。

## 稳定性修复带来的行为

- 结账与扣库存使用同一数据库事务；启用“禁止缺货”时复查实际库存。
- 作废回补库存并防止重复回补；手机作废能上传，电脑作废能回传。
- 保存两端商品与客户 ID 对照，避免条码匹配后扣错库存或丢失赊账关联。
- 已配对手机的销售、作废、资料修改、进货及盘点写入持久队列，电脑确认后才移除。
- 断线后自动重试，同一操作不会因重复提交再次入库或扣库存。
- 电脑界面响应远程业务变化；历史销售查询取消默认 200 条截断。
- 新销售保存当时成本；后续修改商品成本不会改变这些销售的历史毛利。
- OCR Purchase 与 OCR Purchase Reverse 同样使用 operation ID 幂等处理。

若盘点或资料修改发生冲突，系统会保留待同步操作并提示错误，不会静默覆盖另一端。请核对业务记录后处理，不要靠清空手机数据解决冲突。

旧销售未保存的历史成本无法凭空恢复；升级前已作废的旧单不会被批量自动回补。详细说明见 [RELIABILITY_NOTES.md](RELIABILITY_NOTES.md)。

## 开发与验证

在具备 Flutter Windows 桌面构建环境的电脑上执行：

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build windows --release
```

完整程序输出目录：

```text
build/windows/x64/runner/Release/
```

OCR 配套改动已验证：

- Desktop `flutter analyze`：通过
- Desktop tests：通过
- Windows Release build：通过
- OCR Purchase mutation：通过
- `purchase_reverse` 幂等测试：通过
- Desktop / Mobile 既有真实 HTTP / 断线重连联调：通过
- Mobile OCR `flutter analyze`：通过
- Mobile **32 项 tests**：通过
- Mobile Android Release APK：通过

自动化通过不代表已验证所有实际打印机、供应商单据格式和 Android 手机型号。OCR 最终入库前仍要求人工核对。

## OCR 当前范围

Desktop 本次只加入 Mobile OCR 进货的同步兼容，不加入：

- Windows 摄像头 OCR
- 云 OCR
- AI / LLM OCR
- MyInvois / Malaysia e-Invoice
- 无人工确认自动入库
- 云端多门店同步

这些功能不属于本次范围。

## 相关入口

- [Android 下载主页](https://github.com/tyz11234/CNKH_POS_Mobile_APK)
- [Android Flutter 源码](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)
- [Desktop OCR 同步 PR #7](https://github.com/tyz11234/CNKH_POS_Desktop/pull/7)
- [Desktop 稳定性修复 PR #6](https://github.com/tyz11234/CNKH_POS_Desktop/pull/6)
