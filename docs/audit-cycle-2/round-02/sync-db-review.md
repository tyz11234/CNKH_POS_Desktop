# Audit Cycle 2 · Round 2 / 全局 Round 8 · DB / Repository / LAN / Backup

基线：Mobile `230f4768ce24b6fa3a0181351246a22b5907a715`；Desktop `cd6c9db754f94fd83f2b018cd7d64791ceaa3087`。
重新检查当前工作区，保留 root 的 docs / paired ref / training 生成文件。没有修改原工作区、UI、schema version 或协议。

## 本轮全范围重扫

`sync/dynamic-inventory.json` 记录当前 18 个 Mobile / 20 个 Desktop DB、Repository、LAN、maintenance 与备份文件的完整 hash、行数、函数入口以及动态表 / 索引 / 触发器 / endpoint 清单。
覆盖全部双端 `lib/db/`，核心 Repo 的产品/分类/客户/供应商、销售/挂单/进货/库存/日结/报告/设置 SQL；Mobile legacy migration、OCR 入库、独立 history、reverse ACK/rejection、image queue；Desktop Host、全部 mutation、身份 alias、Backup/Restore 与 DB maintenance。
本轮异常/边界重点不取代其余范围：复查了升级 ensure / Outbox seq 保留、全部 LAN endpoint 认证/读取/写入、旧 v1 peer / 缺省字段 / 重试、损坏备份 staged migration / 双资源回滚 / 清理失败、integration 现有断网 / ACK 丢失 / cursor rollback / 库存依赖场景。

## 真实问题 1：有限库存输入的算术结果能成为 Infinity

- Both：已有 stock=`1e308`，`adjustStock(newStock:-1e308)` 或 product edit 为 `-1e308`。新/旧输入分别有限，差值却为 `-Infinity`，原实现成功写入 stock_moves。
- Both：已有 stock=`1e308`，进货 qty=`1e308`。输入数量有限且正，SQL `stock+qty` 得到 Infinity，原实现成功写入 product 和 purchase。
- Desktop：reorderLevel=Infinity 原实现成功持久化，随后 JSON 目录接口不能编码该值。Mobile 同值在 Outbox JSON 编码时事务拒绝，没有发生此项数据持久化损坏；不能把 Mobile 错误类型差异当第二个产品 Bug。
- 根因位置：双端 `pos_repository.dart` 只检查输入有限，不检查最终 stock / ledger delta；相关 LAN、OCR、sale reversal、ACK 补偿也使用同类运算。
- Before：Desktop 新 4 个案例均错误完成成功；Mobile 三个库存/流水案例错误完成成功，另 reorder 被现有 JSON error 拒绝。原始日志 `sync/{desktop,mobile}-stock-before.log`。
- 修复：两端新增同内容 `stock_numeric_validation.dart`（checked difference + transaction stock addition），在实际 SQL 写入前阻止非有限结果。复用到产品编辑/盘点/手动进货/销售/作废、LAN mutation / sale import、Mobile OCR、reverse ACK/rejection 与 catalog ledger。reorder 输入在 product 边界拒绝非有限值。所有原 SQL、事务所有者、有效大数、负库存策略、离线队列顺序保留；没有给正常数量引入任意上限。
- 永久测试：两端 `stock_numeric_integrity_test.dart` 对产品、流水、业务行、Outbox 原子保留作断言。

## 真实问题 2：进货分币数据被截断或原样写入非整数

