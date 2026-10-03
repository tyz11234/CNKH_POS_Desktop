<!-- CNKH_AUDIT_CYCLE_2_BEGIN -->
# Feature Inventory — Audit Cycle 2 当前范围

本周期已完成 **1/10 轮**完整 Audit；已确认 **9 组**可复现产品/构建培训/发布流程缺陷；最后连续 **0 轮 Clean**。

当前功能分组 **42**（Shared 19 / Mobile 10 / Desktop 13）；**36/42** 有直接自动测试映射，**6/42** 保留目标设备/真实服务边界。本周期 PASS 只引用已完成轮次，未完成轮次不计为 Clean。

详细缺陷、每轮来源 hash / 命令 / 时间戳与域报告：[`AUDIT_CYCLE_2.md`](AUDIT_CYCLE_2.md)。

Mobile lib/screens/services/db/widgets：69/18/29/6/7；Desktop：74/17/36/6/6。Desktop 运行表 **26**（含 Host 的 `lan_sync_changes` / `lan_sync_mobile_sales`），纠正历史清单的 24 表口径；Mobile 26 表。schema v10、LAN v1 保持。

<!-- CNKH_AUDIT_CYCLE_2_END -->

> 以下为 Audit Cycle 1 历史记录；当前周期状态以上方 Cycle 2 为准。

# Feature Inventory — Audit Cycle 1, Round 6

审核基线：Mobile `c73e5f515b7a8179c6d82efef3ac2fd139b5d4a7` / Desktop `cec6ae88ea1baa4580063eaa7cf48aeb33fce2bc`，起始版本 `1.10.8+36`；Round 6 与 Final Release Regression 验证合并候选 `1.10.9+37`，SQLite schema v10。Round 6 完成后 Mobile/ Desktop 源码分别合并为 `b121cd40019213273fd7d47db5cf1f93549bab7e` / `bd75dfc381b8be4aa791a42524a40a291e692f1c`。六轮重扫确认 42 个功能组、69/74 个 Dart 源文件、26/24 张运行表；lifecycle、权限、输入、MyInvois、构建和发布流程的功能入口与主要测试映射均已检查。Feature group 依当前 `lib/`、路由入口、设置读写、数据库 schema、LAN host/client 和测试目录归并；新增正式功能应加入本表与 [`FEATURE_TEST_MATRIX.md`](FEATURE_TEST_MATRIX.md)。

## 扫描范围

| 仓库 | Dart 源文件 | Screens | Services | DB modules | Widgets | 自动化入口 |
|---|---:|---:|---:|---:|---:|---|
| Mobile | 69 | 18 | 29 | 6 | 7 | `test/` 48 个文件；`tool/` 2 个测试；Mobile CI、配对回归、布局验证 |
| Desktop | 74 | 17 | 36 | 6 | 6 | `test/` 47 个文件；`integration/test/` 2 个、`integration/regression/` 1 个；Windows Release、配对回归、培训验证 |

Mobile 页面入口由 `main.dart`、`screens/login_screen.dart`、`cart_screen.dart`、`checkout_screen.dart`、`sales_list_screen.dart`、`sale_receipt_detail_screen.dart`、`settings_screen.dart`、`training_page.dart`、`barcode_scan_screen.dart`、`qr_capture_screen.dart`、`einvoice_status_screen.dart` 及 `screens/admin/` 中的管理页组成；后者包括管理 Hub、商品、实体资料、进货 OCR / 历史、增强进货与供应商别名页面。Desktop 页面还包括 `desktop_shell.dart`、管理员 Hub、商品/实体/用户管理、进货新增/详情、备份恢复与 e-Invoice 设置页。

## Shared Feature Inventory — 19 组

