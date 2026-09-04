# 黄金发宝号 · POS Desktop

Flutter 桌面收银（**Windows / Linux**），与手机 APK 功能对齐。

| | |
|--|--|
| 店名 | **黄金发宝号** |
| 包名 | `cnkh_pos_desktop` |
| 版本 | **v0.3.1** |
| 仓库 | https://github.com/tyz11234/CNKH_POS_Desktop |
| 手机 APK | https://github.com/tyz11234/CNKH_POS_Mobile_APK |

---

## 店铺怎么拿 Windows 包

1. 打开 [Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases)（推荐最新 **v0.3.1**）
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
- 局域网同步客户端（`cnkh-sync`）
- 维护：清演示数据、**工厂初始化**（输入「初始化」）
- DuitNow 收款码（仅 Admin 可改）

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
  services/          # e-receipt（Noto PDF）、进货识别、小票模板、利润…
  db/app_database.dart
assets/fonts/NotoSansSC-Regular.ttf
windows/runner/whatsapp_share.*   # Windows 直开 WhatsApp
```

```bash
flutter analyze
flutter test
flutter run -d windows   # 或 linux
```

---

## 版本

| 版本 | 说明 |
|------|------|
| **v0.3.1** | 电子收据中文 PDF；Windows/Android 直开 WhatsApp 发 PDF |
| v0.3.0 | 扫码/单据进货、供货商、进货价/售价、报表毛利、Windows Actions |
| v0.2.0 | 小票模板编辑 + 销售点进小票详情 |
| v0.1.0 | 桌面首发 |

手机端：[CNKH_POS_Mobile_APK Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)
