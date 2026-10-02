# 本轮 Flutter analyze 逐条诊断

执行日期：2026-10-02。Flutter stable 3.47.6；命令均为 `flutter analyze --no-fatal-infos --no-fatal-warnings`。参数沿用现有 CI，未添加忽略规则或删减扫描范围；两端退出码 0，仍有下列实际 warnings / infos。

## Desktop

**0 errors / 6 warnings / 38 infos**，共 44 issues。[实际 CI 日志](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/36997979170)。

| 严重度 | 文件位置 | 规则 |
| --- | --- | --- |
| info | `lib/desktop_shell.dart:49:7` | `prefer_final_fields` |
| info | `lib/desktop_shell.dart:244:16` | `use_build_context_synchronously` |
| info | `lib/screens/admin/products_admin.dart:965:46` | `use_build_context_synchronously` |
| info | `lib/screens/cart_screen.dart:6:8` | `unnecessary_import` |
| info | `lib/screens/cart_screen.dart:7:8` | `unnecessary_import` |
| info | `lib/screens/checkout_screen.dart:5:8` | `unnecessary_import` |
| info | `lib/screens/checkout_screen.dart:131:20` | `use_build_context_synchronously` |
| info | `lib/screens/einvoice_setup_screen.dart:91:67` | `use_build_context_synchronously` |
| info | `lib/screens/sales_list_screen.dart:250:45` | `unnecessary_string_interpolations` |
| info | `lib/screens/settings_screen.dart:463:42` | `use_build_context_synchronously` |
| info | `lib/services/auth_service.dart:35:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:52:9` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:72:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:76:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:97:11` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:134:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/desktop_backup.dart:291:61` | `curly_braces_in_flow_control_structures` |
| warning | `lib/services/desktop_backup.dart:338:7` | `unawaited_return_in_try_block` |
| info | `lib/services/einvoice/einvoice_service.dart:139:64` | `curly_braces_in_flow_control_structures` |
| warning | `lib/services/einvoice/einvoice_signer.dart:220:37` | `unnecessary_cast` |
| info | `lib/services/lan_mutations.dart:122:60` | `curly_braces_in_flow_control_structures` |
| warning | `lib/services/lan_pairing_host.dart:55:10` | `unused_element_parameter` |
| warning | `lib/services/lan_pairing_host.dart:56:10` | `unused_element_parameter` |
| info | `lib/services/lan_pairing_host.dart:1482:50` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/lan_pairing_host.dart:1487:57` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/lan_pairing_host.dart:1489:50` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/lan_pairing_host.dart:1501:56` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/lan_pairing_host.dart:1503:57` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:11:8` | `unnecessary_import` |
| info | `lib/services/pos_repository.dart:12:8` | `unnecessary_import` |
| info | `lib/services/pos_repository.dart:271:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:404:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:446:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:503:11` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:652:9` | `curly_braces_in_flow_control_structures` |
| warning | `lib/services/purchase_edit_service.dart:1:8` | `unused_import` |
| info | `lib/services/sale_reversal.dart:17:5` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/sale_reversal.dart:42:9` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/sale_reversal.dart:56:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/sync_store.dart:61:5` | `curly_braces_in_flow_control_structures` |
| info | `test/einvoice_test.dart:549:26` | `curly_braces_in_flow_control_structures` |
| info | `test/money_discount_test.dart:2:8` | `unnecessary_import` |
| info | `test/money_discount_test.dart:4:8` | `unnecessary_import` |
| warning | `tool/training_capture_test.dart:34:23` | `invalid_use_of_visible_for_testing_member` |

## Mobile

**0 errors / 5 warnings / 37 infos**，共 42 issues。[实际 CI 日志](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/36997981149)。

| 严重度 | 文件位置 | 规则 |
| --- | --- | --- |
| info | `lib/db/legacy_purchase_outbox_migration.dart:99:44` | `curly_braces_in_flow_control_structures` |
| info | `lib/db/legacy_purchase_outbox_migration.dart:142:46` | `curly_braces_in_flow_control_structures` |
| info | `lib/db/legacy_purchase_outbox_migration.dart:507:29` | `curly_braces_in_flow_control_structures` |
| info | `lib/main.dart:356:16` | `use_build_context_synchronously` |
| info | `lib/screens/admin/products_admin.dart:704:47` | `curly_braces_in_flow_control_structures` |
| info | `lib/screens/admin/purchase_ocr_screen.dart:174:21` | `deprecated_member_use` |
| info | `lib/screens/admin/purchase_ocr_screen.dart:579:16` | `use_build_context_synchronously` |
| info | `lib/screens/admin/purchase_ocr_screen.dart:623:20` | `use_build_context_synchronously` |
| info | `lib/screens/admin/purchase_ocr_screen.dart:833:54` | `use_build_context_synchronously` |
| info | `lib/screens/admin/purchase_ocr_screen.dart:874:21` | `deprecated_member_use` |
| info | `lib/screens/admin/purchase_ocr_screen.dart:1066:17` | `deprecated_member_use` |
| info | `lib/screens/cart_screen.dart:7:8` | `unnecessary_import` |
| info | `lib/screens/cart_screen.dart:8:8` | `unnecessary_import` |
| info | `lib/screens/cart_screen.dart:83:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/screens/checkout_screen.dart:5:8` | `unnecessary_import` |
| info | `lib/screens/checkout_screen.dart:131:20` | `use_build_context_synchronously` |
| info | `lib/screens/sales_list_screen.dart:250:43` | `unnecessary_string_interpolations` |
| info | `lib/services/auth_service.dart:35:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:52:9` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:72:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:76:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:97:11` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/auth_service.dart:134:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:11:8` | `unnecessary_import` |
| info | `lib/services/pos_repository.dart:12:8` | `unnecessary_import` |
| info | `lib/services/pos_repository.dart:301:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:448:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:505:7` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:562:11` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/pos_repository.dart:767:9` | `curly_braces_in_flow_control_structures` |
| warning | `lib/services/product_images.dart:79:7` | `unawaited_return_in_try_block` |
| warning | `lib/services/purchase_history_sync.dart:181:25` | `unnecessary_non_null_assertion` |
| warning | `lib/services/purchase_history_sync.dart:201:26` | `unnecessary_non_null_assertion` |
| warning | `lib/services/purchase_history_sync.dart:203:47` | `unnecessary_non_null_assertion` |
| info | `lib/services/purchase_ocr_repository.dart:853:22` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/sale_reversal.dart:16:5` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/sale_reversal.dart:40:9` | `curly_braces_in_flow_control_structures` |
| info | `lib/services/sale_reversal.dart:54:7` | `curly_braces_in_flow_control_structures` |
| info | `test/money_discount_test.dart:2:8` | `unnecessary_import` |
| info | `test/money_discount_test.dart:4:8` | `unnecessary_import` |
| info | `test/product_image_retry_test.dart:37:27` | `curly_braces_in_flow_control_structures` |
| warning | `tool/training_capture_test.dart:32:23` | `invalid_use_of_visible_for_testing_member` |

## 配套 integration

`Desktop/integration` 在 Desktop HTTP #108 与 Mobile HTTP #97 两个工作流均执行相同参数的 analyze，结果都是 **0 errors / 0 warnings / 0 infos，No issues found**。完整命令、配套源码 SHA 和业务回归证据见 [ELEVEN_BUG_VERIFICATION.md](ELEVEN_BUG_VERIFICATION.md)。
