# Cycle 2 / Round 1 — Windows widget-test synchronization

Date: 2026-10-03 UTC. Scope: test-only synchronization, with no product changes by this audit subtask.

Baseline main commits: Desktop `543178e35ca2caf03b12055ba9f9cd0bb7af8a17`; Mobile `0773f646e4cf5980c93bbe025b5f3aa7ff82b9ff`.

## Observed failures

Desktop workflow [37131354448](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37131354448) ran the documentation-only main commit after the successful 1.10.9 release build.

- Attempt 1 / job `111226941238`: `checkout_customer_phone_test.dart` failed at its original line 125, `Expected: not null, Actual: <null>`, on the `saved` callback assertion. Both supplier-selection tests passed in this attempt.
- Attempt 2 / job `111228217828`: the same phone assertion failed again. The ordinary supplier-creation test later reported two `Warning database has been locked for 0:00:10.000000` warnings, followed by `TimeoutException after 0:10:00.000000: Test timed out after 10 minutes`. The workflow was eventually canceled at its 60-minute limit. This is not a passing rerun.
- Decoded GitHub logs are preserved as `windows/job-111226941238-excerpts.log` and `windows/job-111228217828-excerpts.log`.

The previous production release workflow `37130267034` passed 151 Desktop tests. This does not make the subsequent failing main CI successful.

## Mechanism and minimal changes

### Phone callback

The original helper waited a fixed six repetitions of 60 ms real delay and 80 ms virtual pumping. That permits approximately 360 ms of real I/O and does not assert that a sale has completed. `CheckoutScreen._confirmOnce` must first await repository checks and the SQLite sale transaction, then await `WidgetsBinding.instance.endOfFrame`, and only then invoke `onPaid`. A slow Windows runner can legitimately have `saved == null` after the fixed helper.

Desktop and the identical Mobile regression now wait for the loaded three-item customer dropdown before interaction and for the actual `onPaid` callback after confirming. Each loop alternates 20 ms real I/O with a widget pump and has a 10-second wall-clock deadline with a descriptive failure. The synchronous phone-autofill assertions, selected customer, manual number, e-receipt recipient and actual persisted sales row remain unchanged. No callback is mocked and no business assertion is removed.

### Supplier refresh

The old supplier wait repeatedly called `await tester.runAsync(() => repo.listSuppliers())` while the supplier-creation action could still be in `_saveEntity`'s transaction. A database read can wait behind that transaction's serialization lock; meanwhile the test is awaiting `runAsync` and cannot pump fake-async continuations needed by the UI action. The attempted eight-second loop was not a true bound because its individual database await had no completion bound. This matches the observed database-lock warning and ten-minute test timeout.

The new wait inspects only `DropdownButton<String>.items`, `value` and selected item text while alternating real I/O and widget pumping. It also safely waits while the QR import is displaying its busy indicator. The initial supplier bootstrap uses the same condition. Only after the refreshed supplier has appeared in the selected dropdown do the existing repository-list and persisted-purchase assertions run. The 10-second deadline applies to the entire UI wait; it does not increase the global test timeout.

`windows/fake_async_sqlite_lock_repro.dart` separately demonstrates the scheduling dependency with actual SQLite: a transaction holds a deliberately modeled fake-zone continuation; a real-zone query cannot complete while the fake queue is unpumped, and completes after pumping releases the transaction. `windows/fake-async-lock-repro.log` records both the bounded blocked query and recovery. This controlled model is mechanism evidence, not an exact reproduction of the Windows widget suite's scheduler or a new product defect.

## Validation

Flutter 3.47.6 / Dart 3.13.5, Linux. Commands used the project's lockfile and `PUB_CACHE=/workspace/.cache/dart-pub`. `LD_LIBRARY_PATH=/workspace/toolchains/native-libs` resolves the environment's missing unversioned `libsqlite3.so` for FFI's worker isolate. No product loading code was changed for this environment.

- Desktop targeted phone + ordinary supplier + QR supplier: **3/3 pass**, approximately 6 seconds (`windows/targeted-tests-after.log`).
- Independent repeat of those tests: **3/3 pass**, approximately 7 seconds (`windows/targeted-tests-repeat.log`).
- Mobile synchronized phone regression: **1/1 pass**, approximately 2 seconds (`windows/mobile-phone-after.log`).
- Desktop targeted analyzer: **no issues** (`windows/targeted-analyze.log`).
- Mobile targeted analyzer: **no issues** (`windows/mobile-phone-analyze.log`).
- Both repositories' patch whitespace checks pass.

The first local command exposed the missing Linux SQLite shared-library alias and a local-helper declaration-order compile error in the initial patch; both were corrected before the passing runs above. Those failures are not product bug findings.

**Windows verification limit:** this subtask ran on Linux and inspected real Windows CI logs. It did not rerun the fixed commit on a Windows runner or launch the Windows application. The main agent must confirm the next Windows CI separately; local PASS is not recorded as Windows PASS.

## Full scan of related widget-test patterns

Read the uploaded master README and searched `/workspace` for `AGENTS.md`; neither project has one. Read both phone regression tests, Desktop supplier test, both checkout implementations, Desktop supplier creation/repository transaction code, Flutter `runAsync` documentation/implementation and sqflite's serialized database access.

Scanned all `.dart` files under both repositories' `test/`, `tool/`, `integration/` and `integration_test/` where present for `runAsync`, `flush`, `settle`, waits and direct database reads. At scan time this matched ten files in each repository. Related sources inspected include both `checkout_resume_safety_test`, `daily_closing_entry_regression_test`, `receipt_cache_settings_entry_test`, `widget_test`, `tool/training_capture_test`, `tool/training_view_test`, Mobile `mobile_layout_test` and `product_image_edit_regression_test`, Desktop `admin_pin_cancel_entry_test` and newly added `product_image_editor_safety_test`.

- Both daily-closing widget tests perform fixed waiting after UI save and then query `repo.listClosings`. This is a possible instance of the same serialization dependency under a sufficiently slow scheduler, but no failing run was observed. They remain unchanged and are not counted as confirmed bugs.
- Both checkout-resume tests contain fixed waits; their final database reads occur after explicit committed/paid assertions. No additional hang was demonstrated.
- Settings-cache and admin-PIN actions deliberately begin in `runAsync` and wait for visible completion before checking results; no supplier-style query inside a pending UI wait was found there.
- Login tests begin authentication in the real zone, bound authentication completion, and start/stop sockets in real setup/teardown. Their later fixed waits may produce timing sensitivity, but no new failure was established.
- Layout/capture/image-render tests contain fixed real-I/O waits. Database setup/mutations generally occur in the real zone; subsequent UI assertions or image work do not demonstrate a transaction-lock cycle. Preserve these tests and monitor the full ten-round suite.

Confirmed scope for this subtask: two preexisting test-synchronization defects, repaired in three test files because Mobile shares the phone test. New reproducible product bugs from this Windows stability subtask: **0**. No tests skipped, no failure suppressed, no business behavior changed.
