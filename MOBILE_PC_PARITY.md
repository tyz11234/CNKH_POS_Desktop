# CNKH POS Desktop ↔ Mobile 功能对照

> 审核日期：**2026-10-03**<br>
> 当前源码候选：**Desktop 1.10.9+37 + Mobile 1.10.9+37**（未发布）<br>
> 最新可下载安装包：**Desktop Windows 1.10.8+36 + Mobile APK 1.10.7+35**。Mobile 新 APK 因旧 Debug 签名私钥缺失而未发布。

此表说明当前源码能力，不代表所有功能都能在这次 Linux 环境中进行实体设备验收。自动化覆盖与阻塞项见 [`docs/FEATURE_TEST_MATRIX.md`](docs/FEATURE_TEST_MATRIX.md)。

| 功能组 | Desktop | Mobile | 协同与边界 |
|---|---|---|---|
| Admin / Staff 登录 | ✅ | ✅ | 账号凭据分别保存在各设备 |
| POS、商品搜索、分类与购物车 | ✅ | ✅ | 两端使用相同销售数据约定 |
| 折扣、收款、找零与赊账 | ✅ | ✅ | 使用整数分币与共同舍入规则 |
| 挂单与取单 | ✅ | ✅ | 保留点击时快照，阻止重复消费 |
| 销售记录、详情与作废 | ✅ | ✅ | Desktop 作废状态通过 LAN 同步 |
| 商品、分类、客户与供应商 | ✅ | ✅ | Desktop 提供更完整的管理能力；删除保留历史关联 |
| 库存、盘点与库存流水 | ✅ | ✅ | Desktop 是配对设备的权威库存主机 |
| 手动进货与撤销 | ✅ | ✅ | Mobile 撤销依赖 Desktop 库存流水确认 |
| OCR 进货 | ⚠️ 结构化导入/接收 | ✅ Android 本地 ML Kit | Mobile 人工确认后发送 Purchase 与独立附件 |
| 进货历史与原始附件 | ✅ 主机存储/读取 | ✅ 拉取/缓存 | 图片失败独立重试，不重放入库操作 |
| 离线销售与待同步队列 | 接收主机 | ✅ 本机创建并重试 | ACK 丢失后按原 operation ID 重试 |
| LAN 配对与同步 | ✅ HTTP / WebSocket 主机 | ✅ 扫码客户端 | 协议 `cnkh-sync:v1`，HTTP 用于权威对账 |
| e-Invoice | ✅ 配置、签名、提交与查询 | ✅ 只读状态镜像 | 凭据与证书只在 Desktop 保存 |
| 电子收据、PDF 与 WhatsApp | ✅ | ✅ | 系统分享入口按平台实现 |
| 热敏收据打印 | ✅ Windows / Bluetooth | ✅ Bluetooth | 实体打印机未在本轮验收 |
| 条码扫描与标签 | ✅ 键盘/队列/打印 | ✅ 相机扫描/标签队列 | 相机和实体打印需设备验收 |
| 数据库备份与恢复 | ✅ 完整备份、校验、回滚 | ⚠️ 本地数据维护有限 | Windows 文件替换流程仅在 Desktop 提供 |
| 用户管理 | ✅ Admin/Staff CRUD | ⚠️ 登录角色与本机权限 | Desktop 管理员工 PIN、状态与最后管理员保护 |
| 培训页面 | ✅ | ✅ | 截图由实际 Flutter 页面生成并检查 |

## 建议搭配

```text
Source candidate: Desktop 1.10.9+37 / Mobile 1.10.9+37 (not published)
Downloadable pair: Desktop Windows 1.10.8+36 / Mobile APK 1.10.7+35
LAN protocol: cnkh-sync:v1
SQLite schema: v10
```

下载说明与 APK 签名限制以 [`README.md`](README.md) 为准。旧版本条目保留在 [`CHANGELOG.md`](CHANGELOG.md)。
