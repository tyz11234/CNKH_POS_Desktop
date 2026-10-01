# F01–F11 修复与本轮验证

基线：Mobile e77b54686b0dd3a6af2c045643c31b22fac61e21；Desktop 29bba6f61ee8257b5a510199fb38350fee74a78b。开始时已通过远端 main 检查确认一致；原工作区干净，修改位于独立分支 fix/20261001-eleven-regressions。两仓库没有适用 AGENTS.md。已读取 README、FIX_VERIFICATION、相关业务代码及 CI 配套说明。

## 行为、位置和回归

| 编号 | 复核根因及修复 | 回归入口 |
| --- | --- | --- |
| F01 | 确认首次 product_upsert 只 ACK，不返回身份，销售空 SKU 无法解析。Desktop lan_product_identity.dart 与 lan_mutations.dart 在事务保存不可重绑别名和可重放 ACK；lan_pairing_host.dart 返回可选 entity_mappings。Mobile lan_sync.dart 接收确认后先持久化映射，再继续队列；旧 ACK 也有唯一 SKU/条码解析。销售保存条码快照。歧义拒绝并保留操作。 | integration/test/eleven_bug_entries_test.dart：未配对销售、空 SKU、已有 Desktop 商品、丢失和重复 ACK、重复同步、不唯一旧条码 |
| F02 | 确认自然键候选包含已删除/已映射旧实体。Mobile _upsertProduct 只选择活动且未关联其他 Desktop 实体的候选；tombstone 只按身份处理。rememberEntityId 双向禁止重绑。 | 同一 HTTP 文件：增量、全量、重复拉取、历史销售/进货/流水及未 ACK 进货保留 |
| F03 | 确认 OAuth 后认领不再检查销售状态。认领事务重新核对销售；sale_reversal.dart 的共享入口调用 sale_submission_guard.dart，让本地与 LAN 作废参与同一 SQLite 一致性规则。作废先提交则不发送税务请求；认领先提交则拒绝处理中/未知结果的作废。保留 UUID、尝试和审计，不在事务等待网络。 | test/einvoice_test.dart：挂起模拟 OAuth 后本地/LAN 作废、认领后两种作废、重复提交与 UUID/审计保留；全部税务响应受控模拟 |
| F04 | 确认初始库存差额被写成后续活动。catalog_stock_baseline.dart 依据完整 Desktop 流水和本机已确认进货数量证明初始基线；基线单独保留，真实后续流水仍拦截撤销，包括销售后作废的净零活动。缺少证明则继续保守拒绝。 | HTTP 实际 PurchaseOcrRepository.reversePurchase：相同/不同基线、重复撤销、认领后 Desktop 活动导致拒绝、原请求/后续队列/最终库存一致 |
| F05 | 确认 purge/clear 按扩展名删除用户目录全部 PDF。两端 e_receipt.dart 使用隔离子目录；owned_receipt_cache.dart 只删除有准确归属记录且内容 SHA-256 相符的文件。未知旧文件、改过内容、链接和子目录保留。 | 两端 test/receipt_cache_ownership_test.dart 通过公开 purge/clear/count 入口验证大小写、过期/新缓存、无关/旧/子目录 PDF 和重复执行；仅临时目录 |
| F06 | 确认 parser 生成全局重复 ocr-line-index。行 ID 由草稿 ID 长度、草稿 ID 和行位置组成，跨草稿唯一，同草稿稳定；旧 ID 不重写。 | Mobile test/ocr_draft_identity_regression_test.dart：真实 parser→prepareDraft→saveDraft，两份同格式、重复保存/重开、已提交后新建、旧草稿升级及附件/记忆/提交键保留 |
| F07 | 确认 matcher 事务前 upsertProduct。matcher 只建立稳定业务意图；createPurchase 的同一事务创建商品、分配号码、读取权威执行前成本、修改库存成本、写进货/流水/队列。相同意图重试复用 ID，改变内容拒绝；重复行共用原始成本。 | Desktop test/purchase_matcher_atomic_regression_test.dart：resolve→commit，成本在预览后变化、重复行、注入中途失败、新商品回滚、重试、真实撤销、后来成本及无快照旧记录 |
| F08 | 确认保护仅统计 ADMIN。UserAdminService 统计活动 ADMIN 与有效 PBKDF2 凭据的交集。AuthService 规范化账号并验证凭据结构，取消 PIN 不生成默认凭据或开启首次设置。 | test/admin_pin_cancel_entry_test.dart 实际创建页面取消 PIN；user_admin_service_test.dart 拒绝停用/降级、异常凭据、大小写和正常第二管理员实际登录 |
| F09 | 确认 UTF-16 单元直接写字节。两端 esc_pos_receipt.dart 使用自带中文字形生成 GS v 0 分段栅格；bluetooth_printer.dart 保持现有打印入口并采用传输适配器。支持 384/576 dots，设置 bt_printer_width_dots 默认 384。 | 两端 test/bluetooth_receipt_output_test.dart 实际 tryPrintSale（模拟传输），中文/英文/数字/换行/长名称、宽度和全部字节范围；实体打印机未验收 |
| F10 | 确认重置清空序列但保留税务文档。Desktop reset 保留 document_sequence 设置；document_numbers.dart 同时从所有环境/尝试的税务号码取上界，兼容旧序列缺失。税务防重及 UUID/日志保留。 | test/factory_reset_tax_numbers_test.dart：当天多次重置、不同环境/纠错尝试、旧版本/丢失序列、重新生成发票，不向税务发送 |
| F11 | 确认 UI 缓存系统现金且重新取日期。两端 daily_closing.dart 在一个事务按确定日期计算并保存；页面保存已加载业务日期，防重复点击；缓存仅用于显示。保留现金销售、现金定金、作废排除规则。 | 两端 test/daily_closing_entry_regression_test.dart 实际页面、加载后新销售/作废/现金定金、跨午夜、重复点击、事务并发与公共 save 入口；HTTP 双端现金/作废/定金 |

