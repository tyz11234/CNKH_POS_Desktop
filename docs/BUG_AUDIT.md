# Bug Audit — Audit Cycle 1

## 当前进度

- 审核基线：Mobile `c73e5f515b7a8179c6d82efef3ac2fd139b5d4a7`、Desktop `cec6ae88ea1baa4580063eaa7cf48aeb33fce2bc`；分支均为 `work`，开始时工作区干净，`origin/main` 与基线相同。
- Round 1–5 审计版本为两端 `1.10.8+36`；候选版本现已提升为 `1.10.9+37`；数据库 schema v10。
- Round 1 发现并修复 3 个可复现问题；Round 2、3、4、5 均为 Clean。候选版 Final Release Regression 的自动化回归与版本一致性检查通过；平台构建和发布仍受外部条件阻塞。
- 所有修复均在本地未提交；无 commit、tag、push 或 GitHub Release。
- 功能清单：42 组（Shared 19、Mobile 10、Desktop 13）；35 组自动回归通过，7 组受实体设备、生产服务或目标平台构建限制，详见 `FEATURE_TEST_MATRIX.md`。

## 已确认问题

### B001 — About 版本与已安装应用元数据脱节

- **影响平台：** Mobile、Desktop。
- **发现 Round：** 1。
- **复现：** 更新 `pubspec.yaml` 版本后打开“设置 → 关于”；原实现读取 Dart 文件中的常量，发布包版本改变时仍会显示旧值。
- **根因：** 两端 `lib/app_release_notes.dart` 分别重复维护版本与 build number，和安装包 metadata 不同步。
- **修复：** 新增 `lib/app_version.dart`，以 `package_info_plus` 读取安装包 Version/Build Number；About 使用异步 metadata；移除重复常量并更新维护说明。
- **回归测试：** 两端 `test/app_version_test.dart` mock 已安装版本为 `9.8.7+42` 并断言显示值；同时检查 package 版本记录在 CHANGELOG。
- **修复 commit：** 未提交。
- **修复版本：** `1.10.9+37` 候选，尚未发布。
- **状态：** 已修复并通过；需在可构建的下一版正式安装包上确认实际 UI。

### B002 — Mobile 商品图片保存失败可能逃出异常处理

- **影响平台：** Mobile。
- **发现 Round：** 1。
- **复现：** 让商品图片目录创建或写入失败，再调用 `ProductImageStore.saveBase64`；原函数未等待异步 `saveBytes`，异步失败发生在 `try` 返回后，不会被本层 `catch` 捕获。
- **根因：** `saveBase64` 将 `Future` 直接返回，`try/catch` 只覆盖 Base64 解码和同步异常。
- **修复：** 在 `lib/services/product_images.dart` 对 `saveBytes` 使用 `await`，让文件系统错误进入既有恢复结果。
- **回归测试：** 两端新增 `test/product_image_store_test.dart`，用不可创建的输出目录验证返回安全失败结果；Mobile 原实现曾可复现测试失败。
- **修复 commit：** 未提交。
- **修复版本：** `1.10.9+37` 候选，尚未发布。
- **状态：** 已修复并通过。

### B003 — 双仓库配对 CI 固定引用落后于当前主线

- **影响平台：** Mobile、Desktop 配对集成 CI。
- **发现 Round：** 1。
- **复现：** 将配对回归 workflow 配置的 sibling repository SHA 与当前主线比较；旧 SHA 落后，workflow 会检验旧跨端代码组合。
- **根因：** `.github/paired-desktop-ref` 和 `.github/paired-mobile-ref` 没随配对代码更新。
- **修复：** Mobile 引用 Desktop `cec6ae88ea1baa4580063eaa7cf48aeb33fce2bc`；Desktop 引用 Mobile `c73e5f515b7a8179c6d82efef3ac2fd139b5d4a7`。Round 4 再次确认两引用对应各自 `origin/main`。
- **回归测试：** Desktop `integration/` 使用双端本地源码运行 29 项 HTTP/离线/重试集成；最近 GitHub 配对集成 run `37114494494` 成功。
- **修复 commit：** 未提交。
- **修复版本：** `1.10.9+37` 候选，尚未发布；不涉及 About 显示。
- **状态：** 已修复并通过。

## Audit Round 记录

| Round | 新发现可复现 Bug | 重点 | 结果 |
|---|---:|---|---|
| 1 | 3 | 版本元数据、文件系统异步错误、配对 CI 引用 | 3 项已修复，新增回归测试；双端全量测试及集成测试通过 |
| 2 | 0 | 完整功能、数据库、权限、同步与打包复查 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 3 | 0 | schema v10、迁移、约束、Outbox、恢复与回滚 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 4 | 0 | LAN v1 认证、payload、ACK、断线重试、重复请求与跨端兼容 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |
| 5 | 0 | 生命周期、权限、敏感凭据、MyInvois、输入边界、构建/发布流程与全功能复查 | Clean；Mobile 147/147、Desktop 151/151、集成 29/29 |

每轮 analyze 均为 0 errors；目前 Mobile 有 41 条、Desktop 有 46 条非致命 info/warning。Round 4 和 Round 5 的培训资源检查均通过。Final Release Regression 对 `1.10.9+37` 候选再次通过双端 analyze、全量测试、跨端集成、当前及固定源培训截图验证和版本一致性检查。

## 发布与外部阻塞

- 当前 Debian 环境没有 Android SDK；候选版 `flutter build apk --release` 确认失败于找不到 Android SDK。仓库也没有可用于覆盖既有 Debug 安装的相同签名私钥，因此不能安全制作升级 APK。
- Windows Release 需要 Windows host；候选版 `flutter build windows --release` 在 Linux 上被 Flutter 拒绝。本轮没有生成 APK 或 Windows 包。
- 本机下载并校验的 Mobile APK 是 `v1.10.7-mobile`（SHA-256 `ba6e763059eebcee46ef8d55962546f92e3f4332391da82fedc81fb204e6e3ad`）；Desktop ZIP 是 `v1.10.8`（SHA-256 `f114693cb0633b6ab46a0d5e7ae32885be4bcc0780971c3ce8fe603fc3fc73c6`）。两者只验证既有发布文件完整性，不代表当前未提交源码产物。
- 真实 Android 相机、Windows 打印机、门店 Wi-Fi 与 MyInvois Sandbox/Production 未能在此环境验收。固定 MyInvois 模拟服务、localhost LAN、打印字节和权限测试已运行。
- GitHub 公开 Release 文件可直接下载，近期 CI HTML 显示成功；但 `gh auth status` 确认当前注入 token 无效，无法用该凭据 push、创建 tag 或 Release。

## 下一步

Final Release Regression：PASS（候选版自动化测试、培训截图与版本一致性均通过）；Release：BLOCKED。解除阻塞需要可用 Android SDK 与匹配旧 APK 的签名密钥、Windows 构建 host，以及有效 GitHub 写入凭据。当前修复留在本地工作区，未提交、未推送、未发布。
