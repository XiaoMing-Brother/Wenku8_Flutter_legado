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
const _bookSourceRules =
    '书源目录支持串行与并列翻页、分卷、VIP 标记和标题格式化；元素规则新增方括号选取与排除，搜索和发现共用分页判断。';
const _cookies = '书源 Cookie 按来源与目标站点隔离，匹配路径和有效期，WebView 登录按 Cookie 路径回收。';
const _validation = '书源管理新增当前列表与所选书源校验，可检查详情、目录和第一章正文；书源行可展开发现榜单。';
const _discovery = '发现页接入七猫、书旗官方榜单，榜单按分类缓存五分钟；搜索并行查询官方站与已启用书源，官方命中优先。';
const _fanqie = '番茄关键词搜索改用无需签名的接口，并新增独立字体映射还原书名、作者和简介。';
const _covers = '图书详情支持更换封面，可选本机图片、图片地址、默认文字封面或恢复原封面；新增封面图集与磁盘缓存。';
const _reviews = '阅读器支持正文段评标记与网页段评弹层，段评数量未知时气泡显示「评」。';
const _replaceRules = '替换规则按 Legado 语义匹配书名或来源，标题与正文开关独立，并保留规则顺序。';
const _details = '详情页和「我的」页统一打开书籍详情，未收藏退出时默认提示加入书架，本地书也可使用完整菜单。';
const _changes = [
  _bookSourceRules,
  _cookies,
  _validation,
  _discovery,
  _fanqie,
  _covers,
  _reviews,
  _replaceRules,
  _details,
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

- $_bookSourceRules
- $_cookies
- $_validation
- $_discovery
- $_fanqie
- $_covers
- $_reviews
- $_replaceRules
- $_details

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
