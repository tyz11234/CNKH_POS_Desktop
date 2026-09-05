# 黄金发宝号 · POS Desktop

> README 最后更新：**2026-09-05**

Flutter 桌面收银（**Windows / Linux**），与手机 APK 功能对齐。

| | |
|--|--|
| 店名 | **黄金发宝号** |
| 包名 | `cnkh_pos_desktop` |
| 当前正式版本 | **v0.3.1** |
| 正式版本发布日期 | **2026-09-04** |
| 当前 `main` 源码更新日期 | **2026-09-05** |
| 仓库 | https://github.com/tyz11234/CNKH_POS_Desktop |
| 手机 APK | https://github.com/tyz11234/CNKH_POS_Mobile_APK |

> 当前 `main` 已包含 2026-09-05 完成的 Desktop ↔ Mobile LAN 配对与同步一致性修复，因此源码状态比已发布的 `v0.3.1` Release 更新。只有创建新的 GitHub Release 并附带构建产物后，才把这些源码改动视为新的正式发布版本。

---

## 版本概览

| 版本 / 阶段 | 状态 | 更新 / 发布日期 | 重点 |
|---|---|---|---|
| `main`（v0.3.1 之后） | 当前源码，尚未单独发布新版本 | **2026-09-05** | Desktop 作为局域网权威主机、二维码配对、增量同步、幂等 Mobile 销售导入、强制对账、连接状态、LAN 网卡选择优化 |
| `v0.3.1` | 正式 Release | **2026-09-04** | 电子收据中文 PDF；Windows 直开 WhatsApp 发 PDF |
| `v0.3.0` | 正式 Release | **2026-09-04** | 扫码/单据进货、供货商、进货价/售价、报表毛利、Windows Actions |
| `0.2.0+2` | 源码阶段，未单独建立 GitHub Release | **2026-09-04** | 小票模板编辑 + 实时预览、销售记录点进小票详情 |
| `v0.1.0-desktop` | 正式 Release | **2026-09-04** | Flutter Desktop 首发、基础 POS、SQLite、LAN、电子收据 |

正式 Release 日期以 GitHub Release 的 `published_at` 日期为准；未单独发布的源码阶段使用对应 PR / 源码合并日期。

---

## 店铺怎么拿 Windows 包

1. 打开 [Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases)（当前正式 Release 为 **v0.3.1**）
2. 下载 `CNKH_POS_Desktop-windows-x64-v0.3.1-4.zip`（或 Actions → Windows Release 的 Artifact）
3. 解压到任意文件夹，**整包保留**（勿只拷 exe）
4. 双击 `cnkh_pos_desktop.exe`

本地构建：

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter build windows --release
# 产物：build/windows/x64/runner/Release/
```

### 第一次登录

库会自动写入种子账号，**不用先建 Staff**：

| 用户名 | 角色 | PIN |
|--------|------|-----|
| `admin` | 管理员 | 演示任意 PIN |
| `staff` / `staff2` | 员工 | 演示任意 PIN |

建议先用 Admin 设店名、DuitNow、小票格式；日常收银用 Staff。

数据库与旧 PySide V5 **分开**，不会互相覆盖（新库在「文档」下的 `cnkh_pos_desktop.db`）。

---

## 功能一览

### 收银
- Admin / Staff 登录；Staff 权限受限
- 商品搜索、分类、连续扫码加购
- 购物车、挂单 / 取单、行折扣 / 整单折扣
- 结账：现金 / 卡 / DuitNow / 赊账；找零与库存策略

### 销售与小票
- **今日**、**销售记录**：点进订单看**小票详情**
- **设置 → 小票格式**：左改右预览（80mm）；热敏打印与电子收据 PDF **同一模板**
- 电子收据 PDF：**嵌入中文字体（Noto Sans SC）**，避免乱码
- **发送电子收据**：直接打开 **WhatsApp**
  - Windows：打开 WhatsApp Desktop，PDF 放入剪贴板 → 聊天里 **Ctrl+V** 粘贴发送
  - （手机见 APK 说明：Intent 直接附加 PDF）
- 收据缓存可配路径，约 7 天自动清理

### 商品 / 进货 / 报表
- 商品：**进货价** + **售价**
- **进货**：选/新建供货商；**扫码进货**；扫进货单二维码或拍照/粘贴识别（品名、数量、价格）→ 已有商品入库，没有则新建
- **报表**：销售额、成本（按进货价估算）、**毛利**、毛利率；今日与日期范围

### 其它
- 客户 / 供应商、盘点、日结
- 局域网同步主机（`cnkh-sync:v1`）：Desktop 作为权威主机，Mobile 扫描 Desktop 二维码配对
- 维护：清演示数据、**工厂初始化**（输入「初始化」）
- DuitNow 收款码（仅 Admin 可改）

---

## 局域网配对与同步

1. 手机与 PC 连接同一个 Wi‑Fi / LAN。
2. Desktop 打开后作为局域网主机监听默认端口 `8787`。
3. Desktop 顶栏点击 LAN / 扫码配对，电脑显示二维码。
4. Mobile 顶栏点击扫码配对，用手机扫描电脑二维码。
5. 配对成功后 Mobile 保存 Desktop 地址和 Token，并自动重连。

协议前缀：`cnkh-sync:v1`

当前 `main` 已包含：

- 商品、库存、分类、客户、销售增量同步
- WebSocket 实时变更提示
- HTTP 定时对账
- Mobile 离线销售幂等导入
- Desktop 权威库存回传 Mobile
- 作废销售状态同步
- 强制全量对账
- 更安全的本机 LAN IP / 网卡选择

---

## 进货单二维码格式

```text
CNKHPO1:{"v":1,"type":"cnkh_purchase","supplier":"五金行","lines":[{"name":"螺丝M6","qty":100,"price":0.15,"barcode":"1234567890123"}]}
```

`price` = 进货单价（RM）。匹配：条码/SKU → 品名；未匹配则新建商品。

---

## 桌面界面

左侧栏：收银 · 今日 · 商品 · 客户 · 进货 · 报表 · 管理 · 维护 · 设置  
（Staff 主要见收银 / 今日 / 设置）

收银为左右两栏：左商品，右购物车。

---

## 开发

```text
lib/
  main.dart
  desktop_shell.dart
  screens/
  services/          # e-receipt（Noto PDF）、进货识别、小票模板、利润、LAN host…
  db/app_database.dart
assets/fonts/NotoSansSC-Regular.ttf
windows/runner/whatsapp_share.*   # Windows 直开 WhatsApp
```

```bash
flutter analyze
flutter test
flutter run -d windows   # 或 linux
```

手机端：[CNKH_POS_Mobile_APK Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)
