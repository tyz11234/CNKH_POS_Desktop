# 黄金发宝号 · CNKH POS Desktop

> README 最后更新：**2026-09-05**

Flutter 桌面收银端（Windows / Linux）。Desktop 作为店内局域网权威主机，与 CNKH POS Mobile 直接同步，不需要云服务器。

## 当前正式组合

| 项目 | 当前正式版本 |
|---|---|
| Desktop | **0.3.2+5**（`v0.3.2`） |
| Mobile | **1.8.2+24**（`v1.8.2-mobile`） |
| LAN 协议 | `cnkh-sync:v1` |
| Desktop 发布日期 | **2026-09-05** |
| Mobile 发布日期 | **2026-09-05** |

推荐配套使用：**Desktop v0.3.2 + Mobile v1.8.2**。

## 下载 Desktop 正式版

- [Desktop v0.3.2 Release 页面](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.3.2)
- [直接下载 Windows x64 v0.3.2+5](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v0.3.2/CNKH_POS_Desktop-windows-x64-v0.3.2-5.zip)
- [全部 Desktop Releases](https://github.com/tyz11234/CNKH_POS_Desktop/releases)

Windows 正式包：

```text
CNKH_POS_Desktop-windows-x64-v0.3.2-5.zip
```

SHA-256：

```text
94a69a22316f1dadd492b8118fe0530818430163e8e74be4467cb069098e049b
```

Mobile 正式版：
https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.8.2-mobile

## v0.3.2 重点

- Desktop 作为局域网权威主机
- Desktop 显示二维码，Mobile 扫码配对
- 配对 Token 与局域网地址管理
- 商品、库存、分类、客户、销售同步
- WebSocket 实时变更提示
- HTTP 对账
- Mobile 离线销售幂等导入
- Desktop 权威库存回传 Mobile
- 作废销售状态同步
- 强制全量对账
- LAN 网卡 / 本机 IP 选择优化
- Windows release CI 与正式 GitHub Release

## Windows 安装

1. 打开上面的 **v0.3.2 Release**。
2. 下载 `CNKH_POS_Desktop-windows-x64-v0.3.2-5.zip`。
3. 解压到任意文件夹，**整包保留**，不要只复制 exe。
4. 双击 `cnkh_pos_desktop.exe`。

本地构建：

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter build windows --release
```

Windows 构建产物：

```text
build/windows/x64/runner/Release/
```

## 第一次登录

数据库会自动写入种子账号：

| 用户名 | 角色 | PIN |
|---|---|---|
| `admin` | 管理员 | 演示任意 PIN |
| `staff` / `staff2` | 员工 | 演示任意 PIN |

建议先使用 Admin 设置店名、DuitNow、小票格式；日常收银使用 Staff。

## 局域网配对与同步

1. 手机与 PC 连接同一个 Wi‑Fi / LAN。
2. 打开 **Desktop v0.3.2**；Desktop 作为局域网主机，默认端口 `8787`。
3. Desktop 打开 LAN / 扫码配对，电脑显示二维码。
4. Mobile v1.8.2 点击扫码配对并扫描电脑二维码。
5. Mobile 保存 Desktop 地址和 Token，之后自动重连并进行 HTTP 对账。

协议前缀：

```text
cnkh-sync:v1
```

推荐正式组合：

```text
Desktop v0.3.2 + Mobile v1.8.2
```

当前同步包括：

- 商品、库存、分类、客户同步
- 销售记录同步
- WebSocket 实时变更提示
- HTTP 定时对账
- Mobile 离线销售持久化、重试和幂等导入
- Desktop 销售 / 进货 / 盘点后的库存回传 Mobile
- Desktop 作废销售状态回传 Mobile
- 强制全量对账

## 功能一览

### 收银

- Admin / Staff 登录与权限区分
- 商品搜索、分类、连续扫码加购
- 购物车、挂单 / 取单
- 行折扣 / 整单折扣
- 现金 / 卡 / DuitNow / 赊账
- 找零与库存处理

### 销售与小票

- 今日销售与历史销售
- 销售记录查看小票详情
- 80mm 小票格式编辑与实时预览
- 热敏打印与电子收据 PDF 共用模板
- Noto Sans SC 中文 PDF
- Windows 打开 WhatsApp 并发送电子收据
- 收据缓存与自动清理

### 商品 / 进货 / 报表

- 商品进货价与售价
- 供应商管理
- 扫码进货
- 进货单二维码解析
- 进货单图片 / 文本识别流程
- 已有商品入库、未匹配商品新建
- 销售额、成本、毛利、毛利率报表
- 日期范围报表

### 其它

- 客户、供应商、盘点、日结
- DuitNow 收款码
- 演示数据清理
- 工厂初始化
- LAN 配对与同步主机

## 进货单二维码格式

```text
CNKHPO1:{"v":1,"type":"cnkh_purchase","supplier":"五金行","lines":[{"name":"螺丝M6","qty":100,"price":0.15,"barcode":"1234567890123"}]}
```

`price` 为进货单价（RM）。匹配优先级为条码 / SKU，再到品名；未匹配商品可新建。

## 版本说明

| 版本 | 状态 | 日期 | 说明 |
|---|---|---|---|
| `0.3.2+5` | **当前正式版** | 2026-09-05 | QR 配对、Desktop-hosted LAN 同步一致性、正式发布流程 |
| `0.3.1+4` | 历史正式版 | 2026-09-04 | 中文电子收据、Windows WhatsApp PDF |
| `0.3.0` | 历史正式版 | 2026-09-04 | 进货、供应商、成本 / 毛利报表、Windows Actions |
| `0.1.0` | 历史正式版 | 2026-09-04 | Flutter Desktop 首发 |

README-only 文档更新不会改变已发布应用功能；正式程序版本仍以 GitHub Release 为准。

## 开发与验证

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

正式 Windows CI 会执行 Analyze、测试、Windows release build、打包与 artifact 上传；带正式发布标记的提交才会创建 GitHub Release。

## 相关仓库

- Desktop：https://github.com/tyz11234/CNKH_POS_Desktop
- Mobile：https://github.com/tyz11234/CNKH_POS_Mobile_APK
- Mobile 源码：https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main
- Mobile v1.8.2：https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.8.2-mobile
