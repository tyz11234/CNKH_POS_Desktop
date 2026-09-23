# CNKH POS Desktop 1.10.4+32

- LAN 增量同步现在追踪进货记录的新增、修改、删除，并为旧记录建立同步基线；手机端可以按游标获取进货历史。
- MyInvois PFX/P12 检查证书有效期、马来西亚主体字段、配置的 TIN/BRN、签名用途、RSA 密钥类型与证书公钥匹配。
- 提交前校验发票签名的摘要和 RSA 数学签名；测试改用测试专用 PFX，并覆盖签名篡改。
- 同步协议文档更新至配套 Desktop / Mobile 1.10.4+32。

## 验证

Desktop 静态分析、完整测试、Windows Release 构建及与配套 Mobile 的 LAN HTTP 回归均通过。MyInvois 实际 Sandbox / Production 提交尚未执行；正式使用须配置已授权 API 凭据和马来西亚认可 CA 签发证书。
