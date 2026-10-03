<!-- CNKH_AUDIT_CYCLE_2_BEGIN -->
# Bug Audit — Audit Cycle 2 当前进度

本周期已完成 **1/10 轮**完整 Audit；已确认 **9 组**可复现产品/构建培训/发布流程缺陷；最后连续 **0 轮 Clean**。

当前功能分组 **42**（Shared 19 / Mobile 10 / Desktop 13）；**36/42** 有直接自动测试映射，**6/42** 保留目标设备/真实服务边界。本周期 PASS 只引用已完成轮次，未完成轮次不计为 Clean。

详细缺陷、每轮来源 hash / 命令 / 时间戳与域报告：[`AUDIT_CYCLE_2.md`](AUDIT_CYCLE_2.md)。

两项旧 Windows 测试同步故障单独记为测试修复，不计新产品 Bug；新候选 Windows CI 尚待实际运行结果。

<!-- CNKH_AUDIT_CYCLE_2_END -->

> 以下为 Audit Cycle 1 历史记录；当前周期状态以上方 Cycle 2 为准。

# Bug Audit — Audit Cycle 1

## 当前进度

- 审核基线：Mobile `c73e5f515b7a8179c6d82efef3ac2fd139b5d4a7`、Desktop `cec6ae88ea1baa4580063eaa7cf48aeb33fce2bc`；两端初始版本 `1.10.8+36`，本轮版本 `1.10.9+37`，SQLite schema v10。
- 完成 6 轮完整 Audit；Round 1 修复 3 个可复现问题，Round 2–6 未发现新的产品缺陷，Round 5 和 Round 6 连续 Clean。Round 6 加固 Windows 上供应商选择回归的异步状态等待。
- Mobile 源码合并 commit `b121cd40019213273fd7d47db5cf1f93549bab7e`；Desktop 源码合并 commit `bd75dfc381b8be4aa791a42524a40a291e692f1c`。Mobile/ Desktop 配对引用更新 commit 分别为 `47b415029b417c0823fbb8eb08b4b86a6e685c8b` / `a9ddbdb8f97cfaf3c82a65fc99ffdfd233171194`。
- Desktop `v1.10.9` Release 已发布并重新下载验证。Mobile 1.10.9+37 源码已合并，但 APK 未发布：旧 APK 使用 Android Debug 签名，本轮无法验证候选包使用相同签名。
- 功能清单涵盖 42 组：36 组自动回归通过，6 组仍需实体设备、真实服务或 Windows 交互启动验收，详见 `FEATURE_TEST_MATRIX.md`。

## 已确认问题

### B001 — About 版本与已安装应用元数据脱节

- **影响平台：** Mobile、Desktop。
- **发现 Round：** 1。
- **复现：** 更新 `pubspec.yaml` 版本后打开“设置 → 关于”；原实现读取 Dart 文件中的常量，发布包版本改变时仍会显示旧值。
- **根因：** 两端 `lib/app_release_notes.dart` 分别重复维护版本与 build number，和安装包 metadata 不同步。
- **修复：** 新增 `lib/app_version.dart`，以 `package_info_plus` 读取安装包 Version/Build Number；About 使用异步 metadata；移除重复常量并更新维护说明。
- **回归测试：** 两端 `test/app_version_test.dart` mock 已安装版本为 `9.8.7+42` 并断言显示值；同时检查 package 版本记录在 CHANGELOG。
- **修复 commit：** Mobile `b121cd40019213273fd7d47db5cf1f93549bab7e`；Desktop `bd75dfc381b8be4aa791a42524a40a291e692f1c`。
- **修复版本：** Desktop Windows `1.10.9+37` 已发布；Mobile 源码已合并，APK 因签名门槛未发布。
- **状态：** 单测、Windows 包元数据及 Desktop About 版本通过；Mobile 当前安装包仍为 `1.10.7+35`。

### B002 — Mobile 商品图片保存失败可能逃出异常处理

- **影响平台：** Mobile。
- **发现 Round：** 1。
- **复现：** 让商品图片目录创建或写入失败，再调用 `ProductImageStore.saveBase64`；原函数未等待异步 `saveBytes`，异步失败发生在 `try` 返回后，不会被本层 `catch` 捕获。
- **根因：** `saveBase64` 将 `Future` 直接返回，`try/catch` 只覆盖 Base64 解码和同步异常。
- **修复：** 在 `lib/services/product_images.dart` 对 `saveBytes` 使用 `await`，让文件系统错误进入既有恢复结果。
- **回归测试：** 两端新增 `test/product_image_store_test.dart`，用不可创建的输出目录验证返回安全失败结果；Mobile 原实现曾可复现测试失败。
- **修复 commit：** Mobile `b121cd40019213273fd7d47db5cf1f93549bab7e`。
- **修复版本：** `1.10.9+37` 源码已合并；APK 尚未发布。
- **状态：** 已修复并通过 Mobile 147/147 与主线 CI；改动尚未进入可下载 APK。

