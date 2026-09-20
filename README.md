# 黄金发宝号 · CNKH POS Desktop

用于 Windows 电脑的门店收银与管理系统。Desktop 是店内局域网权威主机，与 [CNKH POS Mobile](https://github.com/tyz11234/CNKH_POS_Mobile_APK) 配套使用；核心收银、库存与店内同步不依赖云服务器。

技术栈保持 **Flutter / Dart / SQLite**，本次修复没有重写现有架构或改变稳定的收银 UI 逻辑。

> README 最后更新：**2026-09-20**。默认源码与发布分支：`main`。

## 当前正式版本

| 项目 | 当前正式版本 |
| --- | --- |
| Desktop | **0.4.1+10 / `v0.4.1`** |
| 配套 Mobile | **1.10.2+30 / `v1.10.2-mobile`** |
| LAN 协议 | `cnkh-sync:v1` |
| 本地数据库 | e-Invoice 升级为 **schema v9** |

## 下载与更新

- [Windows x64 便携包](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v0.4.1/CNKH_POS_Desktop-windows-x64-v0.4.1-10.zip)
- [Release 与 SHA-256 校验文件](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v0.4.1)
- [配套 Android APK](https://github.com/tyz11234/CNKH_POS_Mobile_APK/releases/tag/v1.10.2-mobile)

更新前先备份业务数据并关闭程序。将 ZIP 完整解压到单独目录，运行 `cnkh_pos_desktop.exe`，保留同目录 DLL 和 data 文件夹；此包不含安装向导。

## 2026-09-20 结账与数据保护修复

- 保存结账时禁止关闭或重复点击；成功落库后立即处理购物车，即使页面被程序移除也不会依赖旧页面回调才能完成。
- 找零使用已保存销售的应付和实收金额，避免购物车清空后金额变成零。
- 取单前请先挂单或清空当前购物车；不再直接覆盖当前商品，连续取单也不会重复消费同一挂单。

保持数据库 schema v9、现有金额算法、离线销售及 LAN 协议不变。修复范围、测试和限制见 [BUGFIX_REPORT.md](BUGFIX_REPORT.md)。

## Malaysia e-Invoice / MyInvois

本版本以独立模块加入 e-Invoice，保留原收银、商品、库存界面与离线销售。Desktop 负责调用 MyInvois；Mobile 只通过已有配对连接同步状态，不保存 MyInvois 凭据。

### Desktop 设置与提交

1. 管理员登录，打开 **设置 → e-Invoice Setup**。默认选择 **Sandbox**。
2. 输入公司名称、TIN、BRN、MSIC、业务描述、地址、州代码、电话，以及适用的 SST/TTX 登记资料。无登记时按官方规则填写 `NA`。
3. 填写适用的商品分类、整单税种及税率。售价按含税金额映射，保留原折扣、舍入和实售金额。当前仅支持整单相同税种、税率与分类的 MYR 国内普通发票；混合税率、汇总发票和贷项/退款票请在 MyInvois Portal 处理。
4. 输入对应环境的 Client ID / Client Secret，点击 **保存**，再点 **Test Connection**。此按钮验证 OAuth 连接，不等于发票已获验证。
5. 在 **Submission History** 找到销售，点击 **买方资料 / 生成**。填写真实买方 TIN、登记/身份证明及地址，检查生成的 Invoice JSON。
6. 确认金额和环境后点击 **提交**，再点击 **查询 MyInvois**。`Submitted` 仅代表接收；`Validated` 才代表通过验证。查询同一发票至少间隔 5 秒。
7. 正式使用时切换 **Production**，重新保存正式环境专用凭据。Sandbox 与 Production 的设置及提交记录分别保存。

### 状态与错误处理

| 状态 | 含义及操作 |
| --- | --- |
| Pending | 本地销售尚未提交；补齐资料后由 Desktop 提交 |
| Submitted | MyInvois 已接收，等待查询验证结果 |
| Validated | 官方返回 Valid |
| Rejected | 被拒收或验证失败；核对资料及 Portal 验证结果 |
| needs_review / submitting | 提交结果未知或程序中断；先在 Portal 查找 UUID，再使用“核对 UUID”，不要重提 |
| Cancelled | 官方已确认取消；不会自动退款或改动 POS 库存 |

网络超时、重复提交响应或未知结果会冻结重试，防止重复发票。明确的认证/请求错误允许纠正后重试。取消须填写原因，并由 MyInvois 执行取消期限规则；超期调整、贷项和退款票在 Portal 办理。

### 手机与离线使用

手机继续离线开单。连接 Desktop 后，原 LAN 同步先上传待处理操作并拉取销售；新增 `einvoice_status_v1` 能力通过已认证的 `/api/v1/einvoices` 分页同步状态。手机 **设置 → e-Invoice 状态** 显示本地销售的 Pending / Submitted / Validated / Rejected 等状态，可切换环境。状态目前按分页拉取完整快照，尚未做大量历史记录的压力测试。状态同步失败保留上次结果，不阻断销售同步；旧 Desktop 未声明该能力时仍可正常同步原有业务。

### 数据库与凭据

- Desktop schema **v9**：新增 `e_invoice_settings`、`e_invoice_documents`、`e_invoice_logs`；v8 及更早版本自动执行增量迁移，原业务表数据不变。
- Mobile schema **v9**：新增独立 `e_invoice_status` 镜像表；按电脑地址和环境隔离，不修改 sales。
- Client ID 和 Secret 以 AES-256-GCM 密文保存在 e_invoice_settings，密钥使用操作系统安全存储；OAuth Token 仅驻留内存。日志不记录凭据或完整发票资料。
- 旧 scaffold 中若曾人工保存明文凭据，升级后会清空该明文，需重新输入。公司和提交资料保留。旧备份可能仍含其原始内容，请按敏感资料保管。
- 更换电脑/Windows 用户或丢失 OS 密钥后，需要重新输入凭据。数据库备份保留加密内容，不导出解密密钥。

### CNKH POS Employee Training

右上角及 Settings 原培训入口均提供 11 课：登录与权限、商品销售、收款、退款、库存、手机连接电脑、数据同步、数据备份、e-Invoice 设置、e-Invoice 提交、常见错误处理。

培训使用 `tool/training_capture_test.dart` 实际渲染的应用页面截图；箭头坐标来自真实控件位置，可缩放查看。截图资料为隔离测试数据库内容，配对截图不是门店可用配对码。Mobile 的电脑操作课程使用同版本 Desktop 截图。

### 开发与验证

完整变更、测试结果、构建记录及已知范围见 [EINVOICE_REPORT.md](EINVOICE_REPORT.md)。手机打包使用 Desktop `v0.4.0`；Desktop 联调默认固定已测试 Mobile 源码，手动运行可通过 `mobile_ref` 指定其他版本。

发布 CI 执行 `flutter analyze`、完整 `flutter test`、真实页面截图捕获，再执行 Windows/APK Release 构建。截图先生成到 `assets/training/` 再打包。源码首次运行前也需要生成截图；Mobile 截图流程须准备 `.training_desktop` 源码及其字体，参照 `mobile-ci.yml`。双端真实 HTTP 回归位于 Desktop `integration/`，运行 `flutter test test regression`。

目前 API 自动测试使用 HTTP 模拟响应，覆盖 OAuth 缓存/过期/401、提交成功/失败、重复提交和结果未知。真实 MyInvois Sandbox / Production 验收需要店主提供的已授权凭据，目前未执行真实税务提交。构建成功不等于真实设备、打印机或门店网络已验收。

实现采用官方仍支持的 **Invoice 1.0**；不含 1.1 数字签章。启用正式环境前应核对 LHDNM 后续版本公告。

官方依据：[环境和版本 FAQ](https://sdk.myinvois.hasil.gov.my/faq/)、[Invoice 1.0](https://sdk.myinvois.hasil.gov.my/documents/invoice-v1-0/)、[OAuth](https://sdk.myinvois.hasil.gov.my/api/07-login-as-taxpayer-system/)、[提交](https://sdk.myinvois.hasil.gov.my/einvoicingapi/02-submit-documents/)、[查询](https://sdk.myinvois.hasil.gov.my/einvoicingapi/06-get-submission/)、[取消](https://sdk.myinvois.hasil.gov.my/einvoicingapi/03-cancel-document/)。

## 2026-09-13 同步与恢复修复

- 手机离线开单后作废，且没有中间库存操作时，直接同步作废状态，避免电脑零库存阻塞整条队列；客户等无库存影响的编辑不阻止合并。
- 已经入库的销售遇到确认响应丢失，重试作废只回补一次；存在中间盘点等库存依赖时，仍按原操作顺序同步。
- 手机手动全量对账会等待进货历史同步并执行全量拉取；失败或电脑不支持时显示错误，不再提示全部完成。
- 电脑版恢复备份时，会把已备份的商品图片引用改为当前电脑路径，兼容旧 Windows 用户目录。

两端本轮共新增 13 项回归测试和 2 项真实 HTTP 联调用例；发布流程执行本端完整测试、静态分析和构建。两端组合联调为 8 项。未执行真机升级、打印机和真实门店局域网验收。

## 2026-09-13 修复发布

- 修复单号并发重复、销售同步去重及小票改号后的库存流水关联。
- 修复同一商品多行进货撤销的数量计算，并加强流水缺失、数量不符和系统时间回拨时的撤销保护。
- 修复商品搜索对只读数据库结果排序导致的异常。
- 商品编辑按原始快照合并字段，保留期间更新的库存和成本；库存冲突时拒绝覆盖。
- 商品库存编辑记录流水，手机同步到电脑也保留流水，阻止不安全的旧进货撤销。
- 备份恢复后清理旧文件失败不会再删除已恢复数据库。

本轮基线通过 91 项 Desktop 测试、86 项 Mobile 测试及 8 项双端 HTTP 联调；发布流程会重新执行本端静态分析、测试和构建，通过后上传安装包。未执行实体设备、打印机和真实门店局域网验收。

完整说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)，发布结果以 [GitHub Actions](https://github.com/tyz11234/CNKH_POS_Desktop/actions/workflows/windows-release.yml) 和 Release 附件为准。

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

## 2026-09-06 分页与双端联调补强

本轮针对 Mobile 大数据量分页与 Release 联网问题做配套回归。Desktop 保持现有 Windows UI 与业务逻辑，不复制 Mobile 的分页 UI；主要修正双端测试基线与依赖一致性。

- Desktop / Mobile 联调不再固定到旧 Mobile SHA；工作流会记录并测试明确的双端 ref / SHA。
- Desktop 的 `google_mlkit_text_recognition` 已与当前 Mobile 对齐到 `^0.16.0`，并刷新 `pubspec.lock`，避免最新两端无法共同解析依赖。
- 最新两端组合已通过真实 localhost HTTP 同步与重连回归，包括：离线操作顺序、盘点冲突、服务器恢复重连、进货 Lost-ACK 幂等、PC Void 传播等。
- Mobile 的分页改动不改变 LAN `cnkh-sync:v1` 协议，也不改变 Desktop 权威库存模型。
- 最终合并前仍要求 Desktop `flutter analyze`、`flutter test`、Windows Release build 与双端 integration 全部通过。

真机 Android 局域网测试不由 CI 冒充；若未连接实体 Android 设备，会在验证记录中明确标记未执行。

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

### Purchase History 双端一致性

Desktop 通过经过 Token 认证的 `/api/v1/purchases` 提供结构化 Purchase History，Mobile 会同步供应商、Invoice、费用、商品明细、OCR evidence 与 Reverse 状态。

- Desktop 建立的 Purchase 在 Mobile 标记为 `desktop_sync`，作为**只读历史**显示。
- Mobile 拉取 Desktop Purchase History 只更新历史资料，**不会再次增加库存、修改成本或新增 stock move**。
- Desktop 后续 Reverse 时，Mobile 只镜像 Reverse 状态与原因；库存仍由 Desktop Catalog 的权威结果同步，不会在 Mobile 再扣一次。
- Mobile UI 不为 Desktop-origin Purchase 提供本地 Reverse；Repository/SQLite 还有第二层保护，防止绕过 UI 后误执行本地库存反转。
- Mobile 自己确认并上传的 Purchase 继续保留原本的安全 Reverse / Outbox 幂等逻辑，不会因为 Desktop 回传历史而变成第二张记录。
- `purchases_v1` 使用 cursor-compatible 请求/响应格式；兼容全量 reconciliation 时同样依靠稳定 ID 幂等落库，绝不触发第二次库存 mutation。

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
- Purchases / OCR Purchases / Purchase Reverse / Purchase History
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
- Desktop → Mobile Purchase History localhost HTTP / read-only stock safety
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
- Mobile Flutter source: https://github.com/tyz11234/CNKH_POS_Mobile_APK/tree/main
- Desktop Full Fix PR: https://github.com/tyz11234/CNKH_POS_Desktop/pull/8
- Mobile Full Fix PR: https://github.com/tyz11234/CNKH_POS_Mobile_APK/pull/7
