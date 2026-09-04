# 黄金发宝号 · POS Desktop（Flutter）

Flutter **桌面收银**（Windows / Linux），与手机 APK **功能对等**（基于 `/mobile` 同源逻辑，桌面宽屏 UI）。

- 包名：`cnkh_pos_desktop`
- 店名 / 窗口标题：**黄金发宝号 POS Desktop**
- 版本：**v0.1.0-desktop**
- 仓库：<https://github.com/tyz11234/CNKH_POS_Desktop>

> 本仓是 **新桌面工程**，不再继续修补旧 PySide6 仓库 [`-CNKH_POS_V5`](https://github.com/tyz11234/-CNKH_POS_V5)。  
> 手机端 APK 源码/发布见 [`CNKH_POS_Mobile_APK`](https://github.com/tyz11234/CNKH_POS_Mobile_APK) / monorepo `cnkh-v5/mobile`。

---

## 安装与构建

### 环境

- Flutter 3.35+（Dart 3.9+）
- Windows：Visual Studio Desktop C++ 工作负载  
- Linux：`clang` / `cmake` / `ninja` / GTK3 开发包；系统需有 `libsqlite3`

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter run -d windows    # 或 linux
# 发布包：
flutter build windows --release
flutter build linux --release
```

演示账号：种子 **Admin / Staff**（与手机端一致，见设置或店内约定）。

---

## 与手机 APK 功能对照（完整对等）

| 模块 | 手机 APK | 本 Desktop |
|------|----------|------------|
| 登录 Admin / Staff | ✅ | ✅ |
| DuitNow QR（仅 Admin 可改） | ✅ | ✅ |
| POS 搜索 / 分类芯片 | ✅ | ✅ 左栏商品网格 |
| 连续扫码加购 | ✅ 摄像头 | ✅（摄像头/扫码枪；无摄像头时可用搜索） |
| 购物车 / 挂单 / 取单 / 超时提醒 | ✅ | ✅ 右栏购物车 |
| 行折扣 / 整单折扣 + 审计 | ✅ | ✅ |
| 结账 现金/卡/DuitNow/赊账 | ✅ | ✅ 独立结账页，折扣/找零分行不重叠 |
| 找零对话框 / 库存 warn·block | ✅ | ✅ |
| 今日销售 / 搜索 / 作废 | ✅ | ✅ |
| 电子收据 PDF | ✅ | ✅ |
| 收据缓存路径可配 + 7 天清理 | ✅ | ✅ 设置里选目录 |
| WhatsApp 发 PDF | ✅ Intent | ✅ 系统分享 / WhatsApp Desktop（不用损坏的 wa.me 后删文件） |
| 商品 CRUD / 条码自动·手动 | ✅ | ✅ 侧栏「商品」+ 管理中心 |
| 批量选择删除 / 条码批量导出 PNG | ✅ | ✅ |
| 分类选择器 / 商品图开关 | ✅ | ✅ |
| 客户 / 供应商 | ✅ | ✅ 侧栏「客户」 |
| 进货 / 盘点 | ✅ | ✅ 侧栏「进货」+ 管理 |
| 报表 / 日结 / 员工列表 | ✅ | ✅ |
| 维护：清演示交易 | ✅ | ✅ |
| **初始化工厂重置**（输入「初始化」） | ✅（库层） | ✅ 维护页强制确认 + 清收据缓存 |
| 设置：店名、库存策略、挂单超时、扫码反馈、BT、商品图 | ✅ | ✅ |
| LAN 同步客户端（cnkh-sync） | ✅ | ✅ 与旧 PC 服务端协议兼容 |
| 培训页 | ✅ | ✅ 顶栏入口 |
| 蓝牙小票（可选） | ✅ | ✅（桌面视硬件/驱动） |

### 故意仍依赖旧 PC / 后续迭代

| 项 | 说明 |
|----|------|
| LAN **服务端** | v0.1 以 **客户端** 为主，可配对 [`-CNKH_POS_V5`](https://github.com/tyz11234/-CNKH_POS_V5) 已开的同步服务（默认端口 **8787**）。桌面内嵌服务端后续版本再加。 |
| 条码标签 **硬件** 打印对话框 | 旧 Windows Admin；本端支持队列 + PNG 批量导出 |
| Windows 整库二进制备份/还原 | 旧 PySide 工具链 |

---

## 局域网配对（companion）

1. 电脑与本机同一 Wi‑Fi / 局域网  
2. 旧 PC 打开同步服务并显示配对二维码  
3. 本 Desktop 顶栏 **扫码配对**，或设置 → LAN Sync 手填：

```text
http://电脑IP:8787
```

配对码格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.x.x:8787","token":"...","name":"CNKH-PC"}
```

结账后销售近实时推送；可强制全量对账。详见 `LAN_SYNC.md`。

---

## 桌面 UI 要点

- 左侧 **NavigationRail**：收银 · 今日 · 商品 · 客户 · 进货 · 报表 · 管理 · 维护 · 设置（Staff 仅见收银/今日/设置）  
- **收银两栏**：左商品网格，右购物车 + 清晰合计/折扣/结账行  
- 宽窗口默认约 1440×900  

---

## 初始化（危险）

**维护 → 初始化清空全部数据**：输入 `初始化` 确认。  
会 wipe 业务表并重新种子用户/目录，同时清空电子收据缓存；完成后需重新登录。

---

## 开发说明

```
lib/
  main.dart              # 入口
  desktop_shell.dart     # NavigationRail 壳
  screens/               # 与手机同源页面（含 admin）
  services/              # SQLite 仓库、LAN、e-receipt…
  db/app_database.dart   # 本地库 cnkh_pos_desktop.db
```

可选保留 `android/` 以便同源调试；正式桌面目标为 **windows + linux**。

---

## 版本

| Tag | 说明 |
|-----|------|
| **v0.1.0-desktop** | 首发：全功能移植 + 桌面壳 + 工厂重置 + README |
