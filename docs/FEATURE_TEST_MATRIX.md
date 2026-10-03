# Feature Test Matrix — Audit Cycle 1

Audit Round 1–5 基线：Mobile `c73e5f515b7a8179c6d82efef3ac2fd139b5d4a7` / Desktop `cec6ae88ea1baa4580063eaa7cf48aeb33fce2bc`，两端版本 `1.10.8+36`。发布候选版本统一为 `1.10.9+37`，Final Release Regression 已执行。库存、同步、数据库和权限范围见 [`FEATURE_INVENTORY.md`](FEATURE_INVENTORY.md)。

## Audit Round 记录

| Round | 新发现可复现 Bug | 处理 | 双端全量测试 | 跨端集成 | 结论 |
|---|---:|---|---|---|---|
| 1 | 3 | 修复 About 版本来源、Mobile 图片保存异步异常处理、两仓库配对 CI 旧 commit 引用，并添加回归测试 | Mobile 147/147；Desktop 151/151 | 29/29 | 修复后通过 |
| 2 | 0 | 无代码变更 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 3 | 0 | 无代码变更 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 4 | 0 | LAN v1 认证、payload、Outbox ACK/重试、重复投递和配对引用复查 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 5 | 0 | Flutter lifecycle、角色权限、敏感凭据、MyInvois API/重试、输入边界和完整功能复查 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |

Round 1–5 均运行双端 analyze、全量单元/widget/regression、跨端集成 analyze/HTTP 回归和培训截图/显示验证。两端 analyze 均为 0 errors；Mobile 有 41 条、Desktop 有 46 条非致命 info/warning。Round 4 与 Round 5 的当前 Mobile/Desktop 培训截图、固定 Desktop 培训截图捕获，以及双端培训视图测试均通过。Round 5 后达到“至少 5 轮、最后连续 2 轮 Clean”；之后又在候选版执行 Final Release Regression。

## 本轮运行结果

| 检查 | 结果 | 证据 / 边界 |
|---|---|---|
| Mobile analyze | PASS | `flutter analyze --no-fatal-infos --no-fatal-warnings`，0 errors；41 条 info/warning 非致命诊断 |
| Desktop analyze | PASS | 同 CI 命令，0 errors；46 条 info/warning 非致命诊断 |
| Mobile unit/widget/regression | PASS | `flutter test`，147 项通过 |
| Desktop unit/widget/regression | PASS | `flutter test`，151 项通过 |
| Desktop ↔ Mobile integration analyze | PASS | `integration/` 同 CI 命令，无 issues |
| Desktop ↔ Mobile HTTP integration | PASS | `integration/test regression`，29 项通过，真实 localhost HTTP / WebSocket 与重试流程 |
| Mobile training capture + view | PASS | 当前 Mobile 11 张实际页面截图生成；资源/箭头测试通过 |
| Desktop training capture + view | PASS | 当前 Desktop 11 张实际页面截图生成；视图/箭头测试通过 |
| 固定 Desktop 截图源 | PASS | 工作流 SHA `02e3574b16d45bf0e13f89f5f1d1b42f50bfa3f3` 的测试、pubspec、字体文件与归档内容 SHA 一致；截图生成通过 |
| 已发布 APK 完整性 | PASS | 下载后 SHA-256、ZIP 容器和 12 组培训 PNG/JSON 尺寸及箭头坐标有效；它是 1.10.7+35，不与当前 1.10.8 源码逐字节比较 |
| 已发布 Windows ZIP 完整性 | PASS | 下载后 SHA-256、ZIP 校验、EXE/DLL/runtime/字体/培训文件存在；本机 Linux 截图像素与 Windows Release 像素不同，无法用 `verify_training_bundle.py` 做逐字节源码比较 |
| 当前 Mobile Release build | BLOCKED | 无 Android SDK；同一旧 Debug 签名私钥也不在仓库，不能发布可覆盖安装 APK |
| 当前 Windows Release build | BLOCKED | Flutter Windows 构建只支持 Windows host；当前执行器为 Debian Linux |

