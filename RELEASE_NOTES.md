# CNKH POS Desktop 0.4.0+9

- 模块化 MyInvois 支持：Desktop 加密配置、Invoice 1.0 JSON、OAuth、提交/查询/取消和提交记录。
- Mobile 保持离线销售，通过已有 LAN 配对同步 e-Invoice 状态；不直接连接 MyInvois。
- schema v9 增量升级，保留原收银、商品、库存页面和业务数据。
- 11 课员工培训，使用实际 Flutter 页面截图及控件箭头。

## 使用与范围

管理员在 Desktop 设置 → e-Invoice Setup 先配置 Sandbox，补齐公司及买方资料后生成、核对并提交。正式环境凭据独立配置。Submitted 不等于 Validated。

当前支持 MYR 国内普通 Invoice 1.0、整单统一税种/税率/分类；混合税率、汇总和调整票请使用 MyInvois Portal。1.1 数字签章不在本版本范围。结果未知时先核对 UUID，禁止盲目重提。

Client ID / Secret 使用 OS 密钥加密；换电脑或 Windows 用户后重新输入。旧 scaffold 的明文凭据升级后清空，需重新填写。

CI 在上传前执行静态分析、Flutter 回归、真实 UI 截图和 Release 构建。API 测试为模拟响应；未持有店主 MyInvois 凭据，因此未进行真实 Sandbox/Production 提交，也未执行真机、打印机或真实门店网络验收。

下载附件后核对 SHA256SUMS.txt。Windows ZIP 需完整解压并保留 DLL/data，再运行 cnkh_pos_desktop.exe；不含安装向导。
