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
const _discovery = '发现页补充七猫分类榜与番茄分类书库，官网结果优先展示，跨书源搜索可合并同一本书并实时刷新进度。';
const _reader = '阅读器新增 Legado 内置主题库与主题背景，标题字号、字重、对齐和留白可调，正文支持 0–4 字首行缩进、斜体和更大的页边距范围。';
const _sourceSwitch = '换源支持独立搜索范围与作者校验，候选按书源顺序排列，切换后按章节与阅读比例迁移进度。';
const _bookSourceRules =
    '书源引擎修正跳转后的 baseUrl、url/redirectUrl 与章节标题上下文，提升依赖页面路由和章节变量的书源兼容性。';
const _reviews = '段评补充番茄、七猫来源，显示评论作者与总数；新增发现页书籍扉页和未收藏书籍退出提醒。';
const _releaseNames = '发布附件统一使用 legado-wenku8- 前缀，不再上传旧 wenku8- 名称。';
const _changes = [
  _discovery,
  _reader,
  _sourceSwitch,
  _bookSourceRules,
  _reviews,
  _releaseNames,
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

- $_discovery
- $_reader
- $_sourceSwitch
- $_bookSourceRules
- $_reviews
- $_releaseNames

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
