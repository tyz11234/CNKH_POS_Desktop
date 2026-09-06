# 黄金发宝号 · CNKH POS Desktop

用于 Windows 电脑的门店收银与管理系统。电脑作为店内局域网主机，与 [CNKH POS Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK) 配套使用，核心收银与店内同步不依赖云服务器。

基于 **Flutter / Dart**，使用本地 SQLite 保存业务数据。

[下载与构建](#下载与安装) · [首次登录](#首次登录) · [手机配对](#连接手机端) · [修复说明](RELIABILITY_NOTES.md)

> 更新日期：2026-09-06。本文的登录与同步说明适用于已合并的修复代码及下方修复构建。此前发布的安装包不会因为源码更新而自动获得修复。

## 当前状态

| 项目 | 状态 |
| --- | --- |
| 电脑源码 | `main`，已合并 [本轮修复 #6](https://github.com/tyz11234/CNKH_POS_Desktop/pull/6) |
| 配套手机源码 | [`source/main`](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)，已合并配套修复 |
| 修复构建 | Windows Release 已构建成功，见下方 Actions |
| 最近正式 Release | [v0.3.2](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2)，发布于 2026-09-05，早于本轮修复 |
| 源码版本字段 | Desktop `0.3.2+5` / Mobile `1.8.2+24`，本轮未递增版本号 |
| 新增 OCR 进货功能 | 本轮未实施，不属于已完成修复 |

**本轮修复尚未单独发布新 Release。请按构建链接或提交记录区分修复版，不要只看版本号。**

## 主要功能

| 模块 | 功能 |
| --- | --- |
| 收银 | 商品搜索、条码加购、购物车、行折扣、整单折扣、挂单与取单 |
| 收款 | 现金、银行卡、DuitNow、赊账、找零及欠款记录 |
| 商品与库存 | 商品、分类、成本与售价、进货、盘点、供应商管理 |
| 客户与销售 | 客户资料、今日与历史销售、销售详情、作废 |
| 小票与报表 | 小票模板、电子收据 PDF、WhatsApp 分享、销售与成本毛利报表、日结 |
| 局域网同步 | 显示配对二维码、接收手机业务、同步库存与销售、HTTP 对账及 WebSocket 变更通知 |
| 账号 | 管理员与员工权限、实际 PIN 验证、员工 PIN 设置 |

现有收银金额、折扣、舍入规则和页面布局保持不变。DuitNow 收款码展示不等同于银行自动到账确认。

## 下载与安装

### 已验证的修复构建

- [Windows 修复构建及下载入口](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34007132758)
- [配套 Android 修复构建及下载入口](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34006764842)

登录 GitHub 后，在运行页面下方 **Artifacts** 下载对应压缩包。Actions 产物有保留期限，过期后可通过源码重新构建。

Windows 安装步骤：

1. 下载并解压 Windows artifact；若其中还有程序 ZIP，再解压一层。
2. 保留完整程序目录，包括 DLL 与 `data` 文件夹。
3. 运行 `cnkh_pos_desktop.exe`，不要只复制 EXE。
4. 配套更新手机端后，再进行同步。

### 既有正式发布

[v0.3.2 Release](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2) · [所有 Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases)

这些旧安装包保留作版本追溯，**不包含本轮新增修复**。

## 首次登录

首次运行修复版，或从尚未设置真实 PIN 的旧版升级时：

1. 在原登录页选择管理员，用户名使用 `admin`。
2. 输入自定的 **6–12 位数字 PIN**，点击登录。
3. 按提示再次输入同一 PIN，完成初始化并登录。
4. 在用户管理列表点选员工，为员工设置 PIN。

预置员工账号包括 `staff`、`staff2`，需要管理员先分配 PIN。登录页的角色选项不会提升账号权限，实际角色以数据库账号记录为准。

PIN 连续输错 5 次会锁定 5 分钟。恢复出厂业务数据时保留管理员 PIN，员工 PIN 需重新设置。两端账号凭据分别在本机管理，配对不会自动同步 PIN。

## 连接手机端

1. 电脑与 Android 手机连接同一 Wi-Fi 或可互通的局域网。
2. 启动电脑端，打开 LAN / 扫码配对页面，显示二维码。
3. 手机端点击扫码配对，扫描电脑二维码。
4. 手机保存电脑地址和配对令牌，完成同步。

默认端口为 **8787**，二维码前缀为 `cnkh-sync:v1|`。若连接失败，检查电脑是否运行、IP 是否变化，以及 Windows 防火墙是否允许该程序在专用网络通信。

电脑需要保持运行，手机才能与其同步；手机暂时断线仍可本地开单，恢复连接后自动重试。

## 本轮修复带来的行为

- 结账与扣库存使用同一数据库事务；启用“禁止缺货”时复查实际库存。
- 作废回补库存并防止重复回补；手机作废能上传，电脑作废能回传。
- 保存两端商品与客户 ID 对照，避免条码匹配后扣错库存或丢失赊账关联。
- 已配对手机的销售、作废、资料修改、进货及盘点写入持久队列，电脑确认后才移除。
- 断线后自动重试，同一操作不会因重复提交再次入库或扣库存。
- 电脑界面响应远程业务变化；历史销售查询取消默认 200 条截断。
- 新销售保存当时成本；后续修改商品成本不会改变这些销售的历史毛利。

若盘点或资料修改发生冲突，系统会保留待同步操作并提示错误，不会静默覆盖另一端。请核对业务记录后处理，不要靠清空手机数据解决冲突。

旧销售未保存的历史成本无法凭空恢复；升级前已作废的旧单不会被批量自动回补。详细说明见 [RELIABILITY_NOTES.md](RELIABILITY_NOTES.md)。

## 开发与验证

在具备 Flutter Windows 桌面构建环境的电脑上执行：

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build windows --release
```

完整程序输出目录：`build/windows/x64/runner/Release/`。

本轮已验证：

- [Windows：静态分析、35 项测试、Release 构建](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34007132758)
- [Desktop / Mobile：6 项真实 HTTP 联调测试](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/34007132843)
- [Android：静态分析、25 项测试、Release APK 构建](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/34006764842)

联调覆盖 ID 与赊账关联、离线进货/销售/作废顺序、盘点冲突、初始断线重连、确认丢失重试以及电脑作废回传。自动化通过不代表已验证所有实际打印机和手机型号。

## 相关入口

- [Android 下载主页](https://github.com/tyz11234/CNKH_POS_Mobile_APK)
- [Android Flutter 源码](https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main)
- [本轮修复记录](https://github.com/tyz11234/CNKH_POS_Desktop/pull/6)
