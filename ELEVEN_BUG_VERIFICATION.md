# F01–F11 修复与本轮验证

基线：Mobile e77b54686b0dd3a6af2c045643c31b22fac61e21；Desktop 29bba6f61ee8257b5a510199fb38350fee74a78b。开始时已通过远端 main 检查确认一致；原工作区干净，修改位于独立分支 fix/20261001-eleven-regressions。两仓库没有适用 AGENTS.md。已读取 README、FIX_VERIFICATION、相关业务代码及 CI 配套说明。

## 2026-10-03 · 1.10.7+35 发布验证

两端修复 PR #18 已合并到 main，安装包与 SHA256SUMS 已发布。固定发布源码：Desktop `9b297535e8a0e3619efc995cbeb7d647ef63b586`（`v1.10.7`），Mobile `c0b0a67c62c417e3b7e54cfee5ff9d96c141a345`（`v1.10.7-mobile`）。发布只提高应用版本号，数据库仍为 schema v10，协议仍为 cnkh-sync:v1；没有删除税务记录、UUID、审计或未确认业务。

| 工作目录 | 本次实际命令 | 发布回归结果 | 运行证据 |
| --- | --- | --- | --- |
| Mobile | `flutter pub get`；`flutter analyze --no-fatal-infos --no-fatal-warnings` | 成功；0 errors / 5 warnings / 37 infos，退出 0 | [Mobile main 发布 CI](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37029961364) |
| Mobile | `flutter test` | 130 项通过 | 同上 |
| Mobile | `flutter build apk --release` | 成功；APK 签名、INTERNET 与培训资源验证通过 | 同上 |
| Desktop | `flutter pub get`；`flutter analyze --no-fatal-infos --no-fatal-warnings` | 成功；0 errors / 6 warnings / 38 infos，退出 0 | [Windows main 发布 CI](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37029953298) |
| Desktop | `flutter test` | 132 项通过 | 同上 |
| Desktop | `flutter build windows --release` | 成功；Windows x64，培训资源检查与 ZIP 上传通过 | 同上 |
| Desktop/integration | `flutter pub get`；`flutter analyze --no-fatal-infos --no-fatal-warnings`；`flutter test test regression` | 成功；0 / 0 / 0；29 项真实 HTTP 回归通过 | [新版 main 配套 HTTP](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37029961222) |
| 两端 | `flutter test tool/training_capture_test.dart`；`flutter test tool/training_view_test.dart` | 通过，培训捕获/显示各 1 项；Mobile 历史 Desktop 培训截图不计作本轮业务验证 | 对应发布 CI |
| Mobile | `python3 tool/verify_training_bundle.py build/app/outputs/flutter-apk/app-release.apk --kind mobile` | 16 组资源通过 | Mobile 发布 CI |
| Desktop | `python tool/verify_training_bundle.py build/windows/x64/runner/Release --kind desktop` | 11 组资源通过 | Windows 发布 CI |
| Mobile | `apksigner verify --print-certs <APK>`；`aapt dump permissions <APK>`；`sha256sum <APK>` | 签名有效，INTERNET 存在，哈希与 Release digest 一致 | Mobile 发布 CI |

