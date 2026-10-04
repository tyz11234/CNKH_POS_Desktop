# Audit Cycle 2 — Round 2

状态：完整完成；本轮确认缺陷 9 组。

全量回归完成时间：`2026-10-04T02:21:34.215699+00:00`。
四域 review 完成时间：`2026-10-04 02:18:06 UTC`。

同一 Round 的失败尝试和环境重跑不另计一轮。`attempt-*` 日志仅保留为故障证据。

| 来源 | HEAD | Version | lib SHA-256 | 全部检查文件清单 SHA-256 |
|---|---|---|---|---|
| mobile | 301a5595e5f3284dd5085b27d149d18479da667f | 1.10.9+37 | 234c2eee65a30be63593548584260007ca5fc38d501216a59482d73d96c2641e | 1c371b18deac65c00013a7425832719037022121f80b5dae85824f157acf8a36 |
| desktop | 4c0cb33d05495f8d84b8140436d6746bd2889663 | 1.10.9+37 | 5cb4dd6e77d7d5bd561a9fbfc32f3ca9d8e84772f16e93c6bede7b8afbe1112c | 331523247689c49c880c990fdea5273e4e6efbf630673433c52fcad94ad19576 |

| 命令 | 开始 UTC | 结束 UTC | Exit | 测试统计 |
|---|---|---|---:|---|
| `/workspace/toolchains/flutter-3.47.6/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 2026-10-04T02:16:53.288980+00:00 | 2026-10-04T02:17:04.122727+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --concurrency=4 --machine` | 2026-10-04T02:17:04.122928+00:00 | 2026-10-04T02:19:57.613717+00:00 | 0 | pass=192 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 2026-10-04T02:16:53.289201+00:00 | 2026-10-04T02:17:05.421203+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --concurrency=4 --machine` | 2026-10-04T02:17:05.421376+00:00 | 2026-10-04T02:20:13.528419+00:00 | 0 | pass=235 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 2026-10-04T02:16:53.289419+00:00 | 2026-10-04T02:16:54.367354+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --concurrency=4 --machine test regression` | 2026-10-04T02:16:54.367548+00:00 | 2026-10-04T02:17:23.019162+00:00 | 0 | pass=29 / fail=0 / skip=0 |
| `python3 tool/test_release_gate.py` | 2026-10-04T02:20:13.532581+00:00 | 2026-10-04T02:20:13.797131+00:00 | 0 | 不适用 |
| `python3 tool/test_release_gate.py` | 2026-10-04T02:20:13.797311+00:00 | 2026-10-04T02:20:14.061964+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_capture_test.dart` | 2026-10-04T02:20:14.062163+00:00 | 2026-10-04T02:20:49.704263+00:00 | 0 | pass=1 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_view_test.dart` | 2026-10-04T02:20:49.704675+00:00 | 2026-10-04T02:20:55.474176+00:00 | 0 | pass=1 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_capture_test.dart` | 2026-10-04T02:20:55.474524+00:00 | 2026-10-04T02:21:28.755098+00:00 | 0 | pass=1 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_view_test.dart` | 2026-10-04T02:21:28.759126+00:00 | 2026-10-04T02:21:34.170135+00:00 | 0 | pass=1 / fail=0 / skip=0 |

来源计数、命令 log hash、静态门槛与四域确认见 [`summary.json`](summary.json)。

## 域报告

- [mobile-review.md](mobile-review.md)
- [desktop-review.md](desktop-review.md)
- [sync-db-review.md](sync-db-review.md)
- [einvoice-platform-review.md](einvoice-platform-review.md)
- [root-review.md](root-review.md)
- [windows-fixture-review.md](windows-fixture-review.md)

## 结构化动态清单与来源

| 文件 | SHA-256 | Bytes |
|---|---|---:|
| [desktop/source-inventory.json](desktop/source-inventory.json) | `2901629c5018e2c6a2c0da89a7d70161af5950ce5303024b512823bdb3db9f1b` | 9491 |
| [einvoice/boundary-rescan.txt](einvoice/boundary-rescan.txt) | `f2e1c4842c8f9c13f6398823e6183891426d5a9d37603d8d16a200ecb437bc2b` | 31240 |
| [einvoice/reviewed-files.json](einvoice/reviewed-files.json) | `013a21d3f457fdaef8a2e1e9213c89eccdc4bd5cb8f90258f1ca7a5ab7c5b6d1` | 17461 |
| [mobile-source-inventory.txt](mobile-source-inventory.txt) | `3e0b82431d782e687f528d5712c3750319383b46d1204b928c27dbb5c0b86858` | 2149 |
| [mobile-structure-scan.txt](mobile-structure-scan.txt) | `24491d5c037492bf5af5cb2785d487e50c69c4ac10556f8e20378f8131ebb1b1` | 33192 |
| [sync/dynamic-inventory.json](sync/dynamic-inventory.json) | `fd481de0f5396816f4e48a4f36496b2e794a5072184e0278bb7c9c03a04d92c7` | 58240 |

这些文件保留相应域审查时的清单；其 hash 作为证据来源记录，不据此推定原生设备或外部服务通过。

部分子域报告是在统一回归前写成；本页完成状态以结构化全量 Gate 和四域确认共同决定。
Windows CI、正式签名、实体设备和真实外部服务不由本地测试结果推定通过。
