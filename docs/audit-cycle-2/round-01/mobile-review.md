# Audit Cycle 2 / Round 1 — Mobile UI and business review

Scope: isolated latest-main Mobile checkout at `CNKH_POS_Mobile_APK`, version `1.10.9+37`. Read uploaded master README including full-round, current-feature discovery, genuine-bug, regression-preservation and clean-round definitions; read current README/CHANGELOG/RELEASE_NOTES/pubspec/feature inventory. No repository or ancestor AGENTS.md exists. Old workspace is preserved.

All 18 current screen source files, 5 model files and 7 widget files were scanned, including live classes exported from `admin_hub_legacy.dart`. Existing obsolete legacy AdminHub/Entities/Purchases classes are distinguished from the classes the current AdminHub actually opens. The entrypoint/controller/settings scan is recorded in `mobile-ui-entrypoints.txt`.

## Feature coverage

| Group | Review performed | Result / delegated backend |
| --- | --- | --- |
| S01 | Initialization, login setup/confirmation, PIN roles, logout, Admin navigation and staff controls; `main.dart`, `login_screen.dart`, `auth_service.dart`, `app_user.dart` | Reviewed; DB credential/SQL audit delegated |
| S02 | Category/search/pagination request ordering, add/adjust/remove, cart snapshots, line and order discounts, refresh without repricing | Fixed invalid numerical input; scanner asynchronous callback remains candidate pending specific reproduction |
| S03 | Cash/card/DuitNow/credit, customer selection and phone ownership, stock recheck, duplicate confirm, route departure during commit, money/change widgets | Four invalid cash-input widget reproductions fail before fix and pass after |
| S04 | Click-time hold snapshot, unchanged-cart clearing, timeout, resume consumption and nonempty-cart protection | Reviewed `held_cart_coordinator.dart` and main UI; DB persistence audited separately |
| S05 | Sales date/search/pagination, details, void controls and receipt entry | Refused void reproduced and now shows UI error; date SQL handled by DB agent |
| S06 | Product add/edit/delete/multiselect, price/SKU/barcode/category, image picking and cancellation, pagination | Cancelled image edit overwrote old file; staged images preserve old bytes on cancel and rejected save |
| S07 | Category create/rename/delete, picker, existing-product references | Reviewed UI; repository mutation audit delegated |
| S08 | Customer create/edit/delete/batch delete/pagination, phone checkout snapshot, eReceipt save-customer flow | Reviewed; immutable mappings/SQL delegated |
| S09 | Supplier CRUD/pagination and alias edit/delete validation | Reviewed; alias finite positive conversion is enforced |
| S10 | Stock gate warn/block, cart recheck, stocktake form and pagination, policy settings | Reviewed UI; stock transactions/authority delegated |
| S11 | Manual purchase paged supplier/product selectors, quantity/cost validation, historical read-only details, OCR reversal confirmation | Reviewed; reverse plan and state/persistence delegated |
| S12 | Live Dashboard/Reports/DailyClose, date ownership, input/save history | Reviewed; overflow and DB error boundaries remain explicitly reviewed candidates beyond the confirmed cash error |
| S13 | Template load/save/flags/width, preview, CJK multi-page PDF, contacts denial fallback, share flow and owned-cache preservation | Reviewed code and mapped existing receipt/PDF/cache tests; physical sharing not available |
| S14 | Barcode labels codec/render/export/multiqueue, continuous/manual scan and printer entry | Reviewed; scanner success feedback before asynchronous cart acceptance is a pending candidate, not counted as confirmed bug |
| S15 | QR edit Admin check, stock/hold/feedback/image/BT/cache settings, receipt template and reset confirmation | Reviewed; root owns independent QR import fix and tests |
| S16 | Pair scan route/configuration, online/error UI and force-reconcile error propagation | UI reviewed; entire LAN protocol audit delegated |
| S17 | Offline business UI, preserved pending review controls, explicit retry acknowledgement | UI reviewed; outbox/ACK/retry engine delegated |
| S18 | Read-only environment switch/status/error page | UI reviewed; tax status backend delegated to eInvoice agent |
| S19 | UI-facing database failures and repository state ownership | Backend/schema/migration audit delegated |
| M01 | Android scanner initialization/error fallback, pairing-only mode, debounce, manual lookup, feedback and controller disposal | Static review performed; Android camera hardware runtime unavailable |
| M02 | ML Kit local OCR source and recognizer close, original/preview preservation, failure cleanup | Reviewed; physical image-picker/camera/ML Kit acceptance unavailable |
| M03 | Parser, matching/confidence/spec tokens, alias memory, drafts and line/fee/supplier edits, warnings, duplicate invoice override, commit safeguards | Reviewed current OCR service/model/UI logic and existing regression mapping |
| M04 | Mobile/remote read-only purchase details, sync error presentation and reversal flow | UI reviewed; history/outbox/coordinator engine delegated |
| M05 | Pair config route and main lifecycle/disconnect callbacks | UI reviewed; token/host/reconnect backend delegated |
| M06 | Offline checkout finalization and exact click-time held cart | UI reviewed; persistent operations delegated |
| M07 | Environment and eInvoice history UI | Reviewed; service backend delegated |
| M08 | Local product image file store, asynchronously refreshed image setting, cache lookup and lifecycle | Reviewed; host-isolated image queue/LAN transfer delegated |
| M09 | Android capability check, enabled/address/read/connect/write failure handling, ESC/POS CJK raster/width bands | Reviewed; physical Bluetooth transport acceptance unavailable |
| M10 | Phone navigation, retained tabs/refresh, screen layouts and 11 training routes/assets | Reviewed source; training asset source/build audit delegated |

