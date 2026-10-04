# Audit Cycle 2 — Round 1

状态：完整完成；本轮确认缺陷 9 组。

全量回归完成时间：`2026-10-03T17:01:50.578815+00:00`。
四域 review 完成时间：`2026-10-03T16:58:48.506754+00:00`。

同一 Round 的失败尝试和环境重跑不另计一轮。`attempt-*` 日志仅保留为故障证据。

| 来源 | HEAD | Version | lib SHA-256 | 全部检查文件清单 SHA-256 |
|---|---|---|---|---|
| mobile | 0773f646e4cf5980c93bbe025b5f3aa7ff82b9ff | 1.10.9+37 | 12dbe5f1bfdb7a97e7905f19f90e12024d04104cdfa95ea6e0e7ef93fe590211 | 7198f9b56da4372a71dd6f9f4fd9ddc86007d346308c1f114cf0d6e8ac0c3665 |
| desktop | 543178e35ca2caf03b12055ba9f9cd0bb7af8a17 | 1.10.9+37 | 734800f7fb19016a84f117b2955ed597d1dd772b55b6f90d41a70538337e7ef9 | d98ce12b5b7f850da1d439c3c6e58fa4834c9203dd8d875e0032d49ce074c105 |

| 命令 | 开始 UTC | 结束 UTC | Exit | 测试统计 |
|---|---|---|---:|---|
| `/workspace/toolchains/flutter-3.47.6/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 2026-10-03T16:57:31.996413+00:00 | 2026-10-03T16:57:57.268518+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --concurrency=4 --machine` | 2026-10-03T16:57:57.268698+00:00 | 2026-10-03T17:00:20.072128+00:00 | 0 | pass=160 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 2026-10-03T16:57:31.996821+00:00 | 2026-10-03T16:57:52.409311+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --concurrency=4 --machine` | 2026-10-03T16:57:52.409497+00:00 | 2026-10-03T17:00:30.275692+00:00 | 0 | pass=183 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 2026-10-03T16:57:31.997119+00:00 | 2026-10-03T16:57:32.817919+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --concurrency=4 --machine test regression` | 2026-10-03T16:57:32.818237+00:00 | 2026-10-03T16:58:01.017920+00:00 | 0 | pass=29 / fail=0 / skip=0 |
| `python3 tool/test_release_gate.py` | 2026-10-03T17:00:30.279413+00:00 | 2026-10-03T17:00:30.443883+00:00 | 0 | 不适用 |
| `python3 tool/test_release_gate.py` | 2026-10-03T17:00:30.444092+00:00 | 2026-10-03T17:00:30.608559+00:00 | 0 | 不适用 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_capture_test.dart` | 2026-10-03T17:00:30.608699+00:00 | 2026-10-03T17:01:06.584422+00:00 | 0 | pass=1 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_view_test.dart` | 2026-10-03T17:01:06.584824+00:00 | 2026-10-03T17:01:12.068317+00:00 | 0 | pass=1 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_capture_test.dart` | 2026-10-03T17:01:12.068670+00:00 | 2026-10-03T17:01:44.823786+00:00 | 0 | pass=1 / fail=0 / skip=0 |
| `/workspace/toolchains/flutter-3.47.6/bin/flutter test --no-pub --machine tool/training_view_test.dart` | 2026-10-03T17:01:44.825797+00:00 | 2026-10-03T17:01:50.526916+00:00 | 0 | pass=1 / fail=0 / skip=0 |

来源计数、命令 log hash、静态门槛与四域确认见 [`summary.json`](summary.json)。

## 域报告

- [mobile-review.md](mobile-review.md)
- [desktop-review.md](desktop-review.md)
- [sync-db-review.md](sync-db-review.md)
- [einvoice-platform-review.md](einvoice-platform-review.md)
- [root-review.md](root-review.md)
- [windows-test-diagnosis.md](windows-test-diagnosis.md)

## 结构化动态清单与来源

| 文件 | SHA-256 | Bytes |
|---|---|---:|
| [desktop/source-inventory.json](desktop/source-inventory.json) | `b0b32a751e028923574e5851f52ac91dbaedf5e11a1b7e7c7beb494ebf80e54e` | 8337 |
| [einvoice/reviewed-files.json](einvoice/reviewed-files.json) | `2486f9bac3fcdbb850f5065e3a60daf049ea945655345f7fe6d278b35fb90850` | 8574 |
| [sync/dynamic-inventory.json](sync/dynamic-inventory.json) | `dd8613a8b8037d6aa2089988aadf364495b75a573cae111cea193d9ada992f4e` | 10124 |

这些文件保留相应域审查时的清单；其 hash 作为证据来源记录，不据此推定原生设备或外部服务通过。

部分子域报告是在统一回归前写成；本页完成状态以结构化全量 Gate 和四域确认共同决定。
Windows CI、正式签名、实体设备和真实外部服务不由本地测试结果推定通过。