本轮功能矩阵共 **42 组**：Shared 19、Mobile 10、Desktop 13。源文件/入口/测试映射已为 42/42 组建立；35/42 组有本地自动回归并通过；7/42 组的完整实体设备、生产服务或目标平台验收受限，详见下表和“未完成端到端项”。这不是“所有真实设备操作已验收”的结论。

## Final Release Regression — 1.10.9+37 候选

| 检查 | 结果 | 证据 / 边界 |
|---|---|---|
| Mobile analyze / 全量测试 | PASS | 0 errors，41 条非致命 info/warning；147/147 测试通过 |
| Desktop analyze / 全量测试 | PASS | 0 errors，46 条非致命 info/warning；151/151 测试通过 |
| 跨端集成 analyze / HTTP 回归 | PASS | analyze 无 issues；localhost HTTP/WebSocket、离线与重试 29/29 通过 |
| 当前 Mobile 截图捕获 / 显示 | PASS | 11 个 Mobile 页面截图生成；资源/箭头 view test 通过 |
| 当前 Desktop 截图捕获 / 显示 | PASS | 11 个 Desktop 页面截图生成；view test 通过 |
| 固定 Desktop CI 截图源 | PASS | 工作流锁定 SHA `02e3574b16d45bf0e13f89f5f1d1b42f50bfa3f3` 捕获通过；5 组配套资源进入 Mobile 验证 |
| 版本一致性 | PASS | 两端 pubspec 为 `1.10.9+37`；Android 版本读取 Flutter versionCode/versionName，Windows runner 读取 Flutter 版本宏；About 元数据回归通过 |
| Mobile Release APK | BLOCKED | `flutter build apk --release` 因无 Android SDK 失败；匹配当前 Debug APK 的签名私钥也不在仓库 |
| Windows Release 包 | BLOCKED | `flutter build windows --release` 被 Linux host 限制拒绝 |
| 已下载历史发布资产 | PASS | Mobile `v1.10.7-mobile` 115,187,111 bytes，SHA-256 `ba6e763059eebcee46ef8d55962546f92e3f4332391da82fedc81fb204e6e3ad`；Desktop `v1.10.8` 17,511,169 bytes，SHA-256 `f114693cb0633b6ab46a0d5e7ae32885be4bcc0780971c3ce8fe603fc3fc73c6`。只代表既有包完整性，不是候选产物 |
| GitHub push / tag / Release | BLOCKED | `gh auth status` 显示当前注入 token 无效；未提交、推送或发布候选版 |

Final Release Regression 的自动化部分与版本检查通过；完整 Release 仍因 Android SDK/签名密钥、Windows 构建 host 和 GitHub 写权限未满足而阻塞。

## Shared Feature Inventory / Regression