### B003 — 双仓库配对 CI 固定引用落后于当前主线

- **影响平台：** Mobile、Desktop 配对集成 CI。
- **发现 Round：** 1。
- **复现：** 将配对回归 workflow 配置的 sibling repository SHA 与当前主线比较；旧 SHA 落后，workflow 会检验旧跨端代码组合。
- **根因：** `.github/paired-desktop-ref` 和 `.github/paired-mobile-ref` 没随配对代码更新。
- **修复：** Mobile `.github/paired-desktop-ref` 指向 Desktop `bd75dfc381b8be4aa791a42524a40a291e692f1c`；Desktop `.github/paired-mobile-ref` 指向 Mobile `b121cd40019213273fd7d47db5cf1f93549bab7e`。
- **回归测试：** Desktop `integration/` 使用双端本地源码运行 29 项 HTTP/离线/重试集成；最新配对 SHA 的 integration run [37129727823](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727823) 成功。
- **修复 commit：** Mobile ref `47b415029b417c0823fbb8eb08b4b86a6e685c8b`；Desktop ref `a9ddbdb8f97cfaf3c82a65fc99ffdfd233171194`。
- **修复版本：** `1.10.9+37`。
- **状态：** 按新配对 SHA 的 HTTP integration 29/29 通过 [run 37129727823](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727823)。

## Audit Round 记录

| Round | 新发现可复现产品 Bug | 重点 | 结果 |
|---|---:|---|---|
| 1 | 3 | 版本元数据、Mobile 文件系统异步错误、配对 CI 引用 | 3 项已修复并新增回归测试 |
| 2 | 0 | 完整功能、数据库、权限、同步与打包复查 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 3 | 0 | schema v10、迁移、约束、Outbox、恢复与回滚 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 4 | 0 | LAN v1 认证、payload、ACK、断线重试、重复请求与跨端兼容 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 5 | 0 | lifecycle、角色权限、敏感凭据、MyInvois、输入边界和完整功能复查 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 6 | 0 | Windows runner 供应商选择回归计时、全功能 Final Regression 与版本检查 | Clean；修正测试等待逻辑后 Mobile 147/147、Desktop 151/151、集成 29/29 |

Round 5 和 Round 6 是最后连续两轮 Clean。每轮 analyze 均为 0 errors；Mobile 有 41 条、Desktop 有 46 条非致命 info/warning。Round 6 的 supplier 测试曾在 Windows PR run 暴露硬编码延时不稳定；已改为等待 repository 与 dropdown 状态，目标测试 2/2、完整 Windows suite 151/151 通过。该项是测试同步加固，没有发现新的产品缺陷。

## Final Release Regression 与发布结果

- Mobile analyze/全量测试：0 errors，147/147；主线 run [37129727944](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727944) 成功。
- Desktop analyze/全量测试：0 errors，151/151；Windows Release [37130267034](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130267034) 成功。
- 双端 integration analyze/HTTP：29/29；固定 Mobile→Desktop SHA 的 run [37129727823](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37129727823) 成功。
- Desktop 培训截图资源检查：[37130266986](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37130266986) 成功。
- Desktop Release tag：`v1.10.9`，资产 `CNKH_POS_Desktop-windows-x64-v1.10.9-37.zip`，17,516,801 bytes，SHA-256 `5b02d3ce4eb00e57796dc5fd3360d48d6acb1abcb493d2fbed6d23d39848870f`。公开下载后 checksum、ZIP 完整性、EXE、Flutter runtime、data 和 11 组培训 PNG/JSON 均通过；Windows GUI 未在本地 Linux 执行。
- 当前 Mobile APK `v1.10.7-mobile` 下载校验通过，115,187,111 bytes，SHA-256 `ba6e763059eebcee46ef8d55962546f92e3f4332391da82fedc81fb204e6e3ad`。签名是 Android Debug，证书 SHA-256 `51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`。本轮没有验证到可匹配的私钥，因此没有发布 Mobile APK / `v1.10.9-mobile`；候选包若签名不同会无法覆盖安装。
- Android 实体相机/升级、Windows 实体打印机、门店 Wi-Fi 与 MyInvois Sandbox/Production 未验收。README 已记录可下载版本、checksum 和 Mobile 签名限制。

Final Release Regression：PASS；Desktop Windows Release：PUBLISHED AND VERIFIED；Mobile APK：WITHHELD pending compatible signing key. Review evidence and feature-level boundaries are in `FEATURE_TEST_MATRIX.md`.
