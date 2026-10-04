# Audit Cycle 2 / Round 2 — Mobile UI and business review

Baseline: Mobile `230f4768ce24b6fa3a0181351246a22b5907a715` in the isolated Cycle 2 checkout. Read the uploaded master README audit/lifecycle/current-feature requirements and current repository README, feature inventory and regression mapping. No applicable AGENTS.md exists. Root controls the paired Desktop reference and full-round gates; database/LAN and eInvoice audits are assigned separately.

This is a fresh scan of the current 18 screen, 5 model, 7 widget and 30 service source files, with delegated service domains identified below. `mobile-source-inventory.txt` records the current file list; `mobile-structure-scan.txt` records routes, controllers, subscriptions, settings and entrypoints. New numeric validation service added by the database auditor is included in discovery. No architecture, schema v10 or `cnkh-sync:v1` change is made.

## Current-feature coverage

| Group | Current review and regression applicability | Result / boundary |
| --- | --- | --- |
| S01 | `main.dart`, login, auth service, AppUser, PIN/role navigation/logout and persisted setup | Reviewed; database credential persistence assigned separately |
| S02 | Cart search/category/paging/version guards, snapshots, add/remove/int +/- quantity, discounts, scan binding | Async scan acceptance fixed; nine actual discount UI cases pass. Mobile has no quantity text editor or `_editQty`; no fictitious double-quantity input test was added |
| S03 | Checkout cash/card/DuitNow/credit, customer/phone ownership, rounding/change, stock recheck, commit lock and route departure | Round 1 nonfinite cash regression retained and rerun; underlying transactions assigned separately |
| S04 | Held-cart click snapshot, timeout, resume, nonempty protection and clearing ownership | Re-read UI/coordinator; persistent repository and sync tests assigned separately |
| S05 | Sales history/search/date/paging/detail/void permission and refused void Snackbar | Focused void reason reproduced early controller disposal and fixed; source/fixture retained sale and explanatory error |
| S06 | Product CRUD, uniqueness/category/barcode, paging/multiselect/soft delete and image staging | Focused name/price Save and Cancel all reproduced disposal failures and now pass; image cancel/reject/save regression rerun, root owns its asynchronous fixture edits |
| S07 | Category create/rename/delete and product picker references | Re-reviewed live Category page and picker; backend mutations assigned separately |
| S08 | Customer CRUD/list/query/page/bulk-delete, selected customer checkout snapshot and eReceipt save-customer form | Re-reviewed live EntitiesPage and widgets; DB/LAN identity mapping assigned separately |
| S09 | Supplier CRUD/paging and alias conversion/name/memory editing | Re-reviewed live EntitiesPage and SupplierAliasesPage; alias positive finite validation retained; repository identity assigned separately |
| S10 | Warn/block stock UI, cart confirmation/recheck, stocktake page and settings | Re-reviewed; stock numeric arithmetic and atomic stock movement tests assigned to DB auditor |
| S11 | Current EnhancedPurchasesPage supplier/product pages, qty/cost, historical rows, OCR/reverse controls | Huge quantity formerly committed saturated money; now rejected without stock movement. Normal manual Save/Cancel focused controller lifecycle fixed and actual DB effects verified |
| S12 | Live Dashboard/Reports/DailyClose and business-date ownership | Huge finite daily-close amount formerly reached persistence; exact-range money parser now rejects. Existing midnight/serialized closing regression rerun |
| S13 | Receipt template flags/width/preview, PDF, share/contacts fallback and owned-cache rules | Re-read template/eReceipt/cache/widgets and mapped existing tests; hardware/system shares unavailable; save-error presentation remains a source candidate pending Mobile reproduction |
| S14 | Barcode label codec, PNG/export/queue, continuous/manual scanner, printer entry | Scanner waits for returned cart acceptance before count/feedback; verified asynchronous false and true separately |
| S15 | Admin-only QR/settings, stock/hold/scan-feedback/images/BT/cache/reset | Re-reviewed UI; root owns QR import safety, DB auditor owns reset/outbox safety |
| S16 | Pair routes/configuration, offline/error UI, force-reconcile error display | Re-reviewed UI; full LAN token/protocol authority assigned separately |
| S17 | Offline business UI, pending state and explicit review/retry acknowledgements | Re-reviewed UI; outbox/ACK/retry persistence assigned separately |
| S18 | eInvoice read-only status/history/environment/error display | Re-reviewed UI; no external tax request performed; backend assigned separately |
| S19 | Repository error boundaries, data snapshots and state ownership visible in current forms | UI reviewed; schema/migrations/SQL/transactions assigned separately |
| M01 | Scanner platform detection, controller lifecycle, manual fallback, pairing distinction/debounce and feedback | Async callback result bug fixed; real Android camera/permission recovery unavailable |
| M02 | ML Kit local OCR recognition/close, source original and preview preservation, cancel/failure cleanup | Re-read native wrappers/file service; real device recognition/camera unavailable |
| M03 | Parser/matcher/spec confidence/aliases, drafts, qty/conversion/cost/fees/supplier edits, warning/commit control | Parser huge money saturation fixed. Actual saved-draft editing reproduced quantity multiplication and base-cost division failures; UI and validator now block invalid money before mutation/commit |
| M04 | Read-only local/remote purchase history, original attachment display, reversal dialogs/error flow | UI re-reviewed; history/LAN/reversal persistence assigned separately |
| M05 | Pair configuration, main connect/disconnect lifecycle and cache UI | UI re-reviewed; host/token/reconnect/image queue backend assigned separately |
| M06 | Offline checkout, held-cart exact snapshot and pending-operation UX | UI re-reviewed; persistence assigned separately |
| M07 | Read-only eInvoice page and sync error presentation | UI reviewed; backend assigned separately |
| M08 | Local product image picks/stages/cache setting refresh and delayed picker completion | Round 1 three file-safety tests rerun; host-isolated queue assigned separately |
| M09 | BT capability/address/enabled/connect/write errors and ESC/POS width/CJK raster | Re-read service/settings; no physical printer/Android permission acceptance claim |
| M10 | Navigation/layout/tabs/refresh and all current training entrypoints | Re-reviewed screen boundaries and mapped existing layout tests; training/build assets/gates assigned to root |

