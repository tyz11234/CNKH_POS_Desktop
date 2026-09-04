# Mobile ↔ PC feature parity checklist

Honest status after 1.4.0 batch. ✅ = equivalent flow on mobile · ⚠️ = partial · ❌ = PC-only by design · ➖ = N/A

| Area | PC | Mobile | Status | Notes |
|------|----|--------|--------|-------|
| Login Admin/Staff | ✅ | ✅ | ✅ | Demo users |
| POS search add | ✅ | ✅ | ✅ | |
| Category filter chips | ✅ (location/category) | ✅ | ✅ | 全部 + categories |
| Continuous barcode scan | ⚠️ USB scanner | ✅ camera continuous | ✅ | Phone camera |
| Cart qty / discounts | ✅ | ✅ | ✅ | Line + order |
| Hold / resume | ✅ | ✅ | ✅ | Timeout reminder |
| Checkout Cash/Card/DuitNow/Credit | ✅ | ✅ | ✅ | Rounding + credit deposit |
| DuitNow QR | ✅ | ✅ | ✅ | Admin edit / Staff RO |
| E-receipt PDF / WhatsApp | ✅ | ✅ | ✅ | Temp PDF + share |
| Receipt print | ✅ Windows/USB | ⚠️ optional BT | ⚠️ | BT off by default |
| LAN sync + QR pair | ✅ | ✅ | ✅ | WS + poll |
| Low-stock push | ✅ EventHub | ✅ snackbar | ✅ | |
| Products CRUD | ✅ | ✅ | ✅ | |
| Auto/manual barcode | ✅ | ✅ | ✅ | |
| Barcode print labels | ✅ hardware | ⚠️ queue + PNG export | ⚠️ | PC owns paper |
| Batch barcode export images | ➖ | ✅ | ✅ | bars + full name |
| Product images | ⚠️ files dir + API | ✅ opt-in | ✅ | |
| Category management | ✅ | ✅ | ✅ | Picker-only on product |
| Sales list / void | ✅ | ✅ | ✅ | |
| Customers / Suppliers | ✅ | ✅ | ✅ | Lite CRUD |
| Purchases | ✅ | ✅ | ✅ | Simplified |
| Stocktake | ✅ | ✅ | ✅ | |
| Users | ✅ | ⚠️ demo list | ⚠️ | No password mgmt on phone |
| Reports | ✅ | ✅ | ✅ | Today/payment totals |
| Daily close | ✅ | ✅ | ✅ | |
| Settings receipt/QR/LAN | ✅ | ✅ | ✅ | |
| Discount audit | ✅ | ✅ | ✅ | |
| Maintenance clear demo | ✅ | ✅ | ✅ | |
| Barcode label **hardware** | ✅ | ❌ | ❌ | PC-only |
| Windows backup/restore binary | ✅ | ❌ | ❌ | PC-only |

**Parity claim:** Staff/Admin day-to-day flows are covered on mobile except true PC-only hardware/backup. Users password admin and advanced purchase payment states remain lighter on phone.
