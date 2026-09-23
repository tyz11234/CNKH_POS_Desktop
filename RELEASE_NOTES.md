# CNKH POS Desktop 1.10.3+31 (源码更新，CI 验证中)

- 增加 MyInvois PFX/P12 数字证书导入与加密保存。
- 生成符合官方 JSON 签名流程的 Invoice 1.1 签名结构；没有证书时禁止准备发票，历史未签名待提交记录也会被拦截。
- 新增证书加密保存、缺少签名证书时阻止准备发票、历史未签名发票拦截等回归测试。
- Desktop 与 Mobile 的 Flutter 应用版本统一为 1.10.3+31；Mobile 仅同步版本号，没有移动端业务代码变更。

保持数据库 schema v9、现有金额算法、离线销售及 LAN 协议不变。真实 MyInvois Sandbox 提交尚未验证；本次推送仅触发 CI 构建，不创建正式 Release。

Windows 包为完整便携 ZIP，不含安装向导；正式更新前关闭程序并备份业务数据。
