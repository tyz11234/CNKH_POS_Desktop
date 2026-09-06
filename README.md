# 黄金发宝号 · CNKH POS Desktop

用于 Windows 电脑的门店收银与管理系统。Desktop 是店内局域网权威主机，与 [CNKH POS Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK) 配套使用；核心收银、库存与店内同步不依赖云服务器。

技术栈保持 **Flutter / Dart / SQLite**，本次修复没有重写现有架构或改变稳定的收银 UI 逻辑。

> README 最后更新：**2026-09-06**  
> Full Fix 开发分支：`fix/ocr-full-fix-20260906`（基于 `main`）

## 当前正式版本

| 项目 | 当前正式版本 |
| --- | --- |
| Desktop | **0.3.3+6 / `v0.3.3`** |
| 配套 Mobile | **1.9.0+25 / `v1.9.0-mobile`** |
| LAN 协议 | `cnkh-sync:v1` |
| 本地数据库 | Full Fix 后升级为 **schema v8** |

正式 Release 仍以 GitHub Releases 页面为准；Full Fix 在合并前通过 Pull Request CI 验证。

## 2026-09-06 Full Fix

本轮修复把 Desktop 与 Mobile 当成同一套 POS 系统处理，重点不是新增一套平行逻辑，而是在保留现有销售、结账、库存、历史记录、LAN 协议和 UI 风格的前提下补齐缺口。

### 商品、客户、供应商与分类

- Customer / Supplier / Product 支持新增、编辑、软删除。
- 管理列表支持多选、全选/取消全选与批量删除。
- 删除采用 `is_deleted` tombstone，不物理删除历史业务资料。
- Supplier 已补齐 Desktop → Mobile 拉取、Mobile → Desktop mutation、编辑与删除同步。
- Product 删除会同步 tombstone；迟到的旧同步不能把已删除商品恢复成可售状态。
- 已删除商品不会再被商品搜索或条码扫码售卖。
- Category 删除前要求确认；原分类商品转为 Uncategorized / 空分类，不删除商品。

### Windows 原生操作

Desktop 继续使用 Windows 桌面交互：

- 条码图片导出使用 **文件夹选择器**，由用户自行选择输出位置。
- 单个、批量、打印队列导出都会报告成功、跳过与失败数量。
- 支持导出后“打开文件夹”。
- 空队列、商品不存在、无条码、写入失败、权限错误、取消选择目录等不会静默失败。
- Backup / Restore 使用 Windows 文件选择流程，不依赖旧 CNKH POS 工程。

## 条码修复

旧实现通过 SVG + RegExp 解析 `<rect>`，可能生成只有商品名/数字、没有真正条纹的 PNG。

Full Fix 已改为直接使用 barcode package 产生的 `BarcodeBar` 绘制：

- 合法 12/13 位数字使用 EAN-13。
- 其它条码使用 Code128。
- PNG 必须实际包含可扫描的明暗条纹；无有效 bars 会直接报错。
- 自动化测试会解码 PNG 并检查条码区域的暗列、亮列与转换次数，不只检查“PNG 有 bytes”。

## OCR Purchase 架构

OCR 识别只在 Android Mobile 本机运行。Desktop 不重复 OCR，而是接收 Mobile 人工确认后的结构化 Purchase 与 Original Invoice 附件。

```text
Mobile Camera / Gallery
        ↓
Original（原始文件，byte-for-byte 保存）
        ↓
本机 ML Kit OCR（读取 Original）
        ↓
Preview（仅 UI 预览压缩图）
        ↓
OCR Draft + 商品匹配 + 异常检查
        ↓
人工确认
        ↓
Mobile SQLite 原子入库
        ↓
Purchase Outbox ──────────────→ Desktop Purchase mutation
        ↓
Independent Attachment Outbox → Desktop Original Invoice attachment
```

Purchase 与附件是两个独立 operation。图片失败只重试图片，不会重放 Purchase，也不会重复增加库存。

## OCR P0 安全规则

### Conversion

- 必须是 finite 且 `> 0`。
- `NaN`、`Infinity`、0、负数全部阻止。
- Mobile UI 显示字段错误；Repository 边界再次验证。
- 不会无声回退成 `1`。

### Duplicate Invoice

默认按：

```text
Supplier ID + Invoice No
```

检查重复。

- 默认强阻止重复入库。
- Staff 无覆盖权限。
- Admin 只有填写原因并进行第二次确认后才能 Force Commit。
- Override 原因与操作会写入审计，并同步到 Desktop。

### Confirm 幂等

- Mobile 首次点击确认就立即锁定 `_busy`，再进行 revalidate。
- `draft_id` 有数据库唯一幂等保护。
- 重试同一 Draft 返回现有 Purchase，不会重复加库存。
- Desktop 同样使用 operation ID 幂等。

### Safe Reverse

Purchase Reverse 先对**整张进货单**做库存预检，再开始任何 mutation。

如果进货之后已经发生销售、盘点、其它进货或库存调整，会阻止直接撤销，并要求使用库存调整/人工处理。失败时不会出现“部分商品已扣、部分商品没扣”的半撤销状态。

Mobile 与 Desktop 都使用同一安全原则；重复 reverse 不会再次扣库存。

## Original Invoice 附件同步

Mobile 确认 OCR Purchase 后，会为 Original Invoice 创建独立附件 operation：

- 独立 `attachment_id`
- `purchase_id`
- 原始文件名
- SHA-256 `content_hash`
- Base64 文件数据
- 单独 pending / failed / synced 状态

