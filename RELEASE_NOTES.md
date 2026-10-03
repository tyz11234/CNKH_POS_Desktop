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