## 兼容性和迁移

数据库版本仍为 v10，没有重建业务表或改写历史实体。新 LAN 身份 ACK 和基线证明记录使用现有 settings 表，在业务事务中写入并随备份保存；旧数据保持原样。OCR 新 ID 只影响新解析结果，旧草稿/附件/别名/提交幂等键保留。旧库升级和重复 ensure 回归包含在完整测试中。

有未 ACK 旧商品业务时，目录覆盖继续受到保护；旧目标已删除的业务明确报错且保留，不能自动关联到同码新商品。需要人工核对业务，不能清空队列来使测试通过。

旧缓存设置被解释为缓存父目录，在 cnkh_receipts_owned_v2 子目录写入新缓存；无可靠归属的旧 PDF 不自动搬移或删除。已提交或结果未知税务文档保留原始号码、UUID、payload 和审计。

## 本轮命令和结果

**执行中：此段尚不能视为测试通过。** 完成后记录本轮两端精确源码、analyze 的 errors/warnings/infos、完整 flutter test、Desktop/integration 的 flutter test test regression，以及 APK/Windows Release 构建。

本机最初没有 Flutter/Dart。已实际尝试从官方 Git 仓库安装 Flutter stable；SDK 下载后启动进程被自动审批拒绝，因为它尝试访问未经授权的云实例元数据服务。本轮不再通过该进程执行网络请求，采用仓库现有 GitHub Actions 的 Ubuntu/Windows 环境执行实际 Flutter/HTTP/Release 命令。历史 CI 与 Python/SQLite 场景模拟均未计入本轮通过。

## 未验收范围

未执行 Android/Windows 真机覆盖升级、用户实体旧库、门店网络/防火墙/断线、电池与相机 OCR、WhatsApp 原生分享、实体蓝牙打印机（GS v 0 支持与物理宽度）、真实 MyInvois Sandbox/Production、真实企业证书与 Portal 操作。SQLite 旧库回归是隔离测试数据库，不代表门店旧库验收。HTTP 使用 localhost，税务 HTTP 全部受控模拟。未合并 main 或发布安装包。

排除的分类联动没有改动。快速挂单、恢复期间 LAN 写入等待验证风险不作为这 11 项修复的依据；没有用未经复现的新风险推动重构。
