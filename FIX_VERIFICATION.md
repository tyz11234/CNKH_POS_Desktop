# CNKH POS 修复与验证记录（2026-10-01）

## 基线与工作区

- 已阅读两端 README.md、LAN_SYNC.md、相关可靠性/进货/e-Invoice/发布说明；仓库内未发现 AGENTS.md。
- 开始时两端工作区干净，没有覆盖、丢弃或重置用户改动。
- 获取并再次核对 origin/main：Mobile `481faeb89ccf2de8d97e395aa00d74f6960a82a3`；Desktop `82566126415fb69ae55b0542f66ee697a654b1e3`，仍为 1.10.5+33。
- 修复分支：Mobile `fix/offline-sync-stock-history`；Desktop `fix/einvoice-correction-stock-sync`。本次发布源码版本为 1.10.6+34 / schema v10；实际 PR CI 已通过，正式 Release 流程待完成。

## 逐项复核与改动

| 问题 | 最新 main 中的证据 | 本次代码处理 |
| --- | --- | --- |
| 1. 净库存为零的 Desktop 活动未被 Mobile 撤销检查发现 | Mobile `_upsertProduct` 只在 stock 不同时增加 desktop_catalog_sync，销售后作废可绕过该检查 | Desktop 增加可选 stock_moves_v1、按 SQLite 流水顺序导出的 /api/v1/stock-moves；Mobile 保留销售与作废两笔标记。配对手机撤销先入队，ACK 后才执行本机反向流水。明确的事务拒绝保留同一请求并继续同步；旧版已执行的本机撤销按流水核实后补偿一次，保留原流水及审计。未知结果保持顺序等待 ACK |
| 2. 未配对业务未入 Outbox | queueMutation 在 lan_sync_host 为空时直接返回；首次目录拉取可以覆盖已经在本地增加的数量 | 本机操作始终事务入队，先上传再应用目录。v10 升级恢复从未配对的旧进货、销售、作废和库存调整，按流水依赖保留顺序；新商品用业务前库存基线建档，避免库存与进货重复计入。已有 SKU/条码安全关联，其他字段冲突保留请求。Desktop 按业务进货 ID 校验重放，不重复加库存 |
| 3. 备份回退全量目录只 upsert | cursor 回退清空游标后仍未停用快照缺失商品 | 在同一目录事务中停用权威完整快照缺失的已映射商品/客户/供应商/分类；保留未映射本地资料。未确认本地业务会阻止覆盖。无 items、缺失/重复标识的响应不作为权威空快照。独立进货历史同步同样保护待 ACK 记录，并保留游标供重试 |
| 4. 手动进货没有成本快照 | createPurchase 保存调用方 lines_json，没有写 beforeCostCents | 在修改 products 前、同一事务中读取成本并写入每行快照；重复商品行使用同一进货前成本。旧记录缺少快照时不猜测成本，后续成本不同则保留。Desktop 撤销继续使用自己的 desktopBeforeCostCents；配对手机 ACK 后通过权威目录接收 Desktop 成本 |
| 5. 最终验证失败无法纠错 | _applyStatus 将 Invalid 写成 rejected，保留 UUID；prepare 与 UI 随后禁止生成 | 区分同步拒收 rejected 与最终 invalid。纠错建立带 parent_document_id 的独立提交尝试和新的发票号码，原 UUID/签名 payload/审计记录保留。同步拒收后创建新的重试记录。未知结果禁止重提，通过 Portal 的 UUID 与 Submission UID 调 Get Submission 核对。Details 仅用于已确认 Invalid 的验证错误；仅最新尝试允许生成/提交 |

保持 cnkh-sync:v1、现有 POS/LAN 架构、离线销售及收银/商品/库存页面布局。进货详情沿用现有撤销按钮、对话框与 SnackBar；设置页新增明确的 e-Invoice 纠错动作。

### 迁移和兼容边界

