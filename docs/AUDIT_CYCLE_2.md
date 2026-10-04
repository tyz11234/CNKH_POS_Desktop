# Audit Cycle 2 — 追加 10 轮完整审查

更新：`2026-10-04T02:21:34.392987+00:00`。

本周期已完成 **2/10 轮**完整 Audit；已确认 **18 组**可复现产品/构建培训/发布流程缺陷；最后连续 **0 轮 Clean**。

当前功能分组 **42**（Shared 19 / Mobile 10 / Desktop 13）；**36/42** 有直接自动测试映射，**6/42** 保留目标设备/真实服务边界。本周期 PASS 只引用已完成轮次，未完成轮次不计为 Clean。

完整轮次 = 全量适用自动检查 PASS + 检查期间源码 hash 稳定 + Mobile/Desktop/DB-LAN/eInvoice-native-build 四域明确 review complete。

## 每轮状态与证据

| Cycle 2 Round | 全局 Round | 新确认缺陷组 | Mobile | Desktop | 跨端集成 | 状态 |
|---:|---:|---:|---|---|---|---|
| 1 | 7 | 9 | 160/160（失败 0，skip 0） | 183/183（失败 0，skip 0） | 29/29（失败 0，skip 0） | [已完成；修复后全量通过](audit-cycle-2/round-01/README.md) |
| 2 | 8 | 9 | 192/192（失败 0，skip 0） | 235/235（失败 0，skip 0） | 29/29（失败 0，skip 0） | [已完成；修复后全量通过](audit-cycle-2/round-02/README.md) |
| 3 | 9 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 4 | 10 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 5 | 11 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 6 | 12 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 7 | 13 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 8 | 14 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 9 | 15 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |
| 10 | 16 | 待审查 | 待运行 | 待运行 | 待运行 | 尚未开始 |

失败尝试和相同 Round 的环境重跑不增加轮数。Round 1 首次 Mobile 培训缺失 `.training_desktop` 前置目录的重跑属于同一轮环境修复。

## 已确认缺陷及永久回归

### C2-B001 — 非有限或溢出金额导致结账崩溃

- Round：1；平台：Mobile / Desktop。
- 修复前：Mobile 4 个实际结账用例、Desktop 3 个实际结账用例失败。
- 根因：double.tryParse 结果直接进入 round，NaN/Infinity/溢出值没有有效金额校验。
- 修复：共享有界整数分解析；支付确认拒绝无效输入，折扣/商品等入口验证。
- 永久测试：`checkout_money_input_regression_test / nonfinite_money_entry_test`。

### C2-B002 — 商品图片取消编辑或保存失败仍覆盖原图

- Round：1；平台：Mobile / Desktop。
- 修复前：真实 picker/file fixture 证明旧 PNG bytes 改变。
- 根因：选择图片即写入原商品确定文件名，先于商品保存。
- 修复：独立图片草稿版本；成功持久化后保留选中草稿，取消/拒绝清理未提交文件。
- 永久测试：`product_image_edit_regression_test / product_image_editor_safety_test`。

### C2-B003 — 销售作废被业务保护拒绝时缺少错误提示

- Round：1；平台：Mobile / Desktop。
- 修复前：StateError 未处理，预期错误提示不存在。
- 根因：作废 UI await repository 没有捕获拒绝异常。
- 修复：保留原销售，通过已有 Snackbar 展示拒绝原因并检查 mounted。
- 永久测试：`sale_void_error_regression_test / sales_list_boundary_error_test`。

### C2-B004 — 销售筛选漏掉结束日期最后的亚秒交易

- Round：1；平台：Desktop。
- 修复前：23:59:59.999999 销售未显示。
- 根因：结束日期上界设为 23:59:59，不含后续小数秒。
- 修复：使用次日零点的排他上界。
- 永久测试：`sales_list_boundary_error_test`。

### C2-B005 — 采购异价追加改写已有数量的成本

- Round：1；平台：Desktop。
- 修复前：1×100 + 1×200 被保存为 2×200（400 而非 300）。
- 根因：合并同商品数量后用新单价覆盖旧单价。
- 修复：只合并同单价行；不同单价保留独立行直至入库。
- 永久测试：`purchase_line_price_retention_test`。

### C2-B006 — 非法销售金额仍入账并扣库存

