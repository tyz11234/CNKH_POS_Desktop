# Cycle 2 Round 1 eInvoice / native / build / training review

基线 Mobile / Desktop 最新 main clones，版本均 `1.10.9+37`；DB schema v10、LAN `cnkh-sync:v1`。本报告仅覆盖分配范围，完整回归执行结果由根代理统一汇总。

## 动态发现与覆盖

- Shared S18、Mobile M07、Desktop D06/D07：Desktop 环境配置、AES-GCM OS key credential/PFX保存、OAuth token缓存/过期/401/Retry-After/重定向阻断、Invoice 1.0输入/1.1签名输出、PFX证书资料/时效/KeyUsage/EKU/RSA匹配、提交claims/幂等/未知结果冻结、Accepted/Rejected/Submitted/Validated/Invalid/Cancelled、独立纠错尝试、Portal UUID+Submission UID核对、POS void相互排除与审计、只读Mobile镜像环境/Host隔离及全快照失败保留。
- Mobile M10、Desktop D13：11课（Mobile额外12th截图及小屏图），实际控件截图捕获、坐标/字体、PNG/JSON字节对应、打包资源验证、Desktop截图来源及培训文字。
- Desktop D12及Mobile APK release：实际现行所有workflow triggers/conditions、签名配置、包命名/checksum/培训资源检查、native Manifest/权限/FileProvider/Kotlin share、Windows runtime/CMake/plugins/版本资源。
- package_info_plus版本/Build读取、当前依赖和lock一致性、Windows secure-storage支持及Mobile无税务凭据/MyInvois直连。
- 每轮重新扫描范围文件清单及校验值见 `einvoice/reviewed-files.json`。未发现本轮新增正式依赖或eInvoice API；脚本门槛及其测试新增须加入后续全部轮次。

## 确认问题 A：Mobile培训截图固定旧Desktop并遗漏现行税务操作

影响两端培训文字与Mobile复制的Desktop截图。旧代码位置 Mobile `.github/workflows/mobile-ci.yml:47–65` 固定 `02e3574b16d45bf0e13f89f5f1d1b42f50bfa3f3` (Desktop v0.4.0)，未使用现行 `.github/paired-desktop-ref`。根代理拉取的 `training-desktop` 确认该SHA设置页面没有PFX/P12导入（旧einvoice_setup_screen全文件无证书入口），历史帮助仍把Rejected/Invalid合并；现行Desktop设置页已有证书按钮、Invalid独立更正和Submission UID核对。培训课程文字也未指导必需数字证书及新状态步骤。

最小复现：执行 `flutter test --no-pub test/training_source_regression_test.dart`，旧workflow选择检查、PFX课程内容检查均失败（`einvoice/training-before.log`）。不需要设备或真实税务提交。

修复：workflow从配对ref文件选择Desktop培训source并记录实际SHA；双端培训文字加入有效TIN/BRN匹配PFX/P12、Test Connection仅OAuth、Rejected/Invalid区别、独立更正保留UUID及未知结果UUID+Submission UID。

永久回归：Mobile `test/training_source_regression_test.dart` 2/2通过，Desktop `test/training_content_regression_test.dart` 1/1通过。证据 `einvoice/training-after-mobile.log`、`einvoice/training-after-desktop.log`。最新截图捕获及实际bundle由根代理完整pipeline执行。

## 确认问题 B：Release允许覆盖旧同版本资产与tag版本错配

两端Create GitHub Release直接调用softprops/action-gh-release v2，缺少既有Release/不可变tag检查；自动包版本取pubspec，tag触发则直接采用github.ref_name。重新运行相同release job会替换同名包；将旧tag推送于新版本代码可使tag/version/package不一致。这是master §41、§47的发布门槛缺陷，未实际覆盖任何线上产物。

