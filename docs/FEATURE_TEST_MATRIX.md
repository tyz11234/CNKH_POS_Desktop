<!-- CNKH_AUDIT_CYCLE_2_BEGIN -->
# Feature Test Matrix — Audit Cycle 2 当前结果

本周期已完成 **1/10 轮**完整 Audit；已确认 **9 组**可复现产品/构建培训/发布流程缺陷；最后连续 **0 轮 Clean**。

当前功能分组 **42**（Shared 19 / Mobile 10 / Desktop 13）；**36/42** 有直接自动测试映射，**6/42** 保留目标设备/真实服务边界。本周期 PASS 只引用已完成轮次，未完成轮次不计为 Clean。

详细缺陷、每轮来源 hash / 命令 / 时间戳与域报告：[`AUDIT_CYCLE_2.md`](AUDIT_CYCLE_2.md)。

新增永久映射：S03 金额/客户电话；S05 作废错误及日期边界；S06/M08 商品图片草稿；D04 采购异价行；D01 非法 LAN 金额；S15 QR 文件导入；M10/D13 培训来源/内容；D12 与 Android workflow 不可变 Release/tag Gate。具体测试名与证据见当前周期报告。

未完成轮次、正式 Mobile 同签名安装、Windows GUI/实体打印、真实门店 LAN 和 MyInvois 不记 PASS。Cycle 1 下表是历史结果，当前结论以上方已完成轮次为准。

<!-- CNKH_AUDIT_CYCLE_2_END -->

> 以下为 Audit Cycle 1 历史记录；当前周期状态以上方 Cycle 2 为准。

# Feature Test Matrix — Audit Cycle 1

审计基线：Mobile `c73e5f515b7a8179c6d82efef3ac2fd139b5d4a7` / Desktop `cec6ae88ea1baa4580063eaa7cf48aeb33fce2bc`；版本 `1.10.9+37`，schema v10。源代码合并 SHA：Mobile `b121cd40019213273fd7d47db5cf1f93549bab7e`，Desktop `bd75dfc381b8be4aa791a42524a40a291e692f1c`。库存、同步、数据库和权限范围见 [`FEATURE_INVENTORY.md`](FEATURE_INVENTORY.md)。

## Audit Round 记录

| Round | 新发现可复现产品 Bug | 处理 | 双端全量测试 | 跨端集成 | 结论 |
|---|---:|---|---|---|---|
| 1 | 3 | 修复 About 版本来源、Mobile 图片保存异步异常、旧配对 CI SHA，并添加回归测试 | Mobile 147/147；Desktop 151/151 | 29/29 | 修复后通过 |
| 2 | 0 | 完整功能、数据库、权限、同步与打包复查 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 3 | 0 | schema v10、迁移、约束、Outbox、恢复与回滚 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 4 | 0 | LAN v1 认证、payload、ACK/重试、重复投递和配对兼容 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 5 | 0 | lifecycle、权限、凭据、MyInvois、输入边界和完整功能复查 | Mobile 147/147；Desktop 151/151 | 29/29 | Clean |
| 6 | 0 | Windows supplier regression 等待异步 repository/dropdown 状态；全功能 Final Regression | Mobile 147/147；Desktop 151/151 | 29/29 | Clean；目标 Windows 测试通过 |

Round 5、6 是最后连续两轮 Clean。Round 6 的 Windows CI 曾暴露 supplier 选择测试使用固定延时的问题；修正测试同步逻辑后，目标测试 2/2 及完整 Desktop suite 151/151 通过，没有发现产品缺陷。六轮均覆盖双端分析、全量测试、跨端回归、数据库/API/权限与构建发布检查。

## Final Release Regression — 1.10.9+37