The obsolete legacy AdminHub/Entities/Purchases classes remain distinguished from the active AdminHub routes. DailyClose, Dashboard, Reports, Stocktake and Categories exported by `admin_hub_legacy.dart` are active and included. No obsolete unreachable purchase form was treated as an additional current feature.

## Confirmed defects and minimal fixes

Three defect groups below consolidate multiple affected entrypoints rather than counting each input as a new bug.

1. **Scanner reports acceptance before the asynchronous cart stock decision.** `barcode_scan_screen.dart:20,102,196` originally invoked a void callback and immediately counted/played feedback. Actual manual fallback selection with a delayed cart callback read `scan_feedback` while the decision was unresolved, even when it later returned false. `mobile-candidates-before.log` records both failures. The callback now returns `Future<bool>`, `cart_screen.dart:362` returns `_add`'s real result, and scanner awaits true before feedback/count. `scanner_cart_acceptance_regression_test.dart` has delayed false/true cases; it observes the scanner-specific repository feedback read, avoiding Flutter button sound false positives.

2. **Financial boundaries allow saturated or overflowing amounts.** DailyClose `admin_hub_legacy.dart:697`, manual purchase `enhanced_purchases_page.dart:429` and invoice parser `purchase_invoice_parser.dart:252` formerly rounded huge finite values to `9223372036854775807`. Baseline real SQLite widget evidence in `mobile-purchase-total-before.log` records an inserted huge purchase and changed stock. DailyClose persisted once with `1e100`; parser accepted a 101-digit number. These entries now use exact supported cents (absolute value at most 9007199254740991) and reject nonfinite/scaled overflow before persistence. OCR line editor also accepted quantity `1e308`/`1e100` and conversion `1e-308`: validation's subtotal rounding or rendered base cost rounding crashed, or validation returned only warnings. `mobile-ocr-quantity-before-verified.log` records six actual failures, including real saved-draft UI edits. `purchase_ocr.dart:68,73` exposes calculation validity, `purchase_validation_service.dart:65` adds blocking errors and avoids unsafe rounding, and `purchase_ocr_screen.dart:288,294,998` rejects edits and safely displays invalid historic base costs. Permanent tests verify draft/stock/purchases unchanged and direct repository commit rejected. Normal parser grouping, OCR matching/history/conversion/atomic commit/reverse and cost snapshots remain covered by existing regressions.