Desktop 接收时：

- 所有 LAN endpoint 均要求有效 Token。
- 对 Original 做 SHA-256 校验。
- 限制异常大附件。
- 相同 `attachment_id` + 相同 hash 重试视为幂等成功。
- 相同 ID 但 hash 不同视为冲突并拒绝。
- Lost ACK 后重试不会重复创建附件，也不会重播 Purchase 库存 mutation。

Desktop 的 Purchase Detail 页面可查看附件资料，并把经过 hash 验证的 Original 导出到用户选择的文件夹；支持中文文件名和同名自动避让。

## 数据库 v8 Migration

Full Fix 把 OCR schema 正式接入 Desktop `onCreate/onUpgrade`：

- 新安装直接建立完整 OCR schema。
- 旧 v7 数据库升级到 v8 时增量迁移。
- 不清空商品、销售、客户、供应商、Purchase、库存流水或 sync outbox。
- 自动化测试会建立真实旧 v7 数据库，写入业务资料/outbox，再用新版打开并确认旧数据仍存在。

OCR 相关表/字段包括 Purchase OCR 元数据、`draft_id`、reverse/audit、Original attachment 等。

## 独立 Backup / Restore

Desktop Backup 不依赖旧 `CNKH_POS_V5`：

- 备份当前 Desktop SQLite。
- 包含商品图片。
- manifest 标识 CNKH Desktop backup format。
- Restore 前验证 ZIP、manifest、SQLite `integrity_check` 和必要表。
- 使用 staging + 当前数据库安全副本。
- 数据库与图片作为一个恢复事务处理。
- 恢复后再次验证；失败会尝试回滚原数据。

无效备份会在替换当前数据库之前被拒绝。

## LAN 同步与幂等

Desktop 是 LAN 权威主机，协议继续为 `cnkh-sync:v1`。

同步覆盖：

- Products / Categories / Customers / Suppliers
- Product images
- Sales / Void
- Purchases / OCR Purchases / Purchase Reverse
- Original Invoice attachments
- Stocktake
- Barcode print queue

可靠性规则：

- Mobile mutation 使用 persistent outbox。
- Desktop ACK 后 Mobile 才删除 outbox。
- Barcode queue 使用逐项 `operation_id` ACK。
- Product / Customer / Supplier 使用稳定 ID 映射。
- `client_sale_id` 是现代销售幂等主键路径。
- Legacy sale 不再只按“时间 + 总额 + 支付方式”误判重复；不同明细的销售会保留。
- 精确 legacy retry 仍通过更强 payload fingerprint 防 Lost-ACK 重复扣库存。
- 删除同步保留 tombstone，防旧操作复活已删除商品。

## Product Image Sync

Desktop Catalog 返回稳定 Product ID 与 `has_image`。

Mobile：

- `has_image=true` 时使用 Token 调用认证图片 endpoint。
- 用稳定远端 ID 映射到本地 Product ID。
- Desktop 本地 `image_path` 不会直接写进 Mobile。
- `has_image=false` 或 endpoint 404 时，Mobile 清除自己的本地图片缓存与 `image_path`。

## Pairing Security

- QR 包含 `iat` / `exp`，默认约 7 分钟过期。
- Mobile 拒绝过期 QR。
- 所有 Desktop LAN API / WebSocket 使用随机 Token 认证。
- Admin 可在“员工账号 / Users”执行 **撤销手机配对**。
- 撤销会旋转 Token、立即清空当前连接并使旧 Token 返回 Unauthorized。
- 随后 Desktop 生成新的配对二维码。
- Mobile 对**同一个 Desktop Host**允许安全接受新 Token；如果 Host 不同，仍要求先同步并备份，防止误切门店。

## 账号与权限

Desktop Users 支持：

- Add
- Edit display name
- ADMIN / STAFF role
- Enable / Disable
- PIN Reset
- 最后一个有效 Admin 保护

Mobile 的 Admin 管理入口仅对 Admin 显示；Staff 不会因为新增 OCR/CRUD 页面绕过管理权限。

## 开发与验证

```bash
git clone https://github.com/tyz11234/CNKH_POS_Desktop.git
cd CNKH_POS_Desktop
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build windows --release
```

Full Fix 的自动化测试重点包括：

- EAN-13 / Code128 实际 bars
- Barcode queue Lost-ACK idempotency
- Desktop v7 → v8 migration preserving business/outbox data
- Backup create / validate / restore / rollback safety
- OCR Purchase / duplicate invoice / Admin override audit
- Purchase Reverse 后续库存变化阻止
- Original attachment SHA-256 / Lost-ACK / localhost HTTP
- 中文附件文件名导出
- Product image authenticated endpoint
- Legacy sale collision safety
- Product tombstone 防复活
- Pairing QR expiry / Token rotation / revoke
- User role / Disable / PIN / last-admin protection

CI 必须同时通过 Desktop tests、Desktop-Mobile integration 与 Windows Release build 后才允许合并 Full Fix。

## 当前不包含

- Windows 摄像头 OCR
- 云 OCR / AI / LLM OCR
- MyInvois / Malaysia e-Invoice
- 无人工确认自动入库
- 云端多门店同步

## 相关入口

- Desktop Releases: https://github.com/tyz11234/CNKH_POS_Desktop/releases
- Mobile Releases: https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases
- Mobile Flutter source: https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/source/main
- Desktop Full Fix PR: https://github.com/tyz11234/CNKH_POS_Desktop/pull/8
- Mobile Full Fix PR: https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/7
