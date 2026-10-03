# CNKH POS Desktop change log

## 1.10.9+37 — 2026-10-03

- **B001 (Both):** Read the installed Version and Build Number in About instead of maintaining duplicate Dart constants.
- **B003 (Both CI):** Pin paired repository refs to the companion 1.10.9+37 source commits.
- Completed six audit rounds; Rounds 5 and 6 were clean. Final regression passed Mobile 147/147, Desktop 151/151, and paired integration 29/29.
- SQLite schema v10 and `cnkh-sync:v1` remain unchanged.

## 1.10.8+36 — released 2026-10-03

- **B01** Clear a previous customer-directory phone on customer change/cancel while preserving a manually entered temporary number for the saved sale and eReceipt recipient.
- **B03** Validate required current tables/columns and POS queries, migrate supported old backups through the application upgrade path, and keep rollback DB/images until the restored production path reopens and validates.
- **B06** Persist a click-time held-cart snapshot, guard duplicate submits, and clear only an unchanged cart after success.
- **B07 / B11** Add SQL-stable product ordering and progressive search/pagination to product admin, stocktake, purchase selection, compact/full cart, and audit history.
- **B08** Return a structured sale-void business refusal while tax state needs review; keep the operation idempotent and block unsafe duplicate stock reversal.
- **B09** Refresh catalog/category/image settings in the retained cart screen without repricing cart snapshots or replacing manual discounts.
- **B10 / R03** Keep the 80 mm receipt and paginate long receipts with Chinese text.
- **B12** Resolve newly created suppliers from the refreshed picker list by stable ID.
- **B13** Propagate Windows clipboard failures and use the existing share fallback instead of reporting a false success.
- **R01** Pause and drain background DB polling during restore; stop accepting LAN requests and drain in-flight requests before replacing the production database.
- **R04** Ignore stale catalog-search responses using request generations.

MyInvois signing changes are not included. Latest official requirements and an independent verifier remain necessary to resolve R02. No production submission or cancellation was performed.

## Ongoing maintenance

For each future build, update `version` in `pubspec.yaml` and add the real changes to this file. About reads Version + Build Number from installed package metadata; do not add a second version constant. Keep prior release entries. `test/app_version_test.dart` checks the runtime label and changelog version.