- Round：1；平台：Desktop LAN Host。
- 修复前：18 个非法金额案例均 HTTP200 imported=1，预期400且无副作用。
- 根因：宽松 _asInt 接受负数、截断小数，并将错误字符串置零。
- 修复：新导入销售校验整分及非负金额；保留 v1 数字字符串、可选字段及负 rounding 兼容。
- 永久测试：`lan_sale_amount_validation_test`。

### C2-B007 — 收款 QR 导入失败或重选本地图导致数据丢失

- Round：1；平台：Mobile / Desktop。
- 修复前：每端失败2/3：旧图丢失返回null，重选旧图内容为空。
- 根因：导入前删除异扩展旧图；复制文件到自身会截断原图。
- 修复：复制至唯一新文件、提交 preference 后再清理旧 app-owned 文件。
- 永久测试：`qr_storage_import_safety_test`。

### C2-B008 — 培训截图及步骤落后于当前 Desktop 税务功能

- Round：1；平台：Mobile training / Both lessons。
- 修复前：Mobile 2 项课程/源码契约回归失败。
- 根因：固定 v0.4.0 Desktop 源码，课程遗漏证书和 Invalid 纠错步骤。
- 修复：培训与跨端集成读取同一配对 SHA；更新 PFX/P12、Invalid、Submission UID 和更正尝试说明。
- 永久测试：`training_source_regression_test / training_content_regression_test`。

### C2-B009 — 发布允许替换已有同版本资产及错误 tag

- Round：1；平台：Mobile / Desktop release workflows。
- 修复前：现行 workflow 契约失败；已存在 Release 可被默认 action 更新。
- 根因：Release action 默认覆盖，未校验 tag/pubspec/SHA，main/tag 发布未共同串行。
- 修复：只读 immutable Release gate、统一 tag、annotated tag/SHA 验证、发布 mutex、禁止 overwrite。
- 永久测试：`tool/test_release_gate.py（每端26项）`。

### C2-B010 — 进货、OCR与日结接受超界金额或非法数量

- Round：2；平台：Mobile / Desktop。
- 修复前：真实SQLite巨量进货被保存，OCR已保存draft编辑乘除崩溃，QR NaN崩溃且0/-1改为1。
- 根因：边界检查只看原始值，缩放/乘除后的金额仍可Infinity或int64饱和；QR零负数量被改成1。
- 修复：复用整分精度上限并检查实际计算结果，非法输入保留原单据且阻断提交。
- 永久测试：`purchase_import_validation_test / purchase_amount_boundary_regression_test / ocr_quantity_boundary_regression_test / purchase_edit_service_test`。

### C2-B011 — 扫码在购物车接受决定前播放成功反馈

- Round：2；平台：Mobile / Desktop。
- 修复前：延迟拒绝与未完成回调仍读取feedback或产生扫码成功声。
- 根因：void callback忽略异步库存检查的false、pending和异常。
- 修复：回调返回Future<bool>，只有await true才计数和反馈，异常沿用Snackbar。
- 永久测试：`scanner_cart_acceptance_regression_test / scanner_acceptance_feedback_test`。

### C2-B012 — 库存盘点非法数量或保存失败没有可用提示

- Round：2；平台：Desktop。
- 修复前：实际NaN输入抛未处理异常，无错误提示。
- 根因：UI直接传NaN并让repository异常逃逸。
- 修复：输入先验证，写入失败显示Snackbar并保留库存。
- 永久测试：`admin_entry_error_feedback_test`。

### C2-B013 — 收据模板保存与重置失败后缺少错误反馈

- Round：2；平台：Desktop。
- 修复前：真实保存按钮触发StateError，无失败提示。
- 根因：设置写入的异常没有UI恢复分支。
- 修复：保存/重置捕获失败并解除busy，保留编辑值和现有提示机制。
- 永久测试：`admin_entry_error_feedback_test`。

### C2-B014 — 聚焦弹窗关闭时提前释放输入控制器

- Round：2；平台：Mobile / Desktop。
- 修复前：产品、采购、折扣、实体、用户及销售原因保存/取消实际抛TextEditingController used after disposed。
- 根因：Navigator.pop完成时退出动画仍使用TextField，立即dispose使框架访问已释放controller。
- 修复：等待DialogRoute.completed再释放各真实受影响入口的控制器。
- 永久测试：`product_dialog_lifecycle_regression_test / purchase_amount_boundary_regression_test / admin_dialog_controller_lifecycle_test / cart_discount_dialog_lifecycle_test / sale void regressions`。

