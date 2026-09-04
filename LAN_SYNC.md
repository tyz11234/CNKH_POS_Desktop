# CNKH LAN Sync (no cloud) — near-real-time

## Pairing QR (primary UX)

After **同步/配对** starts the server, phone taps AppBar **扫码配对**.

### Payload format

```
cnkh-sync:v1|{"baseUrl":"http://192.168.0.10:8787","token":"abc123","name":"CNKH-PC"}
```

- Prefix: `cnkh-sync:v1|`
- JSON keys: `baseUrl` (required), `token` (optional shared secret), `name` (label)
- Human-readable IP:PORT also shown under the QR on PC

Manual IP entry remains under Settings → LAN Sync → **高级** (advanced fallback).

## Real-time

| Channel | Path | Role |
|---------|------|------|
| WebSocket | `/api/v1/ws` | Preferred push (`{"type":"sale",...}`) |
| SSE | `/api/v1/events` | Alternate stream |
| Poll | `/api/v1/events/poll?after=` + sales pull every ~5s | Fallback |
| Notify | `POST /api/v1/notify` | PC/phone announce local sale |

- Phone checkout → `pushSales` + notify → PC EventHub → Admin sales refresh / Staff stock refresh.
- PC checkout → `publish_sync_event("sale")` → phone WS/poll → `pullSales` + `refreshToken`.

## REST (auth: `X-CNKH-Token` or `?token=`)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/health` | Ping (+ pairing hint) |
| GET | `/api/v1/products?since=` | Pull catalog |
| GET | `/api/v1/customers?since=` | Pull customers |
| GET | `/api/v1/sales?since=` | Pull sales |
| POST | `/api/v1/sales` | Push phone sales |

Default port **8787**, bind `0.0.0.0`.

## Implementation

- PC: `cnkh_pos/services/lan_sync_server.py`, `ui/dialogs/sync_pair_dialog.py`, top-bar **同步/配对**
- Mobile: `lib/services/lan_sync.dart` (`LanLiveSync`), AppBar **扫码配对**