| ID | 功能 | Mobile 自动化 | Desktop 自动化 | 状态 |
|---|---|---|---|---|
| S01 | 启动、登录、Admin/Staff 权限、PIN 与锁定 | `widget_test`, `reliability_test`, `credit_rules_test` | `widget_test`, `admin_pin_cancel_entry_test`, `user_admin_service_test` | PASS |
| S02 | POS 商品查询、购物车与小屏滚动 | `widget_test`, `mobile_layout_test` | `widget_test`, `desktop_pagination_test` | PASS |
| S03 | 折扣、支付、舍入、找零、客户电话与提交防重 | `money_discount_test`, `checkout_customer_phone_test`, `checkout_resume_safety_test` | 同名回归 + `credit_rules_test` | PASS |
| S04 | 挂单/恢复、唯一单号、非空购物车与重复消费保护 | `held_cart_coordinator_test`, `document_numbers_test` | 同名回归 | PASS |
| S05 | 销售历史/详情、作废、退款库存与日结销售归属 | `reliability_test`, `sale_void_review_http_test`, `daily_closing_entry_regression_test` | 同名回归 + `sale_identity_sync_test` | PASS |
| S06 | 商品 CRUD、条码优先级、排序、分页、软删除/防复活 | `product_edit_safety_test`, `product_delete_sync_test`, `pagination_repository_test` | `product_edit_safety_test`, `product_delete_conflict_test`, `desktop_pagination_test` | PASS |
| S07 | 分类 CRUD、全量/增量目录同步 | `entity_crud_sync_test`, `full_catalog_reconcile_test` | `lan_host_sync_safety_test`, `pos_pair_test.dart` | PASS |
| S08 | 客户 CRUD、历史关联、删除重建身份 | `entity_crud_sync_test`, `recreated_customer_supplier_sync_test` | 同名回归 + `sale_identity_sync_test` | PASS |
| S09 | 供应商 CRUD、字段同步、删除重建与稳定选择 | `entity_crud_sync_test`, `recreated_customer_supplier_sync_test` | `purchase_supplier_selection_test`, `purchase_edit_service_test` | PASS |
| S10 | 盘点/库存流水、销售作废库存恢复、基线安全 | `stock_move_sync_test`, `receipt_stock_reference_test`, `reliability_test` | `product_edit_safety_test`, `ocr_purchase_sync_test`, `pos_pair_test.dart` | PASS |
| S11 | 手动/OCR 进货入库、成本快照与安全撤销 | `purchase_ocr_test`, `purchase_manual_cost_snapshot_test`, `purchase_reverse_safety_regression_test` | `purchase_edit_service_test`, `purchase_matcher_atomic_regression_test`, `ocr_purchase_sync_test` | PASS |
| S12 | 日结、存款/取款与跨午夜交易归属 | `daily_closing_entry_regression_test` | 同名回归 | PASS |
| S13 | 收据格式、长中文 PDF、缓存清理、电子收据与打印输出 | `e_receipt_test`, `receipt_pdf_render_test`, `receipt_cache_ownership_test`, `bluetooth_receipt_output_test` | 同名回归 + `windows_share_fallback_test` | PASS |
| S14 | EAN-13/Code128 标签、队列幂等 | `barcode_labels_test` | `barcode_labels_test`, `barcode_queue_idempotency_test` | PASS |
| S15 | 收据/QR/扫描设置与清理入口 | `receipt_cache_settings_entry_test`, `widget_test`, `credit_rules_test` | `receipt_cache_settings_entry_test`, `widget_test` | PASS |
| S16 | LAN v1 Host/client、认证、HTTP 对账、WebSocket、断线与 ACK 重试 | `offline_pairing_outbox_test`, `pairing_token_rotation_test`, `full_catalog_reconcile_test` | `lan_host_sync_safety_test`, `lan_pairing_host_test`, `pairing_token_rotation_test` | PARTIAL：localhost 集成通过；未做真实门店 Wi-Fi/防火墙验收 |
| S17 | Outbox 顺序、持久 ACK/重试、幂等与待办冲突保留 | `offline_cancel_upload_test`, `purchase_attachment_outbox_test`, `clear_demo_outbox_guard_test` | `ocr_purchase_sync_test`, `sale_identity_sync_test`, `sale_void_review_http_test` | PASS |
| S18 | e-Invoice 最新状态镜像与旧状态兼容 | `einvoice_status_test` | `einvoice_test` | PARTIAL：模拟 HTTP 覆盖通过；未连接真实 MyInvois |
| S19 | SQLite schema v10、migration、备份库升级、transaction/回滚 | `database_migration_test`, `reliability_test` | `desktop_ocr_migration_test`, `desktop_backup_validation_regression_test`, `desktop_database_maintenance_test` | PASS |

## Mobile Feature Inventory / Regression