- Mobile schema v10：Outbox 增加 delivery_state；旧 entity_type 形状保留所有行、操作 ID、顺序及错误。仅旧 required entity_type 无默认值时复制为兼容表形状，保留该历史列；不执行删除操作触发附件 ACK。
- 旧数据只有在确认从未配对、业务数量与库存流水可以核实后自动重放。无法核实的旧记录保留为 needs_review，不猜测库存基线；已配对历史不盲目重放。
- Desktop schema v10：e_invoice_documents 增加 attempt_no、parent_document_id 和每销售/环境/尝试唯一索引；迁移不会在再次初始化时重排已有效的尝试。
- 老 Desktop 仍按 v1 同步普通业务；没有完整库存流水能力时，Mobile 明确提示升级 Desktop 后才能撤销。没有首次关联能力的旧实现若拒绝未配对请求，队列及本地数据保留。
- Mobile 状态镜像支持 Invalid；Desktop 对旧状态客户端继续返回其认识的 Rejected 表示，并只镜像最新尝试，完整提交历史仍保存在 Desktop。

## 已执行的回归用例

Mobile：
- `stock_move_sync_test.dart`：销售后作废净零库存、旧主机能力边界、库存游标回退、非确定结果的队列顺序。
- `purchase_reverse_sync_test.dart`：旧本机撤销被明确拒绝后的补偿、后续队列继续、重复拒绝的幂等与审计；独立历史拉取保护待确认业务及游标。
- `offline_pairing_outbox_test.dart`：配对前进货、首次同步失败、断网重试、不重复 POST。
- `full_catalog_reconcile_test.dart`：全量消失记录停用、本地资料和待同步业务保护、无效快照保护。
- `purchase_manual_cost_snapshot_test.dart`：手动进货重复行、库存/成本恢复、后续成本变化、旧记录无快照。
- `database_migration_test.dart`：v7/v9 → v10、旧 Outbox 行与新写入、业务顺序和系统时间回拨、基线与重复迁移。
- OCR 测试增加持久化成本快照断言，既有队列测试调整目录夹具。

Desktop：
- `test/einvoice_test.dart`：成功、同步拒收、Invalid、旧 Rejected+UUID、未知状态与超时、Portal 查询恢复、纠错与纠错拒收重试、原记录与审计、纠错重新生成保留父记录、旧 Pending 已有 Submission UID 的保护、重复迁移的尝试顺序。
- `test/desktop_ocr_migration_test.dart`：升级到 v10 保留原业务与待确认操作。
- `integration/test/pos_pair_test.dart`：实际双端 HTTP 的净零库存、入队后拒绝、丢失撤销 ACK、首次配对、v9 未配对升级、新/已有目录、重复 ACK、进货 ID 内容冲突、过期 SKU 不得重定向已映射商品、Desktop 执行成本、实际 .cnkhbackup 恢复后全量目录及待同步保护。
- `integration/regression/offline_cancel_test.dart`：新增 Invalid 状态镜像兼容断言。

完整双端 HTTP 命令同时覆盖 `integration/test` 与 `integration/regression`。两端 `pair-regression.yml` 读取 `.github/paired-*-ref`，允许手动指定 companion ref 并记录实际 SHA。最终业务代码组合：Mobile `30259b449bad3810a8babbc82c920dafd83cd053` + Desktop `69454048ead4e0a033aaff798200bcc0b811d4c4`，Desktop HTTP 工作流已实际验证此组合。后续发布文档及 companion ref 提交不改变业务代码。

## 实际执行结果

### GitHub Actions PR 回归与构建

