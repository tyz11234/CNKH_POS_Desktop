# Desktop — Audit Cycle 2 Round 1 / Global Round 7

## Scope and dynamic inventory

Read the uploaded master README and current feature inventory/matrix. No AGENTS.md exists in the cycle checkout. The fresh Desktop checkout is under `/workspace/cnkh-audit-cycle-2/CNKH_POS_Desktop`; the original workspace was not edited.

Reviewed all 17 screen files (including e-Invoice route entry; tax implementation is covered by the tax reviewer), 4 models, 6 widgets, main/root/Desktop shell, and the top-level non-LAN services. Exact reviewed source paths, line counts and SHA-256 are in `desktop/source-inventory.json`. Existing feature IDs covered by this assignment: S01–S15, S19, D02–D05, D08, D10–D13 (25 groups). LAN/API/schema and MyInvois deep review are complementary assignments, not silent skips.

| Function surface | Lifecycle and data checks performed |
| --- | --- |
| Startup/login/session/PIN/employees | First-use PIN confirmation, PBKDF2 credentials, failed login lockout, logout, role-derived navigation, create/edit/disable and last valid Admin, PIN cancel |
| POS/catalog/cart | Search/category/reload/pagination generation, duplicate IDs, add/remove/quantity, stock warn/block, item/order discount, finite and malformed inputs, live-cart ownership |
| Checkout/credit/held orders | Cash/card/DuitNow/credit, deposit and customer/phone snapshots, rounding/change, busy/commit guards, route exit, hold immutable snapshot, resume conflict and deleted products |
| Sales/history/receipts/reports/daily close | Date and search filtering, void refusal and rollback, original stock ledger, payment/COGS/cost snapshots, business-day ownership and authoritative close totals |
| Products/categories/customers/suppliers | Create/edit/delete, preserved histories, stale editor and stock conflicts, batch selection and pagination, rename/delete category, supplier identity refresh |
| Purchases/manual/QR/OCR/import | Supplier selection, parser/resolve, same-product lines and unit costs, atomic create/retry, metadata edit, attachment hash/export and safe reversal preflight |
| Images/QR/settings/cache/maintenance | Draft-vs-persisted file ownership, picker/cancel/error/disposal, settings defaults and persist paths, cache ownership/TTL, reset confirmation and business data preservation |
| Backup/restore | Schema/integrity validation, staged database/images, path rebasing, rollback, polling pause/drain, host restart and cleanup after validation |
| Printing/export/share/training | ESC/POS raster width and cleanup, PDF long/CJK receipt, barcode PNG/export/failure reporting, native WhatsApp fallback, About package version and training resources/routes |

## Confirmed new bugs and fixes

Each item has a failing regression against the pre-fix source and passes after the minimal fix. Logs are under `desktop/`.

1. **Sales end-day filter loses the final fractional second** — `lib/screens/sales_list_screen.dart:89`. Selecting a sale date excluded `23:59:59.999999`. The upper bound is now next-day midnight, exclusive. `sales-before.log`; permanent test `sales_list_boundary_error_test.dart`.
2. **Rejected sale void escapes without a UI error** — same file, `_void` around line 127. An e-Invoice void guard failure raised an unhandled StateError and gave no reason. It now keeps the sale and shows the existing snackbar error mechanism. Second regression in the same test/log.
3. **Appending another unit cost changes the earlier purchase quantity's cost** — `lib/screens/admin/purchase_create_screen.dart`, `_mergeLines`. Importing qty 1/cost 100 followed by qty 1/cost 200 produced 400 cents instead of 300. Rows merge only at the same unit cost; different prices retain separate rows through actual commit. `purchase-price-before.log`; permanent widget/commit regression `purchase_line_price_retention_test.dart`.
4. **Picking a product replacement image changes persisted bytes before Save** — `lib/screens/admin/products_admin.dart`, `_edit`. Cancel and rejected database save both left the old filename containing new bytes. Image selections now write independent draft revisions, persist only after successful product save, and delete uncommitted drafts. The original revision remains intact. Async picker completion checks route/dialog ownership. `product-image-before.log`; three permanent regressions in `product_image_editor_safety_test.dart`.
5. **Non-finite pasted amounts crash cash checkout** — `lib/models/money.dart`, `lib/screens/checkout_screen.dart`. NaN, Infinity and 1e309 reached `.round()` while rebuilding the payment screen. A shared checked parser rejects non-finite/scaled-overflow values and values beyond `9007199254740991` exact cents; checkout refuses invalid input before persistence. Cart discount, product money/stock, purchase line and daily-close entries also use validation. Percentages at or over 100 are capped before multiplication. `money-before.log`; three permanent actual-checkout regressions in `nonfinite_money_entry_test.dart`.

## Verification

Targeted permanent regressions: **9/9 PASS**. See `desktop/new-regressions-after.log`. `git diff --check` passes. Full analyze, pre-existing Desktop suite, both-repo integration, training/build/version and release gates are run by the root coordinator after all assignments finish. This report does not substitute static review for those gates.

The new purchase test waits for the observable supplier dropdown and clears import snackbars before pressing the bottom submit button. A transient test failure was due to the snackbar intercepting the synthetic tap, not a purchase product failure; the test now exercises actual commit successfully.

## Explicit acceptance limits

- Windows native GUI, USB/Bluetooth printer hardware, camera permission/sensor, native picker/clipboard/WhatsApp installed application, and Android package upgrade cannot be accepted by this Linux widget environment. Static platform handling plus mock/channel and bytes/filesystem tests were reviewed; target-device acceptance is still required.
- Physical Wi-Fi/firewall and real MyInvois/Sandbox credentials/certificates are not available. LAN and tax reviewers supply automated localhost/mock coverage separately.
- UserAdminService create/list/update lack their own role check, while reachable shell menus are Admin-filtered and PIN writing enforces Admin. No actual STAFF UI path was reproduced in this round, so this remains a candidate for the next permissions round and is not falsely counted as a reproduced product bug.
- Receipt/template/cache errors on filesystem or database failure remain candidates for targeted lifecycle review; existing rollback and ownership regressions cover data preservation. No additional product issue is claimed without a failing reproduction.

**This round is not Clean**: five new confirmed bug groups were fixed. The two-clean-round counter must restart after the fixes.
