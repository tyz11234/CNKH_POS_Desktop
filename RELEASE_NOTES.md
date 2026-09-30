# CNKH POS Desktop 1.10.6+34

- 为 v1 协议增加可选库存流水与确定性撤销拒绝能力；Mobile 可发现销售后作废的净零库存活动，并保留失败请求及审计。
- 首次配对按 SKU/条码安全关联已有资料，保留 Desktop 库存与成本基线；业务进货 ID 重放校验内容，避免重复加库存。
- MyInvois 区分同步拒收与最终 Invalid，使用不可覆盖的提交尝试、关联纠错记录和新发票号码；未知结果核对原 Get Submission，不再提交。
- schema v10 保留原 UUID、签名 payload 和日志；增加双端 HTTP、真实备份恢复、丢失 ACK 和可控税务 HTTP 回归用例。

## 本次实际验证

- Mobile 完整 `flutter test` **124 项通过**；Desktop 完整测试 **116 项通过**。
- Desktop `integration/` 的 `flutter test test regression` **19 项通过**；实际双端 HTTP 覆盖净零库存、首次配对、重复/丢失 ACK、队列拒绝和备份恢复。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：Mobile **0 error / 5 warnings / 37 infos**；Desktop **0 error / 6 warnings / 38 infos**。这不是零告警分析。
- PR CI 的 `flutter build apk --release`、`flutter build windows --release` 及培训资源检查通过；正式发布会在 main 重跑并生成下载资产。
- 旧数据库升级用例已执行。本机缺少 Flutter 的退出 127 记录与远端实际结果分别记载，详见 [FIX_VERIFICATION.md](FIX_VERIFICATION.md)。

APK 优先使用仓库稳定签名密钥；未配置时沿用此前已授权的 Android Debug 签名发布方式，实际签名以发布 CI 检查为准。签名不匹配时不能覆盖安装；先完成业务同步与备份，保留旧版未确认操作，避免卸载丢失数据。Windows 包沿用完整 ZIP 便携包，解压后运行 `cnkh_pos_desktop.exe`，保留 DLL 和 data 文件夹。

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