### C2-B015 — 有效库存加减仍可产生Infinity库存或流水

- Round：2；平台：Mobile / Desktop / LAN。
- 修复前：两端真实SQLite库存/流水Infinity持久化；Desktop无穷reorder破坏JSON产品快照。
- 根因：输入有限但当前库存与变动合算溢出，SQLite允许保存Infinity。
- 修复：事务内校验实际新库存及差额，异常原子回滚，补reorder有限校验。
- 永久测试：`stock_numeric_integrity_test / existing OCR, identity and reversal regressions`。

### C2-B016 — 进货分币被截断成其他金额并确认

- Round：2；平台：Mobile / Desktop / LAN Host。
- 修复前：12个LAN非法金额均被接受；真实Repo小数unit cost被截断。
- 根因：unitCost和LAN进货fees使用toInt截断小数，负0.5变成0绕过保护。
- 修复：写入前验证有限非负整分，非法mutation不产生purchase、stock或durable ACK。
- 永久测试：`lan_purchase_amount_validation_test / stock_numeric_integrity_test`。

### C2-B017 — HTTP200 JSON null被误认为Release不存在

- Round：2；平台：Mobile / Desktop release scripts。
- 修复前：真实localhost两个HTTP200/null查询使发布检查PASS。
- 根因：成功响应null与HTTP404共同返回None。
- 修复：成功GET必须为对象，只有404代表不存在，异常形态fail closed。
- 永久测试：`tool/test_release_gate.py`。

### C2-B018 — 发布检查漏掉同tag草稿Release

- Round：2；平台：Mobile / Desktop release scripts。
- 修复前：符合官方契约的localhost published/ref404且同tag draft存在时门槛误PASS。
- 根因：by-tag仅查published，旧草稿可被Release action复用并保留旧同名资产。
- 修复：认证GET全部分页Release列表，发现同tag即阻断，异常/不前进分页fail closed。
- 永久测试：`tool/test_release_gate.py（每端40项，含13项真实localhost草稿/分页回归）`。

## 既有 Windows 测试同步问题

两项既有测试同步问题单独记录：固定等待后过早检查 sale callback；supplier UI 事务未结束时轮询数据库造成等待锁/停止 pump。双端 phone 与 Desktop supplier 测试已保留业务断言改为有界实际状态等待。这 **不计入本周期新产品 Bug 数**，也不使 Linux 通过自动变为 Windows CI 通过。
证据：[`Round 1 Windows diagnosis`](audit-cycle-2/round-01/windows-test-diagnosis.md)。

## 动态功能与数据库清单

| 来源 | Dart lib | Screens | Services | DB modules | Widgets | Test files | Version |
|---|---:|---:|---:|---:|---:|---:|---|
| mobile | 70 | 18 | 30 | 6 | 7 | 59 | 1.10.9+37 |
| desktop | 76 | 17 | 37 | 6 | 7 | 61 | 1.10.9+37 |

SQLite schema v10、LAN `cnkh-sync:v1` 保持。Mobile 26 张运行表；Desktop **26 张运行表**，包含 LAN Host 启动创建的 `lan_sync_changes` / `lan_sync_mobile_sales`。Cycle 1 历史清单写 Desktop 24 是未计入 Host 两表的统计口径，当前周期已纠正。

## 外部边界与最终 CI / 发布

- Android 同签名正式 APK/覆盖升级：匹配旧 APK 的签名私钥仍未验证；本周期不宣称签名 Gate 通过。
- Android 相机/权限/打印硬件、Windows GUI/实体打印机、门店 Wi-Fi、防火墙及真实 MyInvois Sandbox/Production：目标设备/凭据缺失，保留静态、mock、localhost、文件/字节测试与所需现场验收。
- 新候选源码的 GitHub CI：**待最终提交后的实际 CI 结果**。本地十轮不替代 Windows/Android 构建。
- 新版本 Final Release Regression、tag、Release、产物重新下载：**待轮次及最后连续两轮 Clean、最终回归与平台 Gate 完成**；尚未生成或发布的包不列作可下载产物。
- 既有 Desktop `v1.10.9` Release 和 Mobile `v1.10.7-mobile` 的下载/校验/签名说明保留为历史，详见 README 与 Cycle 1 文档。
