# CNKH POS Desktop 1.10.10+38

发布准备日期：2026-10-08。**安装包待 CI 构建及核验，尚未确认本版发布成功。** 数据库 schema 保持 v10，LAN 协议保持 `cnkh-sync:v1`。

## 本次修复

以下为 Desktop / Mobile 配套版本的完整 16 项修复；作用端标明实际变更范围。

| 编号 | 作用端 | 修复后行为 |
| --- | --- | --- |
| F01 | 双端 | 逐行删空购物车时清除整单折扣，下一笔销售不再继承旧折扣。 |
| F02 | Desktop | 进货追加相同商品但不同成本时保留独立明细，维持准确总额和最终成本顺序。 |
| F03 | Desktop | 进货不再合并不同 ID 或不同明确编码的同名商品；按名称匹配时要求结果唯一。 |
| F04 | Mobile | 清除交易前保护未同步销售及依赖交易记录的待处理任务，防止销售和上传任务丢失。 |
| F05 | 双端 | 商品保存、进货建品和电脑接收修改采用一致的条码 / SKU 冲突检查；旧歧义数据拒绝扫码误选，不自动删除商品。 |
| F06 | Desktop | 使用最终 Invoice 1.1 内容计算摘要和数字签名，并拒绝旧的错版本签名。 |
| F07 | Mobile | 完整销售对账时将电脑快照中缺失的已同步销售排除出有效销售；保护离线及待处理记录，失败不推进游标。 |
| F08 | Mobile | 销售作废待核对时继续拉取电子发票状态；保留库存保护，暂缓目录和依赖目录的销售拉取，解除后从保留游标重放。 |
| F09 | 双端 | 12 位数字条码使用 Code128 原样编码，打印标签不再自动追加第 13 位。 |
| F10 | Mobile | 后台轮询和主动同步重新加载已保存配置；地址或 token 变化后更换旧 WebSocket 连接。 |
| F11 | 双端联动 | 更正发票接口返回原销售收据号，并独立保留 invoice_no，使手机正确关联电脑销售的发票状态。 |
| F12 | 双端 | 新挂单保存售价及显示快照；取单保留原价，同时使用当前库存和删除状态检查，兼容旧挂单。 |
| F13 | Desktop | 报表响应交易及导航刷新，保留手选日期，并忽略过期异步查询结果。 |
| F14 | 双端 | 现金 / 定金以整数分解析并明确校验，拒绝 NaN、Infinity、指数及超范围输入。 |
| F15 | 双端 | PDF 和蓝牙打印输出已配置的 DuitNow 付款图片，保留比例和留白；缺图时不输出扫码提示。 |
| F16 | Desktop | 销售日期筛选使用次日排他上界，包含结束日最后一秒的小数部分。 |

## 验证记录

- Mobile 完整测试 **187 项通过**；随后调整收款测试的异步等待方式，该用例定点复测通过。
- Desktop 完整测试 **187 项通过，1 项因测试固定等待时间不足失败**；改为等待实际付款完成条件后，该用例及电子发票测试共 **25 项定点复测通过**。这不是一次重新执行的全量通过记录。
- 两端真实 HTTP / WebSocket 配套回归 **29 项通过**。
- 两端 `flutter analyze` 未发现 error；保留原有 warning / info。
- 独立 ZXing 解码验证通过：两端 12 位条码均读回原内容；两端 PDF 及 384 / 576 dots ESC/POS 栅格中的 6 个二维码产物均读回正确测试内容。
- `git diff --check`、修复源码包完整性和补丁应用检查通过。

以上为发布前本地验证。1.10.10+38 的 GitHub Actions 构建结果、产物大小、SHA-256 和 APK 签名核验待完成后补充。实体 Windows / Android 设备、打印机、门店网络和 MyInvois Sandbox / Production 线上验收未执行。

## 安装与发布状态

本次计划提供 **Windows x64 Setup.exe 安装包及完整便携 ZIP**。构建及上传完成前，本页不提供未验证的下载链接或校验值。

Windows 更新前备份业务数据并关闭程序；使用便携 ZIP 时保持 EXE、DLL 和 `data` 目录完整。

