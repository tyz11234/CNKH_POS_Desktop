# Audit Cycle 2 · Round 1 / 全局 Round 7 · DB / LAN / Backup 审查

本报告限定 DB、持久化 Repository、LAN Host/Client 与备份域；全项目测试由 root 统一执行。
基线为两端最新隔离 checkout，未修改原工作区。已读取上传 master README、当前 BUG_AUDIT、FEATURE_INVENTORY、LAN_SYNC、MOBILE_PC_PARITY；本 checkout 内未发现 AGENTS.md。

## 动态范围

`sync/dynamic-inventory.json` 记录本轮重新扫描的文件 hash、声明 table/index/trigger、endpoint 与 mutation kind。

- Mobile：16 个 DB/Repository/Sync 相关文件，27 张声明表（含迁移临时 `sync_outbox_v10`；26 张业务/运行表），9 个 index、4 个 trigger、14 个客户端 REST 路径。
- Desktop：18 个相关文件，26 张声明表（含 Host 启动时的 `lan_sync_changes` / `lan_sync_mobile_sales`），9 个 index、18 个 Host change trigger、15 个 REST/WS 路径。
- 全部 `lib/db/*.dart`；双端 `pos_repository.dart`、`sync_store.dart`、`lan_sync.dart`、`sale_reversal.dart` / `purchase_reverse_plan.dart`；Mobile legacy Outbox migration / purchase history / reverse ACK / catalog baseline / image queue；Desktop `lan_pairing_host.dart`、`lan_mutations.dart`、`lan_product_identity.dart`、backup / maintenance。
- 读取 integration 现有 3 组测试入口和 test 映射；本代理仅执行针对性回归，未将静态覆盖宣称为完整动态测试。

## 已证实并修复：LAN 销售金额未经验证即持久化

- 平台：Desktop Host；Mobile 到 Desktop 的非法/损坏销售 payload 可进入此入口。
- 触发：认证后 POST `/api/v1/sales`，商品/数量有效，任意 `subtotal_cents` / `total_cents` / `paid_cents` / `change_cents` / `discount_cents` / `order_discount_cents` 为 `-1`、`1.5` 或 `"invalid"`。
- 根因：`lan_pairing_host.dart` `_postSales` 使用宽松 `_asInt`，负数原样写入，小数截断，无效字符串回落 0；API 返回 HTTP 200 / imported=1，随后产生销售与扣库。
- 修改：同文件 `_saleAmount`（约 line 1514）只允许整分，普通金额非负，rounding 可负；保持旧 v1 整数字符串及缺省 paid / optional amount 兼容。验证位于新导入交易的业务写入前；existing sale identity 幂等 / 取消路径不变。schema v10、`cnkh-sync:v1`、Outbox / ACK 约定不变。
- 永久回归：`test/lan_sale_amount_validation_test.dart`，18 个非法金额案例断言 HTTP 400 且无 sales / identity mapping / stock move / inventory 修改；另 1 个 legacy integer-string / optional-field / negative-rounding 兼容案例。
- 实际 before：19 个测试中 18 个失败（每个非法 payload 均 HTTP 200、imported=1），1 个兼容案例通过。证据 `sync-sale-amount-before.log`。
- 实际 after：新增 19 + `sale_identity_sync_test.dart` 5 + `lan_host_sync_safety_test.dart` 2 = **26 / 26 PASS**。证据 `sync-sale-amount-after.log`。
- Linux 环境只有 libsqlite3.so.0，测试 isolate 找不到未版本化 `.so`；使用 `/workspace/toolchains/native-libs/libsqlite3.so` 系统库链接和 LD_LIBRARY_PATH 解决，仅为工具链修复，不计产品 Bug。

## 生命周期与已有回归映射