| ID | 正式功能 | 主要实现位置 |
|---|---|---|
| S01 | 启动、初始化、Admin / Staff 登录、PIN 与权限门控 | `main.dart`, `services/auth_service.dart`, `models/app_user.dart` |
| S02 | POS 商品查询、分类、加购、数量、行/整单折扣、购物车状态 | `screens/cart_screen.dart`, `models/cart_item.dart`, `services/pos_repository.dart` |
| S03 | 结账、现金/卡/DuitNow QR/赊账、舍入、找零、重复提交保护 | `screens/checkout_screen.dart`, `widgets/cash_change_dialog.dart`, `services/held_cart_coordinator.dart` |
| S04 | 挂单、恢复、超时、唯一单号与非空购物车保护 | `services/pos_repository.dart`, `services/document_numbers.dart`, `services/held_cart_coordinator.dart` |
| S05 | 销售历史/详情、收据引用、作废/撤销、库存反向流水 | `screens/sales_list_screen.dart`, `screens/sale_receipt_detail_screen.dart`, `services/sale_reversal.dart` |
| S06 | 商品 CRUD、SKU/条码唯一性、搜索、排序、分页、软删除 | `screens/admin/products_admin.dart`, `services/pos_repository.dart` |
| S07 | 分类增改、启停、同步 | `services/pos_repository.dart`, `services/lan_sync.dart` |
| S08 | 客户 CRUD、查询分页、销售历史关联与同步 | `screens/admin/entities_page.dart` / `entities_admin_page.dart`, `services/pos_repository.dart` |
| S09 | 供应商 CRUD、查询分页、别名/重建映射与同步 | `screens/admin/entities_page.dart` / `entities_admin_page.dart`, `services/purchase_ocr_repository.dart` |
| S10 | 库存策略、盘点、库存流水、销售扣减/作废恢复、跨端库存权威规则 | `services/pos_repository.dart`, `services/catalog_stock_baseline.dart`, `services/lan_sync.dart` |
| S11 | 手动进货、成本快照、库存入账、撤销安全与历史 | `services/pos_repository.dart`, `services/purchase_reverse_plan.dart`, `services/sale_reversal.dart` |
| S12 | 日结、现金存入/提取、日期归属与报表金额 | `services/daily_closing.dart`, 管理 Hub |
| S13 | 小票模板、80 mm PDF、分页/CJK、缓存所有权、电子收据与分享 | `services/receipt_template.dart`, `services/e_receipt.dart`, `services/owned_receipt_cache.dart`, `widgets/receipt_preview_pane.dart` |
| S14 | 条码生成/扫描入口、标签渲染、打印队列与重复请求处理 | `services/barcode_labels.dart`, `services/bluetooth_printer.dart`, `screens/barcode_scan_screen.dart` |
| S15 | 店名/地址/收据/二维码/扫描反馈/库存与打印设置 | `screens/settings_screen.dart`, `services/receipt_template.dart`, `services/scan_feedback.dart` |
| S16 | `cnkh-sync:v1` 配对身份、认证、HTTP 对账、WebSocket 事件与旧客户端能力协商 | `services/lan_sync.dart`, `services/sync_role.dart` |
| S17 | 离线 Outbox、操作顺序、ACK/重试、幂等、冲突保留与游标恢复 | `services/sync_store.dart`, `services/lan_sync.dart`, `db/legacy_purchase_outbox_migration.dart` |
| S18 | e-Invoice 状态按销售/环境同步；Desktop 为执行方，Mobile 为镜像端 | Mobile `services/einvoice/einvoice_status_store.dart`; Desktop `services/einvoice/` |
| S19 | SQLite schema v10、约束/索引/触发器、事务、审计、凭据与旧库升级 | `db/app_database.dart`, `db/reliability_schema.dart`, `db/ocr_purchase_schema.dart`, e-Invoice schema/migration files |

## Mobile Feature Inventory — 10 组

