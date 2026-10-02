# CNKH POS Desktop 1.10.7+35

- F01–F02：首次配对在 ACK 中持久化唯一商品身份；软删除后同码新建保持新旧实体分离，保护历史及未确认操作。
- F03：本地/LAN 作废与税务提交认领共享事务保护；OAuth 等待后重新核对销售，保留 UUID、未知结果和审计。
- F04：以完整流水证明初始库存基线，保留真实后续活动，进货撤销与 Desktop 权威结果一致。
- F05：收据写入隔离缓存子目录，清理只删除有归属记录且内容校验相符的缓存；不确定归属的旧 PDF 保留。
- F06–F07：OCR 行 ID 按草稿稳定隔离；Desktop matcher 通过单一原子进货操作保存真正的执行前成本，失败全部回滚，重试幂等。
- F08：最后管理员必须活动、有管理权限且具备有效登录凭据；取消设置 PIN 不会允许锁死管理入口。
- F09：两端中文蓝牙小票使用内置字库生成 ESC/POS 栅格字节，保持现有打印入口；实体打印机支持尚待验收。
- F10–F11：恢复出厂保留号码防重及税务记录；日结以事务内现金与明确业务日期保存，防止页面缓存过期或跨日错存。

## 兼容性与验证

保持离线收银、现有页面布局、`cnkh-sync:v1` 与 schema v10。本轮不新增数据库版本或重绑历史实体；旧库增量升级、重复 ensure、旧草稿、历史业务及未确认队列保留已有实际回归。首次配对与库存基线修复建议两端同时更新。旧商品已删除的待上传业务仍明确拒绝并保留，需人工核对，不能通过清空队列解决。

修复分支本轮实际通过 Mobile 完整测试 **130 项**、Desktop **132 项**、Desktop `integration/` 真实 HTTP **29 项**。`flutter analyze --no-fatal-infos --no-fatal-warnings`：Mobile **0 errors / 5 warnings / 37 infos**，Desktop **0 errors / 6 warnings / 38 infos**；这不是零告警。发布 CI 将对 1.10.7+35 重跑完整测试、培训资源检查及 Android/Windows Release 构建，并验证 APK 的签名与 INTERNET 权限。实际发布命令、运行链接、文件 SHA-256 和签名证书最终记录于 README 与 [ELEVEN_BUG_VERIFICATION.md](ELEVEN_BUG_VERIFICATION.md)。

## 下载与升级

- [Android APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/CNKH_POS_Mobile.apk) / [APK SHA256SUMS](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/download/v1.10.7-mobile/SHA256SUMS.txt)
- [Windows x64 ZIP 便携包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.7/CNKH_POS_Desktop-windows-x64-v1.10.7-35.zip) / [ZIP SHA256SUMS](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.7/SHA256SUMS.txt)

发布沿用现有 CI：优先使用已配置的稳定 Android keystore；未配置时沿用此前已授权的 Android Debug 签名方式，以实际签名检查为准。不是 PR 的两天临时验证证书。不同签名不能覆盖安装；更新前同步并备份业务及未确认的离线操作，保留旧 APK，不能直接卸载有未同步数据的旧版。Windows 沿用完整 ZIP 便携包，关闭程序后完整解压，运行 `cnkh_pos_desktop.exe`，保留 DLL 与 data 文件夹。

未执行实体 Android/Windows 升级、门店旧数据库、门店网络/防火墙、相机 OCR、原生分享及实体蓝牙打印机验收；SQLite 旧库与 localhost HTTP 回归不代表现场验收。税务测试全部使用可控 HTTP，没有真实 MyInvois Sandbox/Production 提交。

---

# CNKH POS Desktop 1.10.6+34