- Both Repository：调用 createPurchase 的 unitCostCents=`1.5`，原实现 `.toInt()` 截为 1 分，成功记录进货和变更商品成本。
- Desktop LAN：purchase mutation 的 `discount_cents` / `tax_cents` / `delivery_fee_cents` / `other_fee_cents`、line `unitCostCents` / `subtotalCents` 为 `-0.5` 或 `1.5`。原实现接受 12 / 12 非法案例；负半分 unit cost 被 `.toInt()` 截为 0，其余 metadata 保存为 SQLite REAL / JSON 非整数。
- 根因：`pos_repository.dart` 数值验证只判负数；`lan_mutations.dart` line cost 先截断，metadata 未验证。
- Before：Both Repository 各 1 个案例均错误完成成功；LAN 新 12 个案例均错误完成成功。日志 `sync/{desktop,mobile}-cost-before.log`、`sync/desktop-purchase-before.log`。
- 修复：Both Repository 的成本要求有限、非负、整分；Desktop LAN optional fee / line cost / invoice unit cost / subtotal 要求同样格式，仍保留缺省 optional fields 与完整整数数值（包括 100.0）。所有验证都在 business transaction 内，拒绝时不写永久 ACK；旧真实整数 payload 的幂等/重复 Invoice / reversal 兼容通过既有测试。
- 永久测试：两端 stock numeric 文件的额外 unit cost case；Desktop `lan_purchase_amount_validation_test.dart` 12 项断言 purchase / ledger / operation ACK / stock / cost 全部不变。

## 真实问题 3：Desktop 进货编辑 parser 仅验证乘 100 前的值

- 根因：`PurchaseEditService.parseMoneyCents` 的 locale 正规化后，只检查 RM 值有限，随即 `(value * 100).round()`。308 位有效十进制输入的 RM 值仍有限，但 cents 为 Infinity，触发未处理 `Unsupported operation`；超过 exact-cent 上限的值也会作为有效结果返回。
- 实际 before：新 2 个案例均失败；308 位输入抛 Infinity toInt，`90071992547409.92` 返回 `9007199254740992`，证据 `sync/desktop-purchase-parser-before.log`。
- 最小修复：保留 parser 所有 RM / 千分位 / decimal locale 正规化和 regex，最后复用现有 `tryParseRmCents` 的 scaled finite / exact-cent 检查。新 2 个案例永久加入 `purchase_edit_service_test.dart`。

## 已实际执行的针对性回归

- 首次库存修复回归：Desktop **27/27 PASS**（numeric、reliability、document number、sale identity、reverse safety）；Mobile **19/19 PASS**（numeric、reliability、document number、reverse sync、attachment）。日志 `sync/{desktop,mobile}-stock-after.log`。
- 最终库存 + 进货金额回归：Desktop **30/30 PASS**（numeric 5、LAN purchase 12、OCR mutation 7、reverse safety 6），`sync/desktop-final-after.log`。
- Mobile **28/28 PASS**（numeric 5、OCR 17、reverse sync 2、stock move sync 4），`sync/mobile-final-after.log`。
- Desktop 进货编辑 parser 全文件 **5/5 PASS**（新异常 2 + 既有 locale / safe metadata / duplicate guard 3），`sync/desktop-purchase-parser-after.log`。
- 新增永久 regression：Mobile 5；Desktop 19（含进货编辑 parser 2 个）。`git diff --check` 通过。完整 analyze/test/integration 由 root 汇总，以上 targeted PASS 不替代全量 Gate。
- 一次 Mobile command 引用了不存在的 `purchase_ocr_repository_test.dart`，已换成当前真实的 `purchase_ocr_test.dart` 并完整重跑；不是产品 Bug，没有 skip / 删除任何现有测试。

## 边界与后续

- SQLite migration、FK/index/trigger、Backup 原子回滚、合法 ACK / retry / pending ordering 未发现额外可复现问题；既有动态 tests 仍由全量 Gate 复验。
- 超大 native int cart 金额乘法、备份创建并发的 snapshot 一致性仍属后续验证方向，尚无证明，不计 Bug。
- Desktop purchase 编辑字符串金额 scaled overflow 经 root 交由本代理验证，已按上文修复纯 service parser；本代理未改页面。
- 实机升级 / Windows 文件锁 / 门店 Wi-Fi、相机、打印机、MyInvois 真服务仍需对应环境；静态路径已覆盖，不宣称此轮完成真实外部验收。

本代理相关产品源代码已冻结，等待 root 全量 Gate 和 Round 3。
