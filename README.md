# 黄金发宝号 · POS Desktop

Flutter 桌面收银（**Windows / Linux**），与手机 APK 功能对齐。

| | |
|--|--|
| 店名 | **黄金发宝号** |
| 包名 | `cnkh_pos_desktop` |
| 版本 | **v0.3.0** |
| 仓库 | https://github.com/tyz11234/CNKH_POS_Desktop |
| 手机 APK | https://github.com/tyz11234/CNKH_POS_Mobile_APK |

---

## 店铺怎么拿 Windows 安装包

1. 打开 [Actions → Windows Release](https://github.com/tyz11234/CNKH_POS_Desktop/actions/workflows/windows-release.yml)
2. 选最新**成功**的运行记录
3. 下载 Artifact：`CNKH_POS_Desktop-windows-x64-v…`（zip）
4. 或到 [Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases) 下载带 tag 的包（如 `v0.3.0`）

解压后运行目录里的 `cnkh_pos_desktop.exe`（同目录 dll 勿删）。

本地构建：

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter build windows --release
# 产物：build/windows/x64/runner/Release/
```

演示账号：种子 **Admin / Staff**（与手机端一致）。

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
- 电子收据缓存（可配路径、约 7 天清理）；系统分享发 PDF

### 商品 / 进货 / 报表
- 商品：**进货价** + **售价**
- **进货**：选/新建供货商；**扫码进货**；扫进货单二维码或拍照/粘贴识别（品名、数量、价格）→ 已有商品入库，没有则新建
- **报表**：销售额、成本（按进货价估算）、**毛利**、毛利率；今日与日期范围

### 其它
- 客户 / 供应商、盘点、日结、员工
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
  desktop_shell.dart      # 侧栏壳
  screens/                # 业务页（含 admin）
  services/               # SQLite、进货识别、小票模板、报表利润…
  db/app_database.dart
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
| **v0.3.0** | 扫码/单据进货、供货商、进货价/售价、报表毛利、Windows Actions |
| v0.2.0 | 小票模板编辑 + 销售点进小票详情 |
| v0.1.0 | 桌面首发，与手机功能对齐 |

手机端发布见 [CNKH_POS_Mobile_APK Releases](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases)。