HTTP 使用 Desktop `458b52a8300b37900d1e5557d5b35e7d57d4f202` + Mobile `c0b0a67c62c417e3b7e54cfee5ff9d96c141a345`；两端均为 1.10.7+35。发布版本的业务代码、测试、资源与这些受测源码一致，文档及 companion 固定值差异不改变业务实现。发布前另实际通过 [Desktop 1.10.7 HTTP #113](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37003545232) 与 [Mobile 1.10.7 HTTP #101](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37003549635)，各 29 项。Flutter stable 3.47.6，GitHub Actions Ubuntu/Windows runner；本地 SDK 限制与修复分支失败记录保留在下文，不把它们或历史绿色 CI 计为发布通过。

APK `ba6e763059eebcee46ef8d55962546f92e3f4332391da82fedc81fb204e6e3ad`（115187111 字节）；Windows ZIP `33818e0fe9e6a6141a790d842b909c023eca0dc528ccc42d2f17b3505d548c77`（17487790 字节）。两个版本化/通用 APK 资产内容相同。本次 APK 是 Release 构建，实际使用 **Android Debug 签名证书**；没有使用稳定发布 keystore。证书 SHA-256：`51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`。 **与 1.10.6 APK 的证书不同，不能直接覆盖安装该版本。** 更新前完成业务同步并备份，保留旧 APK 和未确认的离线操作；不要直接卸载含有未同步数据的旧版，卸载会清除本地数据。Android/Windows 实体覆盖升级尚未验收。

安装包下载与完整校验步骤见 [README](README.md)。以下为发布前修复分支的原始证据，PR 临时 APK、旧版本 artifact 与本次公开安装包不同。

## 行为、位置和回归

| 编号 | 复核根因及修复 | 回归入口 | 本轮回归结果 |
| --- | --- | --- | --- |
| F01 | 确认首次 product_upsert 只 ACK，不返回身份，销售空 SKU 无法解析。Desktop lan_product_identity.dart 与 lan_mutations.dart 在事务保存不可重绑别名和可重放 ACK；lan_pairing_host.dart 返回可选 entity_mappings。Mobile lan_sync.dart 接收确认后先持久化映射，再继续队列；旧客户端不需要新增字段，服务端也依据已建立别名或唯一 SKU/条码解析。销售保存条码快照；已解析的 Desktop ID 不再重复剥除 pc- 前缀（本轮 HTTP 在该类真实 ID 上发现了漏扣库存）。歧义拒绝并保留操作。 | integration/test/eleven_bug_entries_test.dart：未配对销售、空 SKU、已有 Desktop 商品、丢失和重复 ACK、重复同步、不唯一旧条码 | 通过：首次配对、旧 v1 请求、丢失/重复 ACK 的真实 HTTP；库存只扣一次 |
| F02 | 确认自然键候选包含已删除/已映射旧实体。Mobile _upsertProduct 只选择活动且未关联其他 Desktop 实体的候选；tombstone 只按身份处理。rememberEntityId 双向禁止重绑；销售回拉按原映射恢复本地 ID，包括已删除商品，保留历史实体。 | 同一 HTTP 文件：增量、全量、重复拉取、历史销售/进货/流水及未 ACK 进货保留 | 通过：增量/全量/重复拉取；历史 ID 不重绑，已删除目标的待同步请求明确拒绝并保留 |
| F03 | 确认 OAuth 后认领不再检查销售状态。认领事务重新核对销售；sale_reversal.dart 的共享入口调用 sale_submission_guard.dart，让本地与 LAN 作废参与同一 SQLite 一致性规则。作废先提交则不发送税务请求；认领先提交则拒绝处理中/未知结果的作废。保留 UUID、尝试和审计，不在事务等待网络。 | test/einvoice_test.dart：挂起模拟 OAuth 后本地/LAN 作废、认领后两种作废、重复提交与 UUID/审计保留；全部税务响应受控模拟 | 通过：本地及真实 LAN HTTP 作废、可控 OAuth/提交 HTTP；没有真实税务提交 |
| F04 | 确认初始库存差额被写成后续活动。catalog_stock_baseline.dart 依据完整 Desktop 流水和本机已确认进货数量证明初始基线；基线单独保留，真实后续流水仍拦截撤销，包括销售后作废的净零活动。缺少证明则继续保守拒绝。 | HTTP 实际 PurchaseOcrRepository.reversePurchase：相同/不同基线、重复撤销、认领后 Desktop 活动导致拒绝、原请求/后续队列/最终库存一致 | 通过：相同/不同基线的真实撤销、净零活动拒绝、原请求/后续队列和双端库存 |
| F05 | 确认 purge/clear 按扩展名删除用户目录全部 PDF。两端 e_receipt.dart 使用隔离子目录；owned_receipt_cache.dart 只删除有准确归属记录且内容 SHA-256 相符的文件。未知旧文件、改过内容、链接和子目录保留。 | 两端 test/receipt_cache_settings_entry_test.dart 经过真实 PDF 写入和设置页清空；test/receipt_cache_ownership_test.dart 通过公开 purge/clear/count 入口验证大小写、过期/新缓存、无关/旧/子目录 PDF 和重复执行；仅临时目录 | 通过：真实 PDF 写入与两个设置页清空；临时目录内无关文件保留 |
| F06 | 确认 parser 生成全局重复 ocr-line-index。行 ID 由草稿 ID 长度、草稿 ID 和行位置组成，跨草稿唯一，同草稿稳定；旧 ID 不重写。 | Mobile test/ocr_draft_identity_regression_test.dart：真实 parser→prepareDraft→saveDraft，两份同格式、重复保存/重开、已提交后新建、旧草稿升级及附件/记忆/提交键保留 | 通过：真实 parser/prepare/save/commit、重复保存/重开、新旧草稿保留 |
| F07 | 确认 matcher 事务前 upsertProduct。matcher 只建立稳定业务意图；createPurchase 的同一事务创建商品、分配号码、读取权威执行前成本、修改库存成本、写进货/流水/队列。相同意图重试复用 ID，改变内容拒绝；重复行共用原始成本。 | Desktop test/purchase_matcher_atomic_regression_test.dart：resolve→commit，成本在预览后变化、重复行、注入中途失败、新商品回滚、重试、真实撤销、后来成本及无快照旧记录 | 通过：真实 matcher、事务中途失败回滚、重复行/重试、撤销及旧快照限制 |
| F08 | 确认保护仅统计 ADMIN。UserAdminService 统计活动 ADMIN 与有效 PBKDF2 凭据的交集。AuthService 规范化账号并验证凭据结构，取消 PIN 不生成默认凭据或开启首次设置。 | test/admin_pin_cancel_entry_test.dart 实际创建页面取消 PIN；user_admin_service_test.dart 拒绝停用/降级、异常凭据、大小写、旧大小写凭据的锁定/PIN 重设和正常第二管理员实际登录 | 通过：实际页面取消 PIN，停用/降级保护及第二管理员实际登录 |
| F09 | 确认 UTF-16 单元直接写字节。两端 esc_pos_receipt.dart 以自带中文字形为首选字体生成 GS v 0 分段栅格；bluetooth_printer.dart 保持现有打印入口并采用传输适配器。支持 384/576 dots，设置 bt_printer_width_dots 默认 384。 | 两端 test/bluetooth_receipt_output_test.dart 实际 tryPrintSale（模拟传输），中文/英文/数字/换行/长名称、宽度和全部字节范围；实体打印机未验收，原生产适配器仍仅支持 Android，本轮未新增 Windows 蓝牙传输 | 通过：两端实际打印入口的自动化栅格输出；实体打印仍待验收 |
| F10 | 确认重置清空序列但保留税务文档。Desktop reset 保留 document_sequence 设置；document_numbers.dart 同时从所有环境/尝试的税务号码取上界，兼容旧序列缺失。税务防重及 UUID/日志保留。 | test/factory_reset_tax_numbers_test.dart：当天多次重置、不同环境/纠错尝试、旧版本/丢失序列、重新生成发票，不向税务发送 | 通过：多次当天重置、旧序列缺失、税务证据保留和新发票 prepare |
| F11 | 确认 UI 缓存系统现金且重新取日期。两端 daily_closing.dart 在一个事务按确定日期计算并保存；页面保存已加载业务日期，防重复点击；缓存仅用于显示。保留现金销售、现金定金、作废排除规则。 | 两端 test/daily_closing_entry_regression_test.dart 实际页面、加载后新销售/作废/现金定金、跨午夜、重复点击、事务并发与公共 save 入口；HTTP 双端现金/作废/定金 | 通过：两端 Widget/事务及真实 HTTP；日期、系统现金、重复点击和并发 |

## 兼容性和迁移

数据库版本仍为 v10，没有重建业务表或改写历史实体。新 LAN 身份 ACK 和基线证明记录使用现有 settings 表，在业务事务中写入并随备份保存；旧数据保持原样。ACK 的 entity_mappings 和请求 client_entity_id 都是可选字段，协议仍为 v1，旧端继续使用原来的响应/请求格式。首次配对修复应使用配套新版本；老客户端不发新字段的 HTTP 场景也已覆盖。OCR 新 ID 只影响新解析结果，旧草稿/附件/别名/提交幂等键保留。旧库升级和重复 ensure 回归包含在完整测试中。

有未 ACK 旧商品业务时，目录覆盖继续受到保护；旧目标已删除的业务明确报错且保留，不能自动关联到同码新商品。需要人工核对业务，不能清空队列来使测试通过。此时上传失败仍会保护目录游标，不能宣称这笔已删除目标的待同步业务已成功。

旧缓存设置被解释为缓存父目录，在 cnkh_receipts_owned_v2 子目录写入新缓存；无可靠归属的旧 PDF 不自动搬移或删除。已提交或结果未知税务文档保留原始号码、UUID、payload 和审计。新字体复用 Desktop 的 NotoSansSC-Regular.ttf，两端打包版权及 OFL 许可；字形优先使用该字体，自动化比较不同汉字输出以防默认字体方块掩盖问题。

## 修复分支命令和结果（发布前）

执行日期：2026-10-01 至 2026-10-02。两端继续保持 1.10.6+34、schema v10；main 在 2026-10-02 再次 fetch 后仍为上述基线。审查提交为 Desktop `1cae8372edd7597948ba8abe45a9cfaec1fcf20e`、Mobile `55dfae9ba78e817a9e29514b2e491ea9b30691f4`。交付前固定 companion SHA；后续验证文档提交不改变业务代码或测试内容。

本轮使用仓库既有 GitHub Actions，Flutter stable **3.47.6**（初轮 2026-10-01 为 3.47.5，下面最终证据来自 2026-10-02）；Desktop 为 Windows runner，Mobile 及配套 integration 为 Ubuntu runner。所有 Dart/Flutter 业务回归均在本轮修复分支实际执行，没有删除、跳过或削弱既有测试。CI 的非致命 warning/info 参数保持原样，成功退出不等于零告警。

| 工作目录 | 实际测试/构建命令 | 本轮结果 | 证据 |
| --- | --- | --- | --- |
| Mobile | `flutter analyze --no-fatal-infos --no-fatal-warnings` | **0 errors / 5 warnings / 37 infos**（42 issues），退出 0 | [Mobile CI #203](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36997981149) |
| Mobile | `flutter test` | **130 项通过**，退出 0 | 同上 |
| Mobile | `flutter build apk --release` | **成功**，APK 115.2 MB，退出 0 | 同上 |
| Desktop | `flutter analyze --no-fatal-infos --no-fatal-warnings` | **0 errors / 6 warnings / 38 infos**（44 issues），退出 0 | [Windows CI #167](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36997979170) |
| Desktop | `flutter test` | **132 项通过**，退出 0 | 同上 |
| Desktop | `flutter build windows --release` | **成功**，Windows x64 Release，退出 0 | 同上 |
| Desktop/integration，Mobile 工作流 | `flutter analyze --no-fatal-infos --no-fatal-warnings` | 0 errors / 0 warnings / 0 infos，No issues found | [Mobile HTTP #97](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36997981000) |
| Desktop/integration，Mobile 工作流 | `flutter test test regression` | **29 项通过**，包含 10 项新增入口回归和 19 项既有回归 | 同上，Desktop `1cae8372` + Mobile `55dfae9b` |
| Desktop/integration，Desktop 工作流 | 同样两条 analyze / `flutter test test regression` | 0 / 0 / 0；**29 项通过** | [Desktop HTTP #108](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36997979158) |
| 两端 | `flutter test tool/training_capture_test.dart`、`flutter test tool/training_view_test.dart` | 已通过；独立截图/箭头回归 | 对应上述 Mobile / Windows CI |
| Mobile | `python3 tool/verify_training_bundle.py build/app/outputs/flutter-apk/app-release.apk --kind mobile` | **16 组资源通过**；不代替业务回归 | Mobile CI |
| Desktop | `python tool/verify_training_bundle.py build/windows/x64/runner/Release --kind desktop` | **11 组资源通过**；不代替业务回归 | Windows CI |
| 两端本地 checkout | `git diff --check` | 通过 | 本轮工作区；不代替 Flutter 测试 |

上述各 Flutter 目录先实际执行 `flutter pub get`，均成功。Mobile 工作流沿用既有历史 Desktop 培训素材来源，该素材截图不计入本轮双端业务验证；本轮 HTTP 明确使用配套新源码，Mobile 工作流记录的是两端上述精确 HEAD，Desktop 工作流记录 Desktop PR merge checkout `2c237797a41a887257fff649bdee6801a0c790bb` + Mobile `55dfae9b`。根目录 Windows CI checkout 同一 Desktop merge SHA；Mobile CI checkout `fd63f41aab24f118bd9ae7e2228856c3cf58bb88`（Mobile HEAD `55dfae9b` 合并指定 main 的测试树），APK 身份步骤已实际记录该 SHA。

旧库与重复升级回归包括两端既有 `database_migration_test.dart` / `desktop_ocr_migration_test.dart`，以及新增 OCR 旧 ID 和税务序列缺失场景。验证 v7/v9 → v10、重复 schema ensure、销售/进货/附件/匹配记忆/提交键及未 ACK 队列保留。本次没有新表迁移，未以重绑或删除历史恢复同步。

### 本轮失败与修正记录

- [1.10.7 Windows PR #170](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37002158364)：131 项通过、1 项失败，F08 新建管理员页面固定等待 300 ms 后 PIN 弹窗尚未出现。测试改为从真实事件循环触发页面操作，有界等待真实 PIN 弹窗及保存提示；[下一轮 #171](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37002895369) 又发现弹窗期间页面忙碌动画使 pumpAndSettle 超时，改为有限帧渲染而不要求整个页面空闲。保留取消 PIN、停用/降级拒绝和实际登录断言。没有跳过或削弱测试，最终发布 CI 已完整重跑通过。

- [首轮 Desktop](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36865709206)、[首轮 Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36865713190)：编译/分析发现事务号码 executor、Desktop 缓存 repo 参数和测试数据库 setVersion 接口不一致。按真实入口补齐参数，并改用 SQLite `PRAGMA user_version` 旧版本夹具；没有跳过测试。
- [首轮可编译 HTTP](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36866242944)：25 项通过、3 项失败。实际复现 canonical Desktop ID 再次剥除 pc- 导致漏扣库存，以及销售回拉改写本地历史 ID。修正解析后 ID 的使用和回拉的不可重绑映射，现有库存和历史断言保持。
- [Mobile 输出测试首轮](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36866236311)：中文字库未打包；随后字体回退仍可能被 Flutter 测试默认字体的方块掩盖。两端把内置中文字库作为首选，保留“中”和“文”输出不同的断言。
- Desktop 新增管理员页面测试起初在虚拟时钟内初始化 FFI/PBKDF2 而超时；夹具移到真实 setUp/tearDown，页面取消 PIN 及实际登录断言保留，已通过。
- [Desktop 缓存页面](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36871318202)、[Mobile 缓存页面](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36871309108) 分别 131/129 项通过、1 项失败，文件检查后弹窗尚未出现。实际点击在 real async 区运行，并有界等待弹窗/删除提示；仍断言本应用 PDF 删除、用户合同保留、计数和提示正确。本轮最终两个完整测试均通过。

### 分析诊断

最终 errors/warnings/infos 的逐条位置与规则见 [ELEVEN_BUG_ANALYZE.md](ELEVEN_BUG_ANALYZE.md)。Desktop 44、Mobile 42 项实际诊断完整保留；没有通过 suppression 或删除文件清空告警。

### 发布前 Release 构建与签名

Mobile 最终 Release APK 已编译成功，115.2 MB；`apksigner verify --print-certs`、merged manifest 及 APK 内 INTERNET 权限检查都通过。本轮 APK SHA-256 为 `f1771a82a10123614666392bb2c33ad45c358c140a3bd8e8fd0f1791c8633309`；PR 验证证书 SHA-256 为 `a200798d10b01f246dc2efa136ea6e18553467dfae527b6ee0d1da209bb1a092`。该证书本轮生成、有效期两天，不能用于门店正式升级或作为稳定签名；没有发布正式 APK，既有工作流不上传 PR APK。正式发布/上传步骤按既有条件未执行，与跳过测试无关。

Windows x64 Release 已编译、资源校验、打包及 artifact 上传成功；[本轮 Windows artifact](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36997979170/artifacts/11222663296) 包含 `CNKH_POS_Desktop-windows-x64-v1.10.6-34.zip` 和 SHA256SUMS。内部应用 ZIP SHA-256：`c67375cc7ed8b69124e91439010f7710e939446535234592284eb4274ae30bc0`；GitHub 外层 artifact ZIP digest：`77f861234c2c7738fe4b245a6c8d03e713a128720a142f34533d1a230e3a7459`，两者不是同一个文件。该阶段没有创建 Release，README 当时仍指历史 1.10.6；最终发布见上文。

PR 审查入口：[Desktop #18](https://github.com/tyz11234/CNKH_POS_Desktop/pull/18)、[Mobile #18](https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/18)。当时保留独立审查分支、尚未发布；PR 现已合并，最终安装包见上文。

本机最初没有 Flutter/Dart。已实际尝试从官方 Git 仓库安装 Flutter stable；SDK 下载后实际尝试 `flutter-sdk/bin/flutter --version`；启动进程被自动审批拒绝，理由是它尝试访问未经授权的 link-local 云实例元数据服务，可能触及云凭据。版本探测没有成功，本机没有执行本轮 Flutter analyze/test/HTTP/Release 命令。本轮不再通过该进程执行网络请求，采用仓库现有 GitHub Actions 的 Ubuntu/Windows 环境执行实际 Flutter/HTTP/Release 命令。历史 CI 与 Python/SQLite 场景模拟均未计入本轮通过。

## 未验收范围

未执行 Android/Windows 真机覆盖升级、用户实体旧库、门店网络/防火墙/断线、电池与相机 OCR、WhatsApp 原生分享、实体蓝牙打印机（GS v 0 支持与物理宽度）、真实 MyInvois Sandbox/Production、真实企业证书与 Portal 操作。SQLite 旧库回归是隔离测试数据库，不代表门店旧库验收。HTTP 使用 localhost，税务 HTTP 全部受控模拟。安装包发布不扩大这些验收范围。

附带观察：F05 设置页回归中，Mobile 真实 PDF 写入仍产生既有的 `Courier has no Unicode support` 日志。缓存归属与删除结果已单独断言；该日志不作为 PDF 中文视觉验收通过，也没有借本轮重写 PDF 票据布局。

排除的分类联动没有改动。快速挂单、恢复期间 LAN 写入等待验证风险不作为这 11 项修复的依据；没有用未经复现的新风险推动重构。
