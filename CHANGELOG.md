# CNKH POS Desktop change log

## 1.10.10+38 — 2026-10-08，安装包待 CI 构建

- **F01（双端）** 逐行删空购物车时清除整单折扣，下一笔销售不再继承旧折扣。
- **F02（Desktop）** 进货追加相同商品但不同成本时保留独立明细，维持准确总额和最终成本顺序。
- **F03（Desktop）** 进货不再合并不同 ID 或不同明确编码的同名商品；按名称匹配时要求结果唯一。
- **F05（双端）** 商品保存、进货建品和电脑接收修改采用一致的条码 / SKU 冲突检查；旧歧义数据拒绝扫码误选，不自动删除商品。
- **F06（Desktop）** 使用最终 Invoice 1.1 内容计算摘要和数字签名，并拒绝旧的错版本签名。
- **F09（双端）** 12 位数字条码使用 Code128 原样编码，打印标签不再自动追加第 13 位。
- **F11（双端联动）** 更正发票接口返回原销售收据号，并独立保留 invoice_no，使手机正确关联电脑销售的发票状态。
- **F12（双端）** 新挂单保存售价及显示快照；取单保留原价，同时使用当前库存和删除状态检查，兼容旧挂单。
- **F13（Desktop）** 报表响应交易及导航刷新，保留手选日期，并忽略过期异步查询结果。
- **F14（双端）** 现金 / 定金以整数分解析并明确校验，拒绝 NaN、Infinity、指数及超范围输入。
- **F15（双端）** PDF 和蓝牙打印输出已配置的 DuitNow 付款图片，保留比例和留白；缺图时不输出扫码提示。
- **F16（Desktop）** 销售日期筛选使用次日排他上界，包含结束日最后一秒的小数部分。
- 配套版本同时修复Mobile 的未同步销售保护、恢复后完整对账、待核对状态同步和配置刷新；完整 16 项清单见 [Release Notes](RELEASE_NOTES.md)。
- 数据库 schema v10 和 `cnkh-sync:v1` 保持不变。
- 本地验证：Mobile 187 项及跨端 HTTP / WebSocket 29 项通过；Desktop 全量 187 项通过、1 项测试等待失败，调整等待后包含电子发票的 25 项定点复测通过。两端 analyze 无 error，条码及收据二维码独立解码通过。
- 发布安装包、校验值、CI 记录和 APK 签名兼容性待核实；未进行实体设备、打印机或 MyInvois 线上验收。

## 1.10.9+37 — 2026-10-03

- **B001 (Both):** Read the installed Version and Build Number in About instead of maintaining duplicate Dart constants.
- **B003 (Both CI):** Pin paired repository refs to the companion 1.10.9+37 source commits.
- Completed six audit rounds; Rounds 5 and 6 were clean. Final regression passed Mobile 147/147, Desktop 151/151, and paired integration 29/29.
- SQLite schema v10 and `cnkh-sync:v1` remain unchanged.

## 1.10.8+36 — released 2026-10-03

- **B01** Clear a previous customer-directory phone on customer change/cancel while preserving a manually entered temporary number for the saved sale and eReceipt recipient.
- **B03** Validate required current tables/columns and POS queries, migrate supported old backups through the application upgrade path, and keep rollback DB/images until the restored production path reopens and validates.
- **B06** Persist a click-time held-cart snapshot, guard duplicate submits, and clear only an unchanged cart after success.
- **B07 / B11** Add SQL-stable product ordering and progressive search/pagination to product admin, stocktake, purchase selection, compact/full cart, and audit history.
- **B08** Return a structured sale-void business refusal while tax state needs review; keep the operation idempotent and block unsafe duplicate stock reversal.
- **B09** Refresh catalog/category/image settings in the retained cart screen without repricing cart snapshots or replacing manual discounts.
- **B10 / R03** Keep the 80 mm receipt and paginate long receipts with Chinese text.
- **B12** Resolve newly created suppliers from the refreshed picker list by stable ID.
- **B13** Propagate Windows clipboard failures and use the existing share fallback instead of reporting a false success.
- **R01** Pause and drain background DB polling during restore; stop accepting LAN requests and drain in-flight requests before replacing the production database.
- **R04** Ignore stale catalog-search responses using request generations.

MyInvois signing changes are not included. Latest official requirements and an independent verifier remain necessary to resolve R02. No production submission or cancellation was performed.

## Ongoing maintenance

For each future build, update `version` in `pubspec.yaml` and add the real changes to this file. About reads Version + Build Number from installed package metadata; do not add a second version constant. Keep prior release entries. `test/app_version_test.dart` checks the runtime label and changelog version.