| ID | 功能 | 自动化证据 | 状态 |
|---|---|---|---|
| M01 | 相机扫码/QR、Android 权限与手动回退 | 静态检查 `barcode_scan_screen.dart`, `qr_capture_screen.dart`; 配对协议另由 S16 覆盖 | PARTIAL：未运行 Android 设备或相机权限流程 |
| M02 | 本机 ML Kit OCR 与原图/预览文件生命周期 | `purchase_ocr_test`, `purchase_ocr_image_lifecycle_test` | PASS |
| M03 | OCR 草稿、商品匹配、别名、单位/成本转换和人工校验 | `purchase_ocr_test`, `ocr_draft_identity_regression_test`, `purchase_validation_service` 的调用断言 | PASS |
| M04 | 进货历史、附件单独重试/下载、进货撤销同步 | `purchase_history_sync_test`, `purchase_attachment_full_sync_test`, `purchase_attachment_outbox_test`, `purchase_reverse_sync_test` | PASS |
| M05 | 配对客户端 Host 隔离、Token 轮替与自动重连 | `pairing_token_rotation_test`, `offline_pairing_outbox_test`, integration pairing cases | PASS |
| M06 | 离线销售/作废、首次配对待办上传与丢 ACK 重试 | `offline_cancel_upload_test`, `offline_pairing_outbox_test`, `clear_demo_outbox_guard_test`, integration regression | PASS |
| M07 | e-Invoice 状态页、过滤和同步错误显示 | `einvoice_status_test`, training capture | PASS |
| M08 | 商品图片本地文件保存、同步队列、重试/取消 | `product_image_store_test`, `product_image_retry_test` | PASS |
| M09 | Bluetooth ESC/POS 输出、中文图像收据 | `bluetooth_receipt_output_test` | PASS：MethodChannel/字节输出；实体打印机未验收 |
| M10 | 响应式布局、培训页面截图捕获与箭头 | `mobile_layout_test`, `tool/training_capture_test.dart`, `tool/training_view_test.dart` | PASS |

## Desktop Feature Inventory / Regression

| ID | 功能 | 自动化证据 | 状态 |
|---|---|---|---|
| D01 | LAN Host REST/WebSocket、Token 认证、事件/操作 ACK | `lan_host_sync_safety_test`, `lan_pairing_host_test`, `pos_pair_test.dart`, `eleven_bug_entries_test.dart` | PASS：本地 HTTP/WebSocket |
| D02 | 主机生命周期、DB polling 暂停/排空及恢复 | `desktop_database_maintenance_test`, `desktop_backup_test` | PASS |
| D03 | Desktop 员工 CRUD、PIN 重置、停用/最后 Admin 保护 | `user_admin_service_test`, `admin_pin_cancel_entry_test` | PASS |
| D04 | 进货建立/修改/选择供应商、OCR/撤销 | `purchase_invoice_test`, `purchase_edit_service_test`, `purchase_supplier_selection_test`, `purchase_matcher_atomic_regression_test`, `ocr_purchase_sync_test` | PASS |
| D05 | 数据+图片备份、验证、恢复、故障回滚与路径重定向 | `desktop_backup_test`, `desktop_backup_validation_regression_test` | PASS |
| D06 | e-Invoice 环境/凭据加密、证书保管与连接配置 | `einvoice_test` credential/settings/certificate cases, training capture | PASS：使用模拟证书/HTTP |
| D07 | MyInvois 签名、映射、OAuth、提交/查询/纠错/取消 | `einvoice_test` 覆盖固定 HTTP 服务和数学签名 | PARTIAL：无真实 Sandbox/Production 凭证、企业证书或 Portal |
| D08 | Windows 剪贴板失败后分享回退 | `windows_share_fallback_test` | PASS：平台通道 mock |
| D09 | Host 配对 QR、过期码与撤销后重新配对 | `lan_pairing_host_test`, `pairing_token_rotation_test`, integration pairing cases | PASS：解析/HTTP 模拟；未用真实扫码设备 |
| D10 | Desktop 管理商品/实体/库存/审计分页与排序 | `desktop_pagination_test`, `product_edit_safety_test`, `profit_math_test` | PASS |
| D11 | 桌面热敏打印设备连接和纸宽打印验收 | `bluetooth_receipt_output_test` 字节级/MethodChannel 断言 | PARTIAL：无真实 Windows/蓝牙打印硬件 |
| D12 | 当前源码 Windows EXE 构建、运行时打包及启动 | 已下载并检查正式 ZIP；`flutter build windows --release` 因 Linux host 拒绝 | PARTIAL：当前源码无法在该 OS 构建或启动 |
| D13 | Desktop 培训画面、图片/JSON 元数据与 Windows 包对照 | capture/view 测试通过；已发布 ZIP 文件与结构完整 | PARTIAL：Windows 渲染图与 Linux 重捕获不是逐字节相同，须在 Windows Release runner 核验 |

