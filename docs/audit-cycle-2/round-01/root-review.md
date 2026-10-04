# Audit Cycle 2 · Round 1 · Root review

Baseline: Mobile `0773f646e4cf5980c93bbe025b5f3aa7ff82b9ff`, Desktop `543178e35ca2caf03b12055ba9f9cd0bb7af8a17`; isolated sibling checkouts preserve original dirty workspaces. Flutter 3.47.6 / Dart 3.13.5 matches target CI. Linux FFI uses the installed SQLite library through a toolchain-only libsqlite3.so link.

## Confirmed QR import data loss (both platforms)

`QrStorage.saveFromPicker` deleted an old PNG before attempting a replacement JPG copy. A missing/unreadable replacement therefore removed the active payment QR while preferences still referenced it. Selecting the current saved file again also copied a file onto itself, truncating the QR to zero bytes.

Before: both repositories fail 2 of 3 new regression cases; logs `CNKH_POS_*-qr-before.log` contain actual null saved-path and empty-byte failures. After: both repositories pass 3/3, logs `CNKH_POS_*-qr-after.log`.

Fix: copy to a new unique app-owned path, persist the preference, then retire the old owned file. Failed copy/preference writes preserve the selected original. Old-file cleanup failures preserve the successful import. The existing local-only QR storage and admin UI permission stay intact. Permanent tests: `test/qr_storage_import_safety_test.dart` in each repository, covering failed replacement, successful replacement/clear and selecting the saved image.

## Additional root review

- Settings operations/roles, QR path handling, About metadata, receipt ownership cleanup, barcode export, scan feedback and Bluetooth printing were read alongside current tests. Settings mutation callbacks perform their state updates before awaiting writes; this specific pattern does not demonstrate setState-after-dispose. Cache cleanup checks ownership metadata and ignores unrelated files. Bluetooth failures return visible messages without blocking committed sales; hardware is not available here.
- Desktop user-admin service has no explicit gate on list/create/update, but current Staff UI cannot reach the admin menu and there is no network user-admin endpoint. A direct library call alone is insufficient proof of a current user-reachable privilege bypass; no speculative product change made. PIN replacement already requires an Admin auth session.
- Windows release is a portable ZIP. Native release build and resource checks need GitHub Windows CI. The Android matching signing key is still unverified; no incompatible replacement APK should be published.
- Full inventory/tests and screenshots are regenerated for each round by `run_round.py`. Per-command timestamps, exit codes and source manifests must be retained. Domain reviewers independently inspect all current source for their scopes each round. Static scan alone does not close a round.

Round 1 full regression remains pending until all domain fixes and the shared runner complete. Android physical camera/upgrade, Windows GUI/printers/store Wi-Fi and live MyInvois acceptance remain explicit external boundaries.