| ID | Mobile 专属/偏重功能 | 主要实现位置 |
|---|---|---|
| M01 | Android 相机条码扫描、QR 配对读取、扫描反馈与权限回退 | `screens/barcode_scan_screen.dart`, `screens/qr_capture_screen.dart`, `services/scan_feedback.dart` |
| M02 | Android 本地 ML Kit 票据 OCR，原图与预览图分开保存 | `services/ocr_service.dart`, `services/purchase_invoice_image_store.dart` |
| M03 | OCR 草稿、行匹配/别名、单位换算、人工校验、原子入库 | `screens/admin/purchase_ocr_screen.dart`, `services/purchase_invoice_parser.dart`, `services/product_match_service.dart`, `services/purchase_validation_service.dart`, `services/purchase_ocr_repository.dart` |
| M04 | Mobile 进货历史拉取、独立附件 Outbox、断线重试与撤销同步 | `screens/admin/desktop_purchase_history_page.dart`, `services/purchase_history_sync.dart`, `services/purchase_reverse_sync.dart` |
| M05 | 配对客户端 Token 轮替、Host 隔离、首次连接与断线重连 | `services/lan_sync.dart`, `services/product_image_sync_queue.dart` |
| M06 | 无网销售/作废/资料与进货待办持久化，首次配对先上传 | `services/pos_repository.dart`, `services/sync_store.dart`, `db/legacy_purchase_outbox_migration.dart` |
| M07 | e-Invoice 状态只读页与同步错误提示 | `screens/einvoice_status_screen.dart`, `services/einvoice/einvoice_status_store.dart` |
| M08 | 按 Desktop Host 隔离的商品图像缓存、队列、重试/取消 | `services/product_images.dart`, `services/product_image_sync_queue.dart` |
| M09 | 手机蓝牙热敏打印设置与 ESC/POS 输出 | `services/bluetooth_printer.dart`, `services/esc_pos_receipt.dart` |
| M10 | 手机小屏/大字 POS 布局与员工培训页 | `screens/`, `screens/training_page.dart`, `tool/training_capture_test.dart`, `tool/training_view_test.dart` |

## Desktop Feature Inventory — 13 组

| ID | Desktop 专属/偏重功能 | 主要实现位置 |
|---|---|---|
| D01 | 权威 LAN HTTP/WebSocket Host、事件轮询、Token 撤销与操作 ACK | `services/lan_pairing_host.dart`, `services/lan_mutations.dart` |
| D02 | LAN 主机监听生命周期、DB polling 暂停/排空与恢复协调 | `services/desktop_database_maintenance.dart`, `desktop_shell.dart` |
| D03 | 员工 Admin/Staff CRUD、PIN/锁定、停用与最后管理员保护 | `screens/admin/user_admin_page.dart`, `services/user_admin_service.dart`, `services/auth_service.dart` |
| D04 | Desktop 进货新建/编辑/详情、OCR 导入、供应商选择与撤销审计 | `screens/admin/purchase_create_screen.dart`, `purchase_detail_page.dart`, `services/purchase_edit_service.dart`, `services/purchase_invoice_ocr.dart` |
| D05 | `.cnkhbackup` 数据库+图片备份、校验、恢复、暂存与回滚 | `screens/admin/backup_restore_page.dart`, `services/desktop_backup.dart` |
| D06 | MyInvois 环境、公司/税务资料与加密凭据设置 | `screens/einvoice_setup_screen.dart`, `services/einvoice/einvoice_settings.dart` |
| D07 | PFX/P12 检查、数字签名、Invoice mapper、OAuth/API、提交/查询/取消与审计 | `services/einvoice/einvoice_signer.dart`, `invoice_mapper.dart`, `myinvois_client.dart`, `einvoice_service.dart` |
| D08 | Windows 分享/剪贴板失败回退与 Windows 运行时适配 | `windows/runner/whatsapp_share.*`, `test/windows_share_fallback_test.dart` |
| D09 | Windows LAN Host QR 与 USB/键盘式扫码设备入口 | `desktop_shell.dart`, `screens/admin/admin_hub.dart`, `screens/barcode_scan_screen.dart` |
| D10 | Desktop 商品/实体/库存/进货分页管理和利润计算 | `screens/admin/`, `services/profit_math.dart` |
| D11 | Windows 桌面收据/PDF 与热敏打印入口 | `services/esc_pos_receipt.dart`, `services/bluetooth_printer.dart`, receipt widgets |
| D12 | Windows Release 构建、运行时文件打包、ZIP 与资源检查 | `.github/workflows/windows-release.yml`, `tool/verify_training_bundle.py` |
| D13 | Desktop 员工培训实际画面生成及打包 | `tool/training_capture_test.dart`, `tool/training_view_test.dart`, `assets/training/` |