Android 旧版 1.10.7+35 APK 使用 Debug 证书，其 SHA-256 为 `51d08c3a894a972f03cfd99dac38a468ffba9de58f0062f6a3bba5b07da57406`。**本版 APK 签名及与旧版的覆盖安装兼容性尚待核验，不承诺可直接覆盖。** 更新前先同步并备份；若 Android 提示签名不匹配，保留旧应用和本地数据，不要卸载仍含未同步业务的旧版本。

下载区、实际 CI 链接及校验值统一记录于 [README](README.md#下载与更新)。

---
# CNKH POS Desktop 1.10.9+37

## Fixes

- **B001 (Both):** About reads the installed package Version and Build Number, removing duplicate hard-coded values.
- **B003 (Both CI):** Pin paired regression workflows to the companion repository commits included in this release cycle.

## Audit and regression

Six complete audit rounds were performed; Rounds 5 and 6 were clean. Final local regression passed: Mobile **147/147**, Desktop **151/151**, and paired HTTP integration **29/29**. Both analyzers reported zero errors. Round 6 made supplier selection wait for the repository update and refreshed dropdown state, removing a timing-sensitive test failure on the Windows runner.

The Windows release workflow runs the complete suite, builds the x64 app, verifies bundled training resources, and stages the portable ZIP with SHA-256. Database schema remains v10 and LAN protocol remains `cnkh-sync:v1`.

## Installation notes

The Windows ZIP is a portable package and has no installer. Back up business data and close the app before extracting it to a separate folder. Keep the EXE, DLL files, and `data` folder together. Physical printer, store-network, Android device, and live MyInvois acceptance were not performed.

---
# CNKH POS Desktop 1.10.8+36

## 修复内容

- **B01** 清除客户切换或取消时旧客户的电话号码；保留手动输入的临时号码供当前销售与电子收据使用。
- **B03** 通过应用升级路径迁移兼容的旧备份；校验必须的表、列及 POS 查询，验证生产路径可重新打开后才删除回滚数据库和图片。
- **B06** 持久化点击时的挂单快照，防止重复提交；成功后仅清除未变化的购物车。
- **B07 / B11** 为商品管理、盘点、进货选择、购物车及审计历史添加 SQL 稳定排序、渐进搜索和分页。
- **B08** 税务待复核时以结构化业务拒绝响应作废请求；保持幂等并阻止不安全的重复库存回补。
- **B09** 保留购物车屏幕时刷新商品、分类和图片设置，不重算价格快照或覆盖手动折扣。
- **B10 / R03** 保持 80 mm 中文小票布局，并分页显示长收据。
- **B12** 使用稳定 ID 从刷新后的供应商选择列表中读取新建供应商。
- **B13** 传播 Windows 剪贴板错误，使用现有分享回退，不再误报成功。
- **R01** 恢复期间暂停并排空数据库后台轮询；替换生产数据库前停止接受 LAN 请求并排空进行中的请求。
- **R04** 使用请求代次忽略过期目录搜索响应。

## Windows Release 验证

Windows Release 工作流 [37115653774](https://github.com/tyz11234/CNKH_POS_Desktop/actions/runs/37115653774) 成功：静态分析通过，完整 Flutter 测试 **149 项通过**，培训截图及资源校验通过，Windows Release 构建与 ZIP 上传成功。Mobile CI **145 项通过**；双端 HTTP 回归见 [运行记录](https://github.com/tyz11234/CNKH_POS_Mobile_APK/actions/runs/37114494494)。

## 下载

- [Windows x64 ZIP 便携包（1.10.8+36）](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.8/CNKH_POS_Desktop-windows-x64-v1.10.8-36.zip)
- [SHA256SUMS.txt](https://github.com/tyz11234/CNKH_POS_Desktop/releases/download/v1.10.8/SHA256SUMS.txt)
- [GitHub Release v1.10.8](https://github.com/tyz11234/CNKH_POS_Desktop/releases/tag/v1.10.8)

ZIP 大小 **17,511,169 字节**，SHA-256：f114693cb0633b6ab46a0d5e7ae32885be4bcc0780971c3ce8fe603fc3fc73c6。Windows ZIP 是完整便携包，不含安装向导。数据库 schema 为 v10，继续使用 cnkh-sync:v1。

Mobile APK 仍为 1.10.7+35。现有 APK 使用 Android Debug 证书；尚未取得与当前安装包匹配的私钥，因此没有发布一个会导致覆盖安装失败的新签名 APK。