| 检查 | 结果 | 证据 / 边界 |
|---|---|---|
| Mobile analyze / 全量测试 | PASS | 0 errors；147/147；主线 CI [37129727944](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727944) |
| Desktop analyze / 全量测试 | PASS | 0 errors；151/151；Windows Release [37130267034](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130267034) |
| 固定配对 SHA 的跨端 integration | PASS | localhost HTTP/WebSocket、离线与重试 29/29；[run 37129727823](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727823) |
| Mobile / Desktop 截图与显示资源 | PASS | Mobile 主线 CI 和 Desktop 培训 run [37130266986](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130266986) |
| 版本一致性 | PASS | 两端 pubspec `1.10.9+37`；About 读取 package Version/Build；Windows EXE 资源含 `1.10.9+37` |
| Mobile PR Release build | PASS (validation only) | [run 37128270811](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37128270811) 用 PR 临时证书构建；不是正式签名或可发布 APK |
| Mobile 1.10.9+37 APK / tag | BLOCKED | 最新 1.10.7+35 APK 使用 Android Debug 证书，SHA-256 `51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`；没有已验证的匹配私钥，故未创建新 APK/Release |
| Desktop Release | PASS / PUBLISHED | tag `v1.10.9`；[Release](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v1.10.9)；Windows Release run [37130267034](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130267034) |
| Windows ZIP 重新下载校验 | PASS | 17,516,801 bytes；SHA-256 `5b02d3ce4eb00e57796dc5fd3360d48d6acb1abcb493d2fbed6d23d39848870f`；ZIP、EXE、Flutter runtime、data、11 组培训 PNG/JSON 通过 |
| 当前 Mobile APK 完整性 | PASS | v1.10.7-mobile，115,187,111 bytes，SHA-256 `ba6e763059eebcee46ef8d55962546f92e3f4332391da82fedc81fb204e6e3ad`；只代表旧包 |
| 实体设备 / MyInvois | PARTIAL | 未运行 Android 实体升级、Windows GUI/打印机、门店 Wi-Fi、真实 MyInvois sandbox/production |

本轮功能矩阵覆盖 **42 组**（Shared 19、Mobile 10、Desktop 13）：**36/42** 有直接自动回归通过；**6/42** 仍需实体设备、真实服务或 Windows GUI 启动验收。Mobile APK 签名限制与 Windows 实体启动边界均单独记录，不将 PR 临时签名 APK 当作正式产物。

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
| D12 | Windows EXE Release build、runtime 文件、ZIP 和资源检查 | Windows Release run 37130267034 构建；重新下载 ZIP、checksum、EXE/DLL/runtime/data 通过 | PARTIAL：Linux 无法启动 Windows GUI，需目标电脑首启验收 |
| D13 | Desktop 培训画面、PNG/JSON 元数据及 Windows 包资源 | run 37130266986 截图/视图验证通过；正式 ZIP 含 11 组 PNG/JSON，bundle verifier 通过 | PASS：发布包资源检查由 Windows runner 完成 |

## 未完成端到端项

| Feature | Reason | Blocked by | 已完成静态/自动检查 | Required follow-up |
|---|---|---|---|---|
| M01 | 相机权限授予/拒绝、相机画面对焦、真实 QR 与条码输入不能由 Linux widget test 代替 | 无 Android SDK/设备/相机 | 检查页面权限失败回退、手动搜索入口与扫描反馈；协议解析/配对服务有自动测试 | 在支持的 Android 设备运行授权、拒绝、重开设置与扫码测试 |
| S16 | localhost HTTP/WebSocket 并不覆盖跨 Wi-Fi、Windows 防火墙、IP 改变和真实断线 | 无两台真实设备/门店 LAN | 29 个双端 localhost integration cases + token/auth/retry tests | 在同一 Wi-Fi 实测断网/重连、Host 地址变化、过期 Token 与重启 |
| S18 / D07 | Sandbox/Production 法定提交、证书信任、Portal 状态及真实取消不可用模拟服务代替 | 未提供外部税务凭据和授权测试证书 | 固定 HTTP 服务覆盖 OAuth、签名、拒绝、超时、未知结果和纠错；不发送真实税务提交 | 有凭据后在 Sandbox 验证；独立核验签名与官方要求后再 Production |
| D11 | 真实 USB/Bluetooth 打印、纸宽、切纸与驱动行为未接入硬件 | 无 Windows 打印机/驱动 | ESC/POS 文本/栅格字节与通道错误测试 | Windows 实机分别验收 58/80mm 和 Bluetooth 输出 |
| D12 | Windows package 首次启动和交互 | Windows Release build、ZIP 和内容校验通过 | 在目标 Windows 桌面会话启动一次，验证首次运行 |
| Android Release / install upgrade | 新 APK 的签名无法验证为与当前包一致，故未发布；旧包仍可下载 | 当前 1.10.7+35 APK SHA-256 / ZIP 完整性及 Debug 证书指纹 `51d08c3a…` 已验证；PR Release APK 使用临时证书，不能代替正式包 | 恢复或验证匹配旧 APK 的签名私钥后，再构建、签名、覆盖升级并检查本地数据保留 |

完整通过数按上表功能行计算：**36/42** 为直接自动回归通过，**6/42** 为部分或目标平台/外部端到端阻塞。Windows Release build 已通过并重新下载验证；没有执行 Mobile 签名兼容 APK、实体 Android 升级、Windows GUI 首启、门店网络、实体打印或 MyInvois 真实提交。
