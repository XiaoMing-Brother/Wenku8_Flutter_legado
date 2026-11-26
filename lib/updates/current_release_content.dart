import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，请勿购买所谓付费版、激活码或解锁服务。**';
const releaseProjectNotice =
    '本项目为第三方客户端，并非轻小说文库（Wenku8）官方应用，也不运营该站点。在线书目与内容来自轻小说文库及你导入的书源，本地书籍由用户自行导入，安装包不附带小说文件或书源。';
const releaseRightsNotice =
    '小说、封面和插图归各自权利人所有。请仅使用有权访问的内容，遵守来源网站规则，不得绕过访问限制、破解 DRM，或未经许可传播、出售内容。';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const releaseMaintenanceNotice =
    '后续版本通过当前仓库的 GitHub Release 发布，可在「关于文库阅读」中检查更新。';
const _fallbackFont = '正文新增补字字体，主字体缺字时使用所选字体补齐，支持导入字体和可下载字体。';
const _paragraphPagination = '横排翻页默认避免跨页孤行，跨页段落优先在前后页各保留至少两行。';
const _readerMenu = '阅读菜单显隐时保持正文布局与阅读位置稳定，旋转屏幕后重新适配安全区。';
const _preferencesBackup = '完善补字字体的加载、删除和备份恢复，并补充启动页偏好的备份校验。';
const _sourceLogin = '调整书源登录表单高度，完善统一弹层中的内容展开与滚动。';
const _changes = [
  _fallbackFont,
  _paragraphPagination,
  _readerMenu,
  _preferencesBackup,
  _sourceLogin,
];
const _androidInstall =
    '**Android**：本版为 arm64-v8a 正式构建，包名仍为 legado.wenku，可直接覆盖同包名的旧版；仍识别旧附件前缀的旧版需手动安装一次。';
const _iosInstall = '**iOS**：本次发布未提供 IPA。';
const _harmonyInstall = '**HarmonyOS**：本次发布未提供 HAP。';
const _backup = '升级、整理存储或同步前，请先备份重要书籍和阅读记录。';
const publicReleaseNotes =
    '''
### 免费使用

$releaseFreeNotice

$releaseProjectNotice

$releaseRightsNotice

$releaseReadingNotice

### 支持范围

**$currentReleaseSourcePolicy**

### 本次更新

- $_fallbackFont
- $_paragraphPagination
- $_readerMenu
- $_preferencesBackup
- $_sourceLogin

### 后续维护

$releaseMaintenanceNotice

### 安装说明

- $_androidInstall
- $_iosInstall
- $_harmonyInstall

$_backup
''';
const currentReleaseNotes = publicReleaseNotes;
const currentReleaseSummary = [
  releaseFreeNotice,
  currentReleaseSourcePolicy,
  releaseReadingNotice,
  ..._changes,
  releaseMaintenanceNotice,
];
const currentReleaseSections = [
  ReleaseSection('本次更新与后续维护', [
    ..._changes,
    releaseMaintenanceNotice,
    _androidInstall,
    _iosInstall,
    _harmonyInstall,
    _backup,
  ]),
];