- 为 v1 协议增加可选库存流水与确定性撤销拒绝能力；Mobile 可发现销售后作废的净零库存活动，并保留失败请求及审计。
- 首次配对按 SKU/条码安全关联已有资料，保留 Desktop 库存与成本基线；业务进货 ID 重放校验内容，避免重复加库存。
- MyInvois 区分同步拒收与最终 Invalid，使用不可覆盖的提交尝试、关联纠错记录和新发票号码；未知结果核对原 Get Submission，不再提交。
- schema v10 保留原 UUID、签名 payload 和日志；增加双端 HTTP、真实备份恢复、丢失 ACK 和可控税务 HTTP 回归用例。

## 本次实际验证

- Mobile 完整 `flutter test` **124 项通过**；Desktop 完整测试 **116 项通过**。
- Desktop `integration/` 的 `flutter test test regression` **19 项通过**；实际双端 HTTP 覆盖净零库存、首次配对、重复/丢失 ACK、队列拒绝和备份恢复。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：Mobile **0 error / 5 warnings / 37 infos**；Desktop **0 error / 6 warnings / 38 infos**。这不是零告警分析。
- PR 与 main 发布 CI 的 `flutter build apk --release`、`flutter build windows --release` 及培训资源检查通过；APK、Windows ZIP 与 SHA256SUMS 已正式发布。
- 旧数据库升级用例已执行。本机缺少 Flutter 的退出 127 记录与远端实际结果分别记载，详见 [FIX_VERIFICATION.md](FIX_VERIFICATION.md)。

本次 APK 实际采用 **Android Debug 签名**，证书 SHA-256：`4e28edc15b7df8f8fe3245805e7a7db7e88ba5c5217cd76fa196d993b12f2fc4`；CI 已验证签名、INTERNET 权限及培训资源。该签名不保证与旧 APK 或未来构建一致。签名不匹配时不能覆盖安装；先完成业务同步与备份，保留旧版未确认操作，避免卸载丢失数据。Windows 包沿用完整 ZIP 便携包，解压后运行 `cnkh_pos_desktop.exe`，保留 DLL 和 data 文件夹。

未执行 Android / Windows 真机升级、门店 Wi-Fi / 防火墙 / 打印机验收，未向真实 MyInvois Sandbox / Production 提交税务发票。MyInvois 回归使用可控 HTTP 响应，保留原 UUID、提交尝试和审计信息。

---

# CNKH POS Desktop 1.10.5+33

- 手机撤销进货前同步检查 Desktop 权威库存变化；冲突时拒绝操作，不静默丢弃撤销业务。
- 在应用进货的同一事务中保存 Desktop 实际执行前成本；撤销不再信任 Mobile 缓存成本，后续成本变化保护及重复行/幂等处理保留。
- 修复 e-Invoice 设置重新打开后已导入证书仍显示为空。
- 与 Mobile 1.10.5+33 配套发布；数据库 schema、金额逻辑和 LAN 协议保持兼容。

## 验证

Desktop 完整 Flutter 测试 **110 项通过**；分析 **0 error、6 warnings、34 infos**；Desktop `integration/` HTTP 回归 **10 项通过**。Windows Release workflow 负责重新运行测试、分析、培训资源校验并构建便携包。MyInvois 真实 Sandbox/Production 提交以及 Windows 真机/打印机验收未执行。

---

# CNKH POS Desktop 1.10.4+32

- LAN 增量同步现在追踪进货记录的新增、修改、删除，并为旧记录建立同步基线；手机端可以按游标获取进货历史。
- MyInvois PFX/P12 检查证书有效期、马来西亚主体字段、配置的 TIN/BRN、签名用途、RSA 密钥类型与证书公钥匹配。
- 提交前校验发票签名的摘要和 RSA 数学签名；测试改用测试专用 PFX，并覆盖签名篡改。
- 同步协议文档更新至配套 Desktop / Mobile 1.10.4+32。

## 验证

Desktop 静态分析、完整测试、Windows Release 构建及与配套 Mobile 的 LAN HTTP 回归均通过。MyInvois 实际 Sandbox / Production 提交尚未执行；正式使用须配置已授权 API 凭据和马来西亚认可 CA 签发证书。