## 未完成端到端项

| Feature | Reason | Blocked by | 已完成静态/自动检查 | Required follow-up |
|---|---|---|---|---|
| M01 | 相机权限授予/拒绝、相机画面对焦、真实 QR 与条码输入不能由 Linux widget test 代替 | 无 Android SDK/设备/相机 | 检查页面权限失败回退、手动搜索入口与扫描反馈；协议解析/配对服务有自动测试 | 在支持的 Android 设备运行授权、拒绝、重开设置与扫码测试 |
| S16 | localhost HTTP/WebSocket 并不覆盖跨 Wi-Fi、Windows 防火墙、IP 改变和真实断线 | 无两台真实设备/门店 LAN | 29 个双端 localhost integration cases + token/auth/retry tests | 在同一 Wi-Fi 实测断网/重连、Host 地址变化、过期 Token 与重启 |
| S18 / D07 | Sandbox/Production 法定提交、证书信任、Portal 状态及真实取消不可用模拟服务代替 | 未提供外部税务凭据和授权测试证书 | 固定 HTTP 服务覆盖 OAuth、签名、拒绝、超时、未知结果和纠错；不发送真实税务提交 | 有凭据后在 Sandbox 验证；独立核验签名与官方要求后再 Production |
| D11 | 真实 USB/Bluetooth 打印、纸宽、切纸与驱动行为未接入硬件 | 无 Windows 打印机/驱动 | ESC/POS 文本/栅格字节与通道错误测试 | Windows 实机分别验收 58/80mm 和 Bluetooth 输出 |
| D12 | 无法从当前环境产出或运行这一轮的 Windows 二进制；当前改动也未进入已发布 ZIP | Flutter Windows target 只支持 Windows host | 上一版 Release ZIP 下载、SHA、ZIP 完整性、EXE/DLL/assets presence 已检查 | 用 Windows Release workflow 从审核后的提交构建并启动验收 |
| D13 | Windows runner 产出的像素与 Linux renderer 不同，`verify_training_bundle.py` 的逐字节比较在 Linux 不适用 | 无 Windows runner 本地环境 | 当前两端截图生成/箭头 tests 通过；正式 ZIP 包含 11 组 desktop 培训图片 | Windows workflow 对本轮产物执行原有 bundle verifier |
| Android Release / install upgrade | APK 无法构建，且旧安装包 Debug 私钥无法从本仓库恢复 | 缺 Android SDK 与匹配签名 key | 旧 APK 下载 hash/ZIP 完整性/12 组图片与元数据结构通过；未冒充当前源码 APK | 找回签名 key 后用 Android CI 构建、签名、覆盖升级并核验数据保留 |

完整通过数按上表功能行计算：**35/42** 为直接自动回归通过，**7/42** 为部分或目标平台/外部端到端阻塞。已执行真实功能级 localhost HTTP 集成；没有执行当前源码 APK/Windows Release 构建、实体设备、真实门店网络、实体打印或 MyInvois 真实提交。
