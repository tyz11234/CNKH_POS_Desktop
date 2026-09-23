# CNKH POS MyInvois 交付与验证报告

日期：2026-09-14。版本：Desktop **0.4.0+9**；Mobile **1.10.0+28**。

> **2026-09-23 源码补充：**本报告记录的上一轮 e-Invoice 版本尚未实现数字签名。当前 `main` 源码版本两端统一为 **1.10.3+31**；Desktop 已增加 PFX/P12 导入、加密保存及 Invoice 1.1 签名，Mobile 业务代码未改动。Desktop 和 Mobile CI、Windows/APK 构建及双端联调均已通过；真实 MyInvois Sandbox/Production 提交尚未执行。

## 实现结果

- Desktop 独立模块负责设置、凭据加密、销售快照映射、OAuth、提交、查询、取消及历史记录。
- MyInvois 发票不会写回原 sales 金额或销售明细。原收银、商品、库存页面没有变更；只在原 Settings 增加入口，并更新原培训页面。
- Mobile 保留离线销售和原 LAN 业务同步；仅通过已认证的电脑接口镜像发票状态，不调用 MyInvois，也不持有税务凭据。
- 管理员显式生成、预览、确认并提交。Submitted 仅表示接收；Validated 以服务器查询结果为准。超时或未知结果锁定重提，须核对官方 UUID。
- 原右上角和 Settings 培训入口提供 11 课。图片由生产 Flutter 控件在隔离测试数据库中实际渲染；箭头指向截图中真实控件。Windows 包含 11 组截图/坐标，APK 包含 12 组，电脑操作课程使用配套 Desktop 源码截图。

## 数据库变化

| 端 | 迁移 | 表及用途 |
| --- | --- | --- |
| Desktop | v8 → v9；新安装和旧库升级调用同一幂等 helper | e_invoice_settings：公司资料和加密凭据；e_invoice_documents：冻结发票、哈希、环境和状态；e_invoice_logs：操作审计 |
| Mobile | v8 → v9；更早版本继续原迁移后创建新表 | e_invoice_status：按电脑地址、文档及环境隔离的状态镜像 |

Desktop 为原 scaffold 增补 profile_json / credentials_cipher，以及文档的环境、payload、哈希、买方快照、更新时间等字段；保留旧提交与日志。原 sales、products、customers、suppliers 数据不被 e-Invoice 迁移改写。原业务表的早期版本升级逻辑保留。

Client ID 和 Secret 使用 AES-256-GCM；密文在数据库，密钥在 OS 安全存储，Token 仅在内存。旧 scaffold 的明文凭据升级时清空，需要重新输入。换电脑、Windows 用户或丢失密钥后也须重新输入；数据库备份不导出密钥。历史备份可能包含旧明文，需按敏感资料保管。

## 测试结果

| 验证项 | 结果与记录 |
| --- | --- |
| Desktop 全部单元/组件测试 | **100 通过**；[Windows CI](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34866162888) |
| Mobile 全部单元/组件测试 | **87 通过**；[Android CI](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34866240333) |
| 双端实际 HTTP 联调 | **10 通过**；[组合回归](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34866240327) |
| 截图生成和图片/箭头组件 | 两端通过；[快速截图检查](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34866155073) |
| 最终二进制培训资源 | Windows 11 组、APK 12 组；由上述构建任务逐项核验 |

以上是合并前的验证记录。正式发布工作流在 main 上再次运行测试和构建，通过后才上传成品。

覆盖范围：

- Desktop：新建数据库、v8 升级、原业务行保留、旧 scaffold 兼容、加密保存/读取、环境隔离和密钥丢失。
- Mapper：原销售快照不变，行折扣/整单折扣/舍入/含税金额一致；缺少买方资料或总额不一致时拒绝生成。
- API：模拟 OAuth 缓存、过期刷新、401、成功提交、服务失败、Retry-After、禁止凭据重定向、重复提交保护、未知结果跨重启锁定、查询和取消。
- Mobile：离线保存及 Outbox、电脑/环境状态隔离、异常快照保留旧结果。
- 实际 localhost HTTP：原离线操作顺序、重连和幂等回归，加上 Pending → Submitted / Validated / Rejected 回传，以及电脑来源销售在手机上的关联。
- UI 培训：生成真实页面截图，校验目标控件和字体；新进程加载打包图片并绘制箭头；最终成品逐项检查 PNG、尺寸、箭头坐标及与捕获源文件的字节一致性。

