# CNKH LAN Sync v1

> 当前已发布组合：**Desktop v1.10.5+33 + Mobile v1.10.5+33**
>
> 修复源码：**1.10.6+34 / schema v10**，尚未完成 Flutter 回归或发布，见 [FIX_VERIFICATION.md](FIX_VERIFICATION.md)。
>
> 最后更新：**2026-09-30**

CNKH POS 使用 **local-first / no-cloud** 架构。Desktop 是店内局域网权威主机，Mobile 通过同一个 Wi-Fi / LAN 与 Desktop 直接同步。

## 配对二维码

Desktop 打开 LAN / 扫码配对后显示二维码，Mobile 点击扫码配对读取。

格式：

```text
cnkh-sync:v1|{"baseUrl":"http://192.168.0.10:8787","token":"...","name":"CNKH-PC"}
```

字段：

- Prefix：`cnkh-sync:v1|`
- `baseUrl`：Desktop 当前局域网地址，默认端口 `8787`
- `token`：Desktop 持久化 LAN Token
- `name`：主机显示名称

Desktop 监听：

```text
0.0.0.0:8787
```

Mobile 配对成功后会保存地址与 Token，App 重启后自动尝试重连。

## 身份验证

HTTP：

```text
X-CNKH-Token: <token>
```

WebSocket 也可通过查询参数携带 token。

## 实时与对账

| 通道 | 路径 | 用途 |
|---|---|---|
| WebSocket | `/api/v1/ws` | 实时变更提示 |
| Event poll | `/api/v1/events/poll` | WebSocket 不可用时的轮询补偿 |
| Notify | `POST /api/v1/notify` | 设备主动通知有本地变更 |
| HTTP reconcile | REST endpoints | 定时 / 重连后的权威对账 |

Mobile 不把 WebSocket 当成唯一数据来源；断线、重连或事件遗漏时会通过 HTTP 重新对账。

## 主要 REST API

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/health` | 主机健康检查与协议信息 |
| GET | `/api/v1/products?since=` | 商品 / 库存同步 |
| GET | `/api/v1/customers?since=` | 客户同步 |
| GET | `/api/v1/categories?since=` | 分类同步 |
| GET | `/api/v1/purchases?since=` | 进货历史同步 |
| GET | `/api/v1/sales?since=` | 销售同步 |
| POST | `/api/v1/sales` | Mobile 上传本地 / 离线销售 |
| POST | `/api/v1/notify` | 同步事件通知 |
| GET | `/api/v1/events/poll` | 事件轮询 |

部分管理流程还会使用分类 / 条码队列等内部 API。

## 数据一致性规则

- Desktop 是商品、库存、分类、客户与已汇总销售的局域网权威来源。
- Mobile 可在离线时继续开单，并把待同步销售持久化到本地 outbox。
- 恢复连接后 Mobile 重试上传，再从 Desktop 做权威对账。
- Mobile 销售使用稳定的 client sale identity，Desktop 以幂等方式导入，避免网络重试造成重复记账。
- Desktop 销售 / 进货 / 盘点后的库存变化会回传 Mobile。
- Desktop 作废销售状态会回传 Mobile。
- Mobile 支持强制全量对账。

## 当前实现位置

### 修复源码的可选能力

- `stock_moves_v1`：`GET /api/v1/stock-moves?since=` 导出稳定 ID 的库存活动，按流水插入顺序推进游标；销售后作废仍保留两笔活动。主机游标回退时全量替换主机来源标记，不删除本机业务流水。
- `mutation_rejections_v1`：`POST /api/v1/mutations` 对明确事务拒绝的进货撤销返回 `rejected_operation`。客户端校验操作 ID 后保留请求，核实并补偿旧版本已执行的本机撤销，再允许后续业务同步。超时、无结构错误或丢失 ACK 保持原请求顺序等待确认。
- Mobile 配对前事务入队，首次同步先上传。已有 SKU/条码按唯一身份关联；已有 Desktop 的库存/成本基线不会被手机缓存覆盖。字段冲突与无法核实的旧库存基线保留为待处理错误，不丢弃业务。
- 完整目录是权威快照；只停用已映射但快照缺失的资料。待确认库存业务先上传，失败时不覆盖本机库存。无效快照不推进游标。
- `einvoice_status_v1` 的 `status_version=2` 支持最终 `invalid`，只镜像最新尝试；未声明新版状态的客户端继续收到旧版认识的 `rejected` 表示。
- 没有完整库存流水能力的旧 Desktop 仍可同步其他 v1 业务；Mobile 撤销会明确提示先升级 Desktop，保留本机资料与队列。

协议前缀与认证方式不变。

Desktop：

```text
lib/services/lan_pairing_host.dart
lib/services/lan_sync.dart
lib/services/pos_repository.dart
lib/screens/barcode_scan_screen.dart
```

Mobile：

```text
lib/services/lan_sync.dart
lib/services/pos_repository.dart
lib/screens/qr_capture_screen.dart
```

## Windows 防火墙

如果二维码内容正确但手机无法连接：

1. 确认手机与 PC 在同一个 Wi-Fi / LAN。
2. 确认 Windows 防火墙允许 CNKH POS Desktop / TCP 8787 在私人网络通信。
3. 避免使用访客 Wi-Fi、AP isolation 或会阻断局域网设备互访的网络。
4. 如果电脑同时有 VPN / 虚拟网卡，确认二维码显示的是实际局域网 IP。

## 建议实机验证

1. Desktop 显示二维码，Mobile 扫描并连接。
2. Mobile 开一单，Desktop 出现销售并更新库存。
3. Desktop 开一单，Mobile 收到销售 / 库存变化。
4. 关闭 Wi-Fi 后 Mobile 开一单，再恢复网络，确认只同步一次。
5. 重启两端，确认自动重连。
6. 作废一笔销售，确认状态能同步。
