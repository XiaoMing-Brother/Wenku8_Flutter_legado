import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，请勿购买所谓付费版、激活码或解锁服务。**';
const releaseSponsorLink = '☕ [请我喝杯咖啡 · 爱发电](https://afdian.com/a/mikufoxxx)';
const releaseProjectNotice =
    '本项目为第三方客户端，并非轻小说文库（Wenku8）官方应用，也不运营该站点。在线书目与内容来自轻小说文库，本地书籍由用户自行导入，安装包不附带小说文件。';
const releaseRightsNotice =
    '小说、封面和插图归各自权利人所有。请仅使用有权访问的内容，遵守来源网站规则，不得绕过访问限制、破解 DRM，或未经许可传播、出售内容。';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const releaseMaintenanceNotice = '本构建为个人发布版，后续更新以当前仓库的 Release 为准。';
const _updateSource = '应用内更新检查默认指向当前项目仓库，不再依赖旧镜像。';
const _versionFormat = '版本号支持“主版本.次版本.修订号.日期.时间”格式。';
const _packages = '提供 Android arm64-v8a、armeabi-v7a、x86_64 与 universal 安装包。';
const _changes = [_updateSource, _versionFormat, _packages];
const _androidInstall = '**Android**：同签名版本可直接覆盖更新；签名不同请先备份再卸载旧版。';
const _iosInstall = '**iOS**：本次未提供 IPA。';
const _harmonyInstall = '**HarmonyOS**：本次未提供 HAP。';
const _backup = '升级、整理存储或同步前，请先备份重要书籍和阅读记录。';
const publicReleaseNotes =
    '''
### 免费使用，请勿付费

$releaseFreeNotice

$releaseSponsorLink

$releaseProjectNotice

$releaseRightsNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### 本次更新

- $_updateSource
- $_versionFormat
- $_packages

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
  releaseSponsorLink,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  ..._changes,
  releaseMaintenanceNotice,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    releaseFreeNotice,
    releaseSponsorLink,
    releaseProjectNotice,
    releaseRightsNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('本次更新与后续维护', [
    ..._changes,
    releaseMaintenanceNotice,
    _androidInstall,
    _iosInstall,
    _harmonyInstall,
    _backup,
  ]),
];