Windows 的原 205 笔销售回归首次超过默认 30 秒。仅该测试改为两分钟，保留逐笔真实数据库写入、销售数量与单号唯一性断言。静态分析使用项目原有 --no-fatal-infos / --no-fatal-warnings；没有编译错误，仍有非阻断 lint 提示。

## Build 与下载

| 成品 | 构建结果 | 发布地址 |
| --- | --- | --- |
| Windows x64 | flutter build windows --release 成功；[构建记录](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34866162888) | [Desktop v0.4.0](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.4.0) |
| Android APK | flutter build apk --release 成功；联网权限和培训资源检查通过；[构建记录](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34866240333) | [Mobile v1.10.0](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.0-mobile) |

发布工作流在测试和构建通过后上传成品及 SHA256SUMS.txt。Windows ZIP 是完整便携程序包，需保留 DLL 和 data 文件夹，不含安装向导。APK 两个文件名指向相同内容。

## 已知范围与未执行验收

1. 未持有店主 MyInvois 授权凭据；**没有实际 Sandbox 或 Production 税务提交**。模拟 HTTP 成功不代表 LHDNM 已验证真实发票。
2. 当前支持国内 MYR 普通 Invoice 1.0、整单统一税种/税率/商品分类。混合税率、汇总发票、贷项/退款票及 1.1 数字签章不在本版范围，使用 MyInvois Portal。
3. 查询/取消以官方结果为准；POS 作废、支付退款和税务取消是各自的操作。已验证发票的调整应按官方规则处理。
4. 状态在 Desktop 查询后随正常 LAN 同步回手机；目前按分页拉取完整状态快照，未做大规模历史数据压力测试。
5. 未执行实体 Windows/Android 安装升级、打印机、门店 Wi-Fi 或原生 OS 密钥存储真机验收。
6. APK 沿用项目现有 debug 签名。若与旧包签名不同，不能覆盖安装；先完成同步和备份，不应直接卸载带有未同步销售的版本。
7. 从源码启动前须先运行截图捕获流程；成品已包含培训图片。Mobile 构建固定配套 Desktop 源码，避免临时功能分支删除导致构建失败。

## 修改文件列表

以下为相对各仓库 main 基线的本次修改；历史 bugfix 已在上一版发布，不在此重复计入。

### Desktop（27 个文件）

```text
.github/workflows/pair-regression.yml
.github/workflows/training-validation.yml
.github/workflows/windows-release.yml
EINVOICE_REPORT.md
README.md
RELEASE_NOTES.md
assets/training/README.txt
integration/regression/offline_cancel_test.dart
lib/db/app_database.dart
lib/db/einvoice_migration.dart
lib/db/einvoice_schema.dart
lib/screens/einvoice_setup_screen.dart
lib/screens/settings_screen.dart
lib/screens/training_page.dart
lib/services/einvoice/einvoice_service.dart
lib/services/einvoice/einvoice_settings.dart
lib/services/einvoice/invoice_mapper.dart
lib/services/einvoice/myinvois_client.dart
lib/services/lan_pairing_host.dart
pubspec.lock
pubspec.yaml
test/desktop_ocr_migration_test.dart
test/einvoice_test.dart
test/reliability_test.dart
tool/training_capture_test.dart
tool/training_view_test.dart
tool/verify_training_bundle.py
```

### Mobile（20 个文件）

```text
.github/workflows/mobile-ci.yml
.github/workflows/pair-regression.yml
.gitignore
EINVOICE_REPORT.md
README.md
RELEASE_NOTES.md
assets/training/README.txt
lib/db/app_database.dart
lib/db/einvoice_status_schema.dart
lib/screens/einvoice_status_screen.dart
lib/screens/settings_screen.dart
lib/screens/training_page.dart
lib/services/einvoice/einvoice_status_store.dart
lib/services/lan_sync.dart
pubspec.yaml
test/database_migration_test.dart
test/einvoice_status_test.dart
tool/training_capture_test.dart
tool/training_view_test.dart
tool/verify_training_bundle.py
```

官方实现依据和完整配置步骤见 [README.md](README.md)；发布说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。
