# CNKH POS Desktop 1.10.11+39 — 收款记录与到账播报

发布日期：2026-10-28。Windows Setup.exe 与便携 ZIP 由 GitHub Actions 构建。数据库 schema 保持 v10，LAN 协议保持 `cnkh-sync:v1`。

## 本次更新

- **新增「收款记录 Payments」页面**（管理中心入口）：读取云端收款台账，显示今日 / 本月 / 累计收款汇总，每笔带金额 + 银行流水号（Transaction Ref）+ 时间。
- **每条记录右侧新增喇叭按钮**：点击即可重新播报该笔到账金额（只播报金额，与实时到账播报同一语音通道）。
- **补回仓库此前遗失的到账播报监听服务**（`payment_broadcast_listener.dart`）及桌面外壳接线：Public Bank DuitNow QR 到账时自动语音播报金额并弹出到账横幅。仓库版本此前缺失此文件，本版起与正式发布源码一致。
- 数据来自云端服务器（43.156.169.203）的收款台账（银行通知邮件自动入账）；网页版已同步上线相同功能。

## 安装提示

- 双击 `CNKH_POS_Desktop-windows-x64-v1.10.11-39-Setup.exe` 安装即可；也可以使用便携 ZIP 解压运行。