## 数据库、同步、API、设置与角色清单

- Mobile 和 Desktop 当前声明 schema `version: 10`。Mobile schema 扫描有 26 张运行表；`sync_outbox_v10` 是旧 Outbox 迁移的临时替换表。Desktop 有 24 张表。两端表定义分布在 `lib/db/`，另有历史列迁移、主键/唯一约束与索引；Mobile 4 个触发器、9 个索引，Desktop 8 个索引。测试覆盖 v7/v9 迁移、重复初始化、Outbox 保留和备份迁移路径。
- Mobile client 调用健康检查、商品/客户/供应商/分类/进货/销售/库存流水/电子发票读取、销售/突变/分类/条码队列/通知写入、图片读取与 WebSocket。Desktop host 还提供 `/api/v1/events/poll`。全部 Desktop LAN 请求用 `X-CNKH-Token` 或配对 WebSocket token 认证。
- 已发现的 Outbox mutation kinds：`product_upsert`、`customer_upsert`、`supplier_upsert`、`category_upsert`、`stocktake`、`sale_upload`、`sale_void`、`purchase`、`purchase_reverse`、`purchase_attachment`；条码标签使用独立 `barcode_queue` 幂等 endpoint。健康能力声明含 `mutations_v1`、`stable_ids`、`void_sales`、`cost_snapshot`、`suppliers_v1`、`product_images_v1`、`purchases_v1`、`barcode_queue_idempotency`、`einvoice_status_v1`、`stock_moves_v1`、`mutation_rejections_v1`。
- 角色枚举为 `ADMIN` / `STAFF`（Dart `AppRole.admin` / `AppRole.staff`）。Desktop 后端限制员工维护、e-Invoice 和用户管理；Mobile 设置中的收款 QR 编辑限制 Admin，角色权限还有专门回归测试。
- 可修改设置包括 LAN Host/token/name 与同步游标、库存策略/低库存阈值、挂单超时、商品图同步、扫描反馈、Bluetooth 打印机地址/纸宽/启用、店铺资料和收据显示字段、电子收据目录；Desktop 另有加密保存的 Sandbox/Production e-Invoice 凭据/证书。

## 构建与发布面

Mobile：`.github/workflows/mobile-ci.yml`（pub get、analyze、全量 test、固定 Desktop 截图、APK 签名/版本/权限/资源核验与 Release）；`pair-regression.yml`；`layout-validation.yml`。Desktop：`windows-release.yml`（analyze、全量 test、截图、Windows build/ZIP/资源检查）；`pair-regression.yml`；`training-validation.yml`。双端集成包在 `CNKH_POS_Desktop/integration/`，使用本地 sibling source path，含两份 POS pairing HTTP 测试和 offline cancel 回归。

本地 Linux 环境可执行 Dart/Flutter、SQLite FFI、localhost HTTP 和 ZIP 校验，但没有 Android SDK / Windows host。GitHub Actions 已从审核源码完成 Windows 1.10.9+37 Release build 与 ZIP 发布；Mobile 最新可下载 APK 仍为 1.10.7+35，因无法验证匹配签名而没有发布新 APK。

版本显示新增依赖 `package_info_plus 8.3.1`：Android 使用应用包元数据接口；Windows/Linux 使用 Dart 平台实现。其读取版本/Build Number，不要求新增应用权限，不调用外部服务；方法通道由测试 mock 验证。Windows 原生构建与包资源校验已由 GitHub Actions 执行；Mobile APK 的正式签名兼容仍是发布阻塞。
