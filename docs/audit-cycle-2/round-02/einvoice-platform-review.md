# Cycle 2 Round 2 eInvoice / native / build / training review

Mobile baseline `230f4768ce24b6fa3a0181351246a22b5907a715`，Desktop baseline `cd6c9db754f94fd83f2b018cd7d64791ceaa3087`；版本均1.10.9+37、DB v10、LAN cnkh-sync:v1。当前paired refs指向该两端SHA。根代理保留docs/PNG/JSON/pin/dev-dependency的在途修改；本代理未覆盖它们。

## 完整范围独立重扫

重新动态扫描eInvoice全部service methods/endpoints、设置/表单、状态镜像及全host/env快照、eInvoice DB schema/migration、LAN最新attempt payload。重新读取Android/Windows native目录全部实际XML/Gradle/Kotlin/CMake/C++/manifest/resource/config、所有现行workflow、版本来源/About package metadata、全部依赖、训练页面/截图/箭头/capture/bundle verifier及永久回归。共91份范围文件，字节数/校验值及path详见 `einvoice/reviewed-files.json`。源码异常/transaction/throw/status/UUID/credentials/redirect/lifecycle索引见 `einvoice/boundary-rescan.txt`。

- S18/M07/D06/D07：双环境OAuth cache/refresh/401/Retry-After、HTTP redirect禁用、认证前失败不claim文档、claim后超时/5xx/409保留needs_review、同步Rejected无UUID、Accepted/Submitted→Validated/Invalid/Cancelled、独立更正保留原payload/UUID/attempt audit、UUID+Submission UID与号码/TIN/金额核对、POS void互斥、credential/certificate AES-GCM环境AAD/OS密钥、RSA profile/expiry/signature checks。
- Mobile状态快照所有行先验证再在单事务删除/插入；非法行、网络分页错误不清旧结果，host/environment隔离继续成立。Desktop同步仅最大attempt，未把历史尝试重新作为当前状态。
- M10/D13：paired Desktop ref训练source及日志、11课/12组Mobile图片、PFX/Invalid/Submission UID更新、实际控件捕获与坐标、PNG/JSON尺寸/范围/字节一致性。
- D12/Mobile Release：Android signing secrets/PR仅临时key/debug明确授权gate、INTERNET权限、minSdk与plugin、Windows runtime/secure-storage/资源version、包名/SHA文件、tag/pubspec/SHA/immutable gate及共享mutex/overwrite false。
- 未新增正式产品功能或production依赖；根代理新增image_picker_platform_interface及Mobile path_provider_platform_interface为回归直接import的dev_dependencies，不扩大正式权限/API。

## 新可复现问题：成功HTTP null响应被发布门槛当成404缺失

影响Both，位置两端 `tool/check_release_gate.py:49`（R1版本直接return json.load(response)）。GitHubAPI.get把HTTP200合法JSON null解码成None，而check_release用None表示Release/tag不存在。给两个GET endpoint均返回200/null时，门槛反而允许发布；这破坏异常响应fail-closed。

最小真实复现使用Python标准库localhost HTTPServer，实际urllib GET两次200 `null`（无外部写入）：门槛返回PASS v1.10.10。证据 `einvoice/release-null-before.log`。永久transport regression在旧逻辑失败，日志 `einvoice/release-null-test-before.log`。

最小修复：成功JSON必须为dict；null/list/number/bool/string皆以现有GateError fail-closed。仅HTTP404返回None。未改变正常新版本/旧Release/tag解析路径或签名条件。

该问题的永久回归覆盖5种合法JSON错误形态，修复当时双端各27/27脚本测试通过，日志 `einvoice/release-null-test-after-desktop.log`、`...-mobile.log`。相同localhost HTTP200/null修复后实际BLOCKED，证据 `einvoice/release-null-after.log`。两端diff --check通过。根代理执行本轮所有Flutter/集成/培训/版本完整pipeline，不能把本范围定向检查当整轮PASS。

## 没有重记或推测的Bug

- R1培训漂移、旧Release overwrite/tag错配修复仍有效，不重复计新问题。
- 已排除dispose后catch、签名1.0→1.1指南示例，不再制造新Bug或修改算法。
- schema/state/crypto/API mirror源码没有新可复现失败；没有真实税务请求。
- Cancel未知返回/网络失败保留本地状态；状态应用UUID不匹配保护保持，旧凭据key丢失需重输是明示行为。

## 外部边界与覆盖状态

全91/91范围文件已复审，无静默skip。4类真实外部验收仍不可由自动化替代：授权MyInvois Sandbox/Production和证书信任链；原Mobile Debug签名对应私钥/带离线数据覆盖升级；实体Android权限/相机/打印/分享；Windows GUI首次启动/OS key storage/打印与门店LAN。已静态review和mock/SQLite/localhost测试覆盖其可执行部分，真实验收需对应凭据/设备/Windows用户会话。现行正式APK blocker继续保留，未发布不匹配APK。

## 新可复现问题：published-by-tag未覆盖同tag草稿Release

影响Both，R1及初次null修复版本只查询 `releases/tags/{tag}` 和 `git/ref/tags/{tag}`。GitHub官方API明确前者查published Release，authenticated `/releases` 列表才含push-access用户可见草稿。同tag旧草稿没有published Release或tag时两查询404，门槛允许继续；softprops v2的canonicalizeCreatedRelease可复用旧同tag草稿，而overwrite_files:false保留同名旧资产，形成旧包与新source metadata不一致的可复现触发条件。

使用符合官方API契约的localhost服务实证旧门槛PASS，草稿ID7仍未被查询，证据 `einvoice/release-draft-gap-reproduction.log`。官方OpenAPI及softprops来源URL、行段、SHA见 `einvoice/release-draft-gap-official-sources.txt`。没有创建、修改或发布真实GitHub草稿。

最小修复位置双端 `tool/check_release_gate.py:46`、`:93`：保留原by-tag及ref/SHA规则，在published查询缺失后认证读取每页100条Release列表；第一页或晚页同tag对象（含草稿）均阻断。其他tag、空tag草稿正常通过。列表HTTP异常、非法JSON/形态/条目、缺token、重复ID/不前进、超过100条或分页上限均fail-closed；只使用GET且不输出token。

双端 `tool/test_release_gate.py:257` 增加13项真实localhost HTTP永久测试，覆盖首页/晚页同tag、其他草稿、empty list、缺token、晚页401/403/404/429/500、非法响应/条目、重复/超大/超限分页、正常晚页终止。修前40项测试产生30个失败subcase，证据 `einvoice/release-draft-test-before.log`；修后双端各40/40 PASS，证据 `einvoice/release-draft-test-after-desktop.log`、`...-mobile.log`。两端gate/test文件逐字一致，diff --check通过。

## 完成状态

本轮本范围确认2个独立新问题，均已修复。每端永久测试由R1的26项增加至40项（null形态1项、草稿/分页真实HTTP13项）。只修改各端两个Release脚本，没有修改workflow、正式签名条件、版本或eInvoice产品算法。完整91份范围文件manifest已更新至最终源码，源码冻结。

独立复审15项真实HTTP/core先通过null修复，并额外发现上述草稿边界；其修前记录和修后复审注记见 `einvoice/release-gate-independent-review.md`。根代理执行本轮Flutter、集成、培训和版本全部pipeline，以上40/40是本范围定向结果，不能代替整轮PASS。