| 工作目录 | 实际命令 | 结果与日志 |
| --- | --- | --- |
| Mobile | `flutter analyze --no-fatal-infos --no-fatal-warnings` | 成功，0 error、5 warnings、37 infos；[Mobile CI](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36785588879) |
| Mobile | `flutter test` | 124 项通过；同上 |
| Mobile | `flutter build apk --release` | 成功，APK 113.5 MB；PR 临时验证签名，不作为正式发布 APK；同上 |
| Desktop | `flutter analyze --no-fatal-infos --no-fatal-warnings` | 成功，0 error、6 warnings、38 infos；[Windows CI](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36785895779) |
| Desktop | `flutter test` | 116 项通过；同上 |
| Desktop | `flutter build windows --release` | 成功，Windows x64 ZIP 及培训资源检查通过；同上 |
| Desktop/integration | `flutter analyze --no-fatal-infos --no-fatal-warnings` | No issues found；[Desktop HTTP](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36785895856) / [Mobile HTTP](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36785589132) |
| Desktop/integration | `flutter test test regression` | 两端工作流各 19 项通过；Desktop 工作流使用最终业务代码组合 |
| 两端 | `flutter test tool/training_capture_test.dart`、`flutter test tool/training_view_test.dart`、`tool/verify_training_bundle.py` | 实际截图、箭头及打包资源检查通过 |
| 两端 | `git diff --check`、`git diff --cached --check` | 无空白错误；不替代 Flutter 回归 |

分析沿用既有 CI 的非致命 warning/info 参数，没有将其写成零告警结果。完整 Flutter 测试和双端 HTTP 均已实际执行，未把先前 SQLite 模拟计作 Flutter 回归。

### CI 首轮失败及修正

- Mobile 首轮 122 通过、2 失败：附件延期提示与既有断言不一致，以及新增 MockClient 响应默认 Latin-1 无法编码中文。恢复现有“仍待重试”提示，并让模拟 HTTP 明确采用 UTF-8 字节及 Content-Type；业务断言保留。重跑 124 项通过。
- Desktop 首轮 114 通过、2 失败：审计 JSON 的远端 `status` 覆盖本地 `unknown_status` / `identity_mismatch` 决策。修复 `_log` 字段写入顺序，单独保存 `remote_status`，同时保留审计决策；增加相关断言。重跑 116 项通过。
- 初次失败日志：[Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36785207393)、[Desktop](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36785209838)。未忽略失败或弱化业务断言。

### 原本地环境限制

本机为 Linux，没有 Flutter/Dart；以下七条命令均实际尝试并返回 127 `flutter: command not found`：Mobile 的 `flutter analyze` / `flutter test` / `flutter build apk --release`，Desktop 的 `flutter analyze` / `flutter test` / `flutter build windows --release`，以及 Desktop/integration 的 `flutter test test regression`。官方 SDK 清单普通请求超时、授权重试返回 404。此后通过 GitHub Actions 的 Ubuntu / Windows runner 实际完成上述分析、测试与构建；本机失败未记为通过。

## 推送、审查与发布

用户已明确授权推送、发布 APK 和电脑包，并更新 README。两端修复分支已上传，审查入口：[Mobile PR #17](https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/17)、[Desktop PR #17](https://github.com/tyz11234/CNKH_POS_Desktop/pull/17)。上传通过已连接的 GitHub 工具完成；本地 Git 没有写入凭据，没有覆盖原 main 或丢弃用户改动。

正式发布流程将合并已验证的业务代码与发布文档，在 main 再跑分析、完整测试、培训资源及 Release 构建，生成 `v1.10.6-mobile` APK 和 `v1.10.6` Windows ZIP；实际 Release 与资产校验值完成后更新此记录及两端 README。

## 尚未验证

未执行 Android / Windows 真机覆盖升级、实体 SQLite 数据库升级、门店 Wi-Fi / 防火墙 / 断线重连、打印机验收。双端 HTTP 使用 localhost，不代表门店网络测试。MyInvois 状态回归使用可控 HTTP 模拟，未调用真实 MyInvois Sandbox / Production 税务提交，也未验收真实企业证书及 Portal 操作。

## MyInvois 官方依据

- [Submit Documents](https://sdk.myinvois.hasil.gov.my/einvoicingapi/02-submit-documents/)
- [Get Submission](https://sdk.myinvois.hasil.gov.my/einvoicingapi/06-get-submission/)
- [Get Document Details](https://sdk.myinvois.hasil.gov.my/einvoicingapi/08-get-document-details/)
- [Cancel Document](https://sdk.myinvois.hasil.gov.my/einvoicingapi/03-cancel-document/)
- [Integration Practices](https://sdk.myinvois.hasil.gov.my/integration-practices/)
