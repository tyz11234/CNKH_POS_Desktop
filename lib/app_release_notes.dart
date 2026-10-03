/// Keep this version and release record in sync with pubspec.yaml and
/// CHANGELOG.md whenever a Desktop build is updated.
const String appVersion = '1.10.8';
const String appBuildNumber = '36';
const String appVersionLabel = '$appVersion+$appBuildNumber';

const List<String> appReleaseNotes = <String>[
  'B01：切换客户或取消客户后不再误用上一位客户的自动带入电话；手动填写的临时号码会保留，并用于单据与电子收据分享。',
  'B03/R01：备份恢复先迁移并校验暂存数据库，实际重开失败时回滚数据库和图片；恢复期间排空 LAN 请求并暂停后台数据库轮询。',
  'B06：挂单使用点击时的购物车快照，避免异步保存期间的新修改被清除，并阻止重复提交。',
  'B07/B11/R04：商品、库存盘点、采购选择器、审计和购物车支持稳定分页/搜索；快速搜索结果采用请求代次保护。',
  'B08：电子发票限制导致销售作废被拒时返回结构化待核对状态，不重复返还库存；重复请求保持幂等。',
  'B09：购物车刷新商品、分类和图片设置，同时保留购物车价格快照及人工折扣。',
  'B10/R03：电子收据 PDF 对长收据分页，保留 80mm 布局与中文字体。',
  'B12：新建供应商后使用稳定 ID 从刷新后的列表恢复选择。',
  'B13：Windows 剪贴板失败会返回失败并触发系统分享回退，不再误报复制成功。',
  'MyInvois 签名规范仍需最新官方材料和独立验证器确认；本次未向生产环境提交或取消发票。',
];
