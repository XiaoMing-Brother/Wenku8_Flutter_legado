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
const _discovery = '发现页接入起点、番茄官网榜单，可直接查看书籍详情、目录和免费章节试读。';
const _reader = '阅读器新增可配置页眉页脚与信息位、可排序的「更多」入口、段评和生效净化总览。';
const _sourceSwitch = '换源支持候选直接切换与批量换源，切换后迁移阅读进度、书签和分类。';
const _bookSourceRules =
    '书源规则增强 JavaScript 数组展开、XPath 属性轴、正文多结果与多页拼接和目录重复标题清理；正文规则升级后会自动忽略旧缓存重新抓取。';
const _splash = '启动书法页支持开关、每日仅显示一次和自定义文字；补充内置替换规则。';
const _changes = [
  _discovery,
  _reader,
  _sourceSwitch,
  _bookSourceRules,
  _splash,
];
const _androidInstall =
    '**Android**：本版为 arm64-v8a 正式构建，包名仍为 legado.wenku，可直接覆盖同包名的旧版；从旧包名迁移时请先备份并手动恢复数据。';
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
- $_splash

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
