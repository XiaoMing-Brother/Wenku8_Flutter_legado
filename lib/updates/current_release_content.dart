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
const _coverPicker =
    '更换封面首屏直接展示推荐图，支持书名关键词、同作者优先与仅同作者筛选、按图片内容去重和长按预览；相册、恢复原封面、文字封面与地址导入收进更多菜单。';
const _titlePage = '新增书籍扉页入口，并重做阅读开篇首屏的封面、书名、作者、类型、上架时间、字数与简介版式。';
const _bookBrowsing =
    '列表滚动时暂停实时玻璃背景，封面改用独立重绘边界并只响应自身封面变化；普通目录按需生成，阅读位置直接映射章节，减少长目录和切页卡顿。';
const _identityAndSource =
    '书源身份索引改为后台编码保存，详情打开不再等待整份索引落盘；书源脚本探测 qread 时的异常可由 Rhino 捕获并回退，Android 阅读页脚安全区不再因导航栏临时显示而跳动。';
const _changes = [_coverPicker, _titlePage, _bookBrowsing, _identityAndSource];
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

- $_coverPicker
- $_titlePage
- $_bookBrowsing
- $_identityAndSource

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
