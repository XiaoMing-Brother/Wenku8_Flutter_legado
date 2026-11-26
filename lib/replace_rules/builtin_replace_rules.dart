import 'replace_rule.dart';

/// 内置净化规则包（Legado 风格），供「替换净化」一键导入。
///
/// 全部为常见站点广告/水印/多余空行的保守规则，只改变阅读页显示、不改写缓存
/// 正文；导入后进入规则库，用户可继续编辑、停用或删除。`id` 固定，重复导入会被
/// 当作更新而非重复新增（`ReplaceRuleStore.importText` 按 id 合并）。
List<ReplaceRule> builtinReplaceRules() => const [
  ReplaceRule(
    id: 'builtin-ad-tail',
    name: '删“本章未完 / 点击下一页”提示',
    group: '内置净化',
    pattern: r'(本章未完[^\n]*|请(?:点击|收藏)下一页[^\n]*|点击下一页继续阅读[^\n]*|請點擊下一頁[^\n]*)',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 0,
  ),
  ReplaceRule(
    id: 'builtin-site-ad-line',
    name: '删站点广告行',
    group: '内置净化',
    pattern:
        r'^[ \t]*(?:请收藏本站|记住本站|笔趣阁|顶点小说|新笔阁|最新章节|手机版阅读网址)[^\n]*$',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 10,
  ),
  ReplaceRule(
    id: 'builtin-pirate-banner',
    name: '删盗版站横幅（全本/精校/TXT 下载 + 网址）',
    group: '内置净化',
    // 典型："本站发的所有小说都是全本-完结-精校-校对 的无错TXT小说下载 : http://..."
    pattern:
        r'^[ \t]*(?:本站|本网站|本书|更多).{0,60}?(?:全本|完结|精校|校对|免费|TXT|txt|小说).{0,60}?(?:下载|https?://|www\.|\.com).{0,200}$',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 5,
  ),
  ReplaceRule(
    id: 'builtin-separator-line',
    name: '删纯分隔线（整行 = - — * _ 等重复）',
    group: '内置净化',
    // 仅匹配"整行只由分隔符组成"，不会误删 `=== 第2话 标题 ===` 这类带文字的装饰标题。
    pattern: r'^[ \t]*[=\-—–*_~#]{3,}[ \t]*$',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 6,
  ),
  ReplaceRule(
    id: 'builtin-bare-url-line',
    name: '删整行裸网址',
    group: '内置净化',
    pattern: r'^[ \t]*(?:https?://|www\.)\S+[ \t]*$',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 7,
  ),
  ReplaceRule(
    id: 'builtin-mobile-url',
    name: '删手机版网址尾巴',
    group: '内置净化',
    pattern: r'(手机版阅读网址|m\.[a-z0-9]+\.(?:com|net|org))[^\n]*',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 20,
  ),
  ReplaceRule(
    id: 'builtin-blank-lines',
    name: '合并多余空行',
    group: '内置净化',
    pattern: r'\n{3,}',
    replacement: '\n\n',
    scopeContent: true,
    scopeTitle: false,
    order: 30,
  ),
  ReplaceRule(
    id: 'builtin-trailing-space',
    name: '去掉行尾空白',
    group: '内置净化',
    pattern: r'[ \t]+$',
    replacement: '',
    scopeContent: true,
    scopeTitle: false,
    order: 40,
  ),
];