| 域 | 本轮读到的实现与边界 | 现有测试 |
|---|---|---|
| DB 打开/升级/重复 ensure | 两端 AppDatabase `_opening` 重试、v10、FK、增量 columns、schema ensure；Mobile v7/v9 Outbox 保留、seq 与 legacy baseline；Desktop backup 真实迁移与必要列/integrity 验证 | Mobile `database_migration_test.dart`；Desktop OCR migration / backup validation |
| Transaction / 单号 | 销售扣库、Outbox、stock move 同事务；current stock block policy 聚合同商品数量；document_sequence 保留删除/并发/失败 rollback，Desktop 保留税票号码 baseline | 双端 `reliability_test.dart` / `document_numbers_test.dart` |
| Product/Customer/Supplier/Category CRUD | `_saveEntity` 持久化、软删除、original conflict merge、产品编辑 ledger、分类重命名 / 删除关联产品；历史 ID 保留；首次配对自然身份唯一匹配 | entity CRUD / recreated entity / product delete tests |
| Sale/credit/report/closing | createSale、cost snapshot、paid/deposit、receipt identity、void guard/reversal、日结事务 SQL 与利润历史成本 | reliability / checkout / daily closing / profit tests；integration F11 |
| Purchase / reversal | 数量有限且正、transaction cost snapshot、Desktop request idempotence；all-line reversal preflight；Mobile Desktop-origin trigger、ACK 延迟、本机旧撤销拒绝补偿、needs_review 保留 | purchase reverse plan / purchase reverse sync / OCR purchase sync tests |
| 全部 LAN endpoints | 认证在 dispatch 前，健康能力、WS / events / notify、全量/增量目录、product image、sales、purchases、stock moves、einvoice、categories、barcode_queue；输入解析与结构化拒绝 | host safety / sale identity；integration `pos_pair_test.dart` / `eleven_bug_entries_test.dart` / `offline_cancel_test.dart` |
| Outbox / ACK / 重试 | FIFO、operation ID、逐单 receipt ACK、逐项 mutation ACK、ACK 丢失重试、未知拒绝阻断顺序、attachment 独立 retry、sale_void 审核 barrier、stock authoritative snapshot 在 pending 检查后事务 commit | integration lost ACK / offline cancel / stocktake conflict / pending old purchase；Mobile stock move / attachment tests |
| Cursor / identity | catalog 4 返回游标最小值；missing full rows 只软删映射资料；Stock cursor rollback 替换 host-owned marker；Immutable product alias / recreated entity mapping；purchase history 不改 stock | integration backup cursor / F02 / stale SKU；Mobile recreated/history/stock move tests |
| Connection / lifecycle | Mobile mutex、generation guards、5s poll 重连、WebSocket 事件补偿；Desktop Token 旋转关闭连接、stopAndDrain、maintenance poll gate | integration initial offline reconnect；Desktop maintenance drain test |
| Backup / restore | ZIP manifest/integrity/schema 验证、staged migration、safe image paths、DB/images 对替换、exact active reopen、失败 rollback、cleanup failure 不撤销成功恢复、跨账号图片 path rebase | Desktop backup + backup validation + maintenance tests |

## 需要 root 合并到报告的界限

- 实体门店 LAN、防火墙/IP 变化、真实 Android/Windows 启动、实体文件锁仍需平台验收；此轮静态审查已执行，自动测试只能验证 localhost HTTP/SQLite/受控异常，不宣称实体端到端通过。
- Desktop `LAN_SYNC.md` 和 `MOBILE_PC_PARITY.md`（Mobile 同文）顶部仍写 1.10.9 未发布、最新 Desktop 1.10.8；已给 root 提醒与 README 中已发布 v1.10.9 状态冲突，需要修正文档。
- 备份建立期间 background host/poll 协调、极端有限数值导致算术溢出等仅属后续验证方向；尚无复现证明，不计为 Bug。
- 根代理全量 analyze/test/integration 状态待汇总；本代理完成的 targeted 26/26 不能代替本 Round 的全套 Gate。