## Confirmed bugs fixed

1. **Invalid/overflow cash inputs crash checkout.** Original `checkout_screen.dart:111` parses nonfinite `double` values and calls `rmToCents`; `build` parses cash every rebuild. Paste `NaN`, `Infinity`, `1e309` or `1e308` into Cash tendered. All four failed with `Unsupported operation: Infinity or NaN toInt`. Added finite/scaled-range parser (`lib/models/money.dart:6`), safe visual fallback and explicit confirmation rejection. Applied validation to line/order discount and product price entry too. No invalid value is persisted. `test/checkout_money_input_regression_test.dart` exercises actual CheckoutScreen and verifies zero persistence calls.
2. **Canceling a product image edit changes the saved image.** Original product edit copies picked bytes immediately onto `existing.id.ext`, so Cancel leaves the DB path unchanged but old file overwritten. An actual picker/platform/file fixture detects original 2x2 PNG being replaced by 3x3 PNG. New `products_admin.dart:177` stages separate owned files, retains the selected file only after repository commit, removes uncommitted files, and cleans up a picker operation that completes after dialog departure. `test/product_image_edit_regression_test.dart` verifies cancel, repository rejection and successful save; original bytes remain unchanged in all three cases. Existing image remains readable after conflict.
3. **Refused sale void is an unhandled error with no user explanation.** Existing `_void` awaits `repo.voidSale` without catch. When business protection rejects it, the sale remains intact but UI fails without explaining why. `sales_list_screen.dart:125` now shows the rejection through existing Snackbar; controller is disposed and mounted is checked. `test/sale_void_error_regression_test.dart` verifies rejection, visible reason and retained sale.

## Execution evidence

Before: `mobile-new-bugs-before.log` (four cash failures), `mobile-image-before.log` (original bytes overwritten), `mobile-void-before.log` (StateError and missing error Snackbar).

After: `mobile-new-bugs-after.log`, **19/19 PASS** across the three new regression files and existing money/cart calculation and product edit safety tests. `git diff --check` PASS. Root runs full analyze/test and related integration/build gates for this Round; this report does not substitute targeted tests for the full-round requirement.

## Boundaries and pending candidates

- Android camera/OCR/Bluetooth and system share-sheet hardware: no Android device in Linux environment. Static review and existing platform-stub tests performed; actual permission denial/recovery/printing must be executed on device. Do not report hardware acceptance PASS.
- Invalid date/DB query and LAN authority are owned by DB/LAN auditor; real tax environment/API by eInvoice auditor.
- Scanner void callback reports/counts success before async `_add` returns. It needs a dedicated accepted/rejected callback reproduction before modifying; not counted as a bug in this report.
- OCR dialogs use a finite 5000-product directory snapshot. More than 5000 products and concurrent supplier/line edit requests are visible boundaries; no unsupported assertion of correctness is made for these cases.
- Money/helper and image fixes keep schema v10 and `cnkh-sync:v1`; no app version bump is made merely for audit.