3. **Focused dialog fields outlive their disposed controllers.** `showDialog`'s pop future resolves while its exit animation still retains focused TextFields. Manual quantity normal Save/Cancel, product focused name/price Save/Cancel, and focused sale-void reason reproducibly threw `TextEditingController was used after being disposed`. Baselines are `mobile-purchase-dialog-before.log`, `mobile-product-dialog-before.log` and `mobile-sale-dialog-before.log`. `enhanced_purchases_page.dart:254,453`, `products_admin.dart:184,340` and `sales_list_screen.dart:127,142` now await `DialogRoute.completed` before controller disposal; no fixed sleep is used. Actual purchase Save adds one row and stock 5→6, Cancel leaves no row/stock 5. Product Save updates only the edited field; Cancel preserves the product. Void rejection still displays the protected-sale reason and retains the sale.

## Regression evidence

- Before confirmed failures: `mobile-candidates-before.log`, `mobile-purchase-total-before.log`, `mobile-purchase-dialog-before.log`, `mobile-product-dialog-before.log`, `mobile-sale-dialog-before.log`, `mobile-ocr-quantity-before-verified.log`.
- The initial `mobile-ocr-quantity-before.log` includes an inadequate default-size fixture obscured by the fixed footer; it is retained for traceability and is superseded by the corrected phone-size verified baseline. MissingPlugin close exceptions in failed aborted widgets are fixture teardown consequences, not product defects.
- New permanent files: scanner acceptance (2), purchase/daily/parser/reorder boundary (6), product focused dialog lifecycle (4), actual cart discount inputs (9), OCR arithmetic/draft/commit boundary (6). The existing refused-void test is strengthened by focused reason input. No existing test or assertion was removed.
- After intermediate checks: dialog lifecycle **5/5 PASS**, purchase boundaries **6/6 PASS**, actual cart discount input **9/9 PASS**, OCR plus existing OCR tests **23/23 PASS**. Final combined affected-domain results are recorded in `mobile-new-bugs-after.log`.
- Initial final combined check: **53 PASS / 3 FAIL**, with all three failures in the root-owned image fixture. Its condition polling pumps frames without advancing the fake animation clock, so the new route-completion wait cannot finish. Root has been notified to advance test-frame time within the existing observable-condition polling; this is not a native file-safety failure. Do not claim full PASS until the adjusted fixture and root gates pass.
- Root runs complete analyze/test, dual-end integration, training and release gates after source freeze. Targeted PASS is not presented as a complete Audit Round PASS.

## Rejected candidates and runtime boundaries

- Reorder NaN: actual SQLite mutation already rejects and rolls back; persisted threshold remains 2. The permanent real-DB assertion passes before and after. No fix or additional bug count was claimed.
- Mobile cart quantity is an integer controlled by add/+/- and gross cents uses integer multiplication. There is no double text-entry route; NaN/Infinity/1e100 were tested in the actual discount inputs instead. `1e100` percent is safely capped to 100%; nonfinite percentages and invalid RM inputs do not alter money or write audit rows.
- Scanner manual search sheet currently does not set `_handling` until an item is picked. A real Android camera stream might continue detecting beneath the sheet. Linux uses unsupported-platform fallback, and the modal blocks ordinary repeated-button taps; no actual simultaneous-camera duplicate was reproduced. Retain as an Android runtime/Round 3 candidate; no mechanical Desktop alignment or new bug claim.
- Supplier alias focused dialog disposal and Mobile receipt-template save-error feedback remain source candidates for explicit future repro; no unsupported bug count or claim of tested recovery is made.
- Android camera/OCR/BT/system share permission denial/recovery and physical printer are unavailable. Platform stubs and code review do not equal hardware acceptance.
- OCR uses a finite 5000-product matching directory; more than 5000 products and concurrent supplier/line-edit completion remain documented boundaries.
- Root-owned image fixture, pubspec/lock, paired reference, docs and other auditors' DB/LAN services were preserved. Original workspace and user data remain untouched.