最小修复：两端新增 `tool/check_release_gate.py` 只用GET，校验pubspec→tag、tag触发名、完整源SHA、已存在Release一律阻断、已有轻量/annotated tag递归解析必须指向源SHA；main/tag发布共享concurrency mutex，发布不取消，softprops设置 `overwrite_files: false`。普通CI保留其原并发策略。每次CI独立执行 `python3 tool/test_release_gate.py`（Windows用 `python`）。

永久回归：每端26个Python tests覆盖新版本允许、已存在正式/草稿Release拒绝、仅build号变化拒绝旧semver、错tag/shortSHA/tag指向错误源阻断、annotated循环及异常API fail-closed、secret不打印、只GET、workflow guard条件/顺序及共享mutex。修复前workflow contract两项失败，见 `einvoice/release-gate-before.log`；修复后两端各26/26 PASS，见 `einvoice/release-gate-after.log`。YAML parse与两端diff --check PASS。未执行真实Release写操作，正式Mobile签名gate未放宽。

## 已排除候选，避免伪Bug

- 签名先以Invoice 1.0 canonical计算再输出Invoice1.1与官方JSON签名指南当前示例一致；不能仅按一般XML签名理解把它当新Bug。原MyInvois站点HTTP访问因环境网络policy403不可用，读取GitHub镜像文档/PDF作为解释佐证，未修改签名算法。
- Desktop setup _load退出后controller访问异常现有catch可接住；本轮未复现退出后用户可见错误，不按推测更改代码或计入真实Bug。
- 最新Desktop LAN status endpoint只选择每sale/environment最大attempt，Mobile mirror不会收到所有历史尝试产生重复状态。
- 旧EINVOICE_REPORT等有明确日期和历史版本说明，不粗暴全局替换历史。

## 外部验收边界（无静默skip）

| Feature | Reason / blocker | Static/automatic review | Required follow-up |
|---|---|---|---|
| MyInvois Sandbox/Production | 没有店主真实授权凭据/正式证书；禁止真实税务提交 | 全状态、HTTP fake、证书/签名、环境隔离、migration、Mobile LAN镜像源码和现有测试扫描 | 授权Sandbox验签/信任链/提交/查询/取消后，再独立批准生产验收 |
| Mobile覆盖安装 | 当前可下载APK仍为1.10.7+35 Debug签名，无法核对本轮可用私钥与旧证书匹配 | Gradle/CI签名gate保持；不得发布换签名包冒充可覆盖升级 | 使用相同私钥正式构建；实际旧包带未同步业务升级验收 |
| Android权限/外设 | 无实体相机/打印机Android设备 | Manifest、minSdk、联网/相机/Bluetooth/contacts声明、FileProvider/native share review | 真机授予/拒绝/再打开设置、扫码/打印/分享 |
| WindowsGUI及OS secure storage | Linux审查环境无真实Windows用户GUI会话 | Windows源码、runtime插件/metadata/ZIP及CI build/training检查 | Windows首次启动、OS密钥保管/换用户、真实文件/打印机验收 |

不以mock HTTP、source比对、build成功宣称真实LHDNM/设备验收完成。正式Mobile签名阻塞继续保留。

## 本轮范围结论

确认新问题2组（培训来源/步骤漂移；不可变Release/tag版本门槛），均最小修复并永久回归；签名/状态算法无未确认改动。文件级review manifest 45份（含新gate脚本）。所有范围适用测试交根代理完整回归与build/training pipeline汇总，外部边界4项如上。

既有正式Release只读验证：direct urllib访问api.github.com受环境代理403，正确fail-closed（不能作为已发布检测成功证据）；GitHub connector GET获得实际Desktop v1.10.9快照，本地guard对该真实快照拒绝“already exists”。快照 `einvoice/desktop-release-readonly-snapshot.json` 的包大小17,516,801与SHA-256 `5b02d3ce4eb00e57796dc5fd3360d48d6acb1abcb493d2fbed6d23d39848870f`保持既有Release一致。未写线上Release。
