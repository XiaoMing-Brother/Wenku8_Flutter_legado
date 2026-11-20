# 书源适配

书源采用两层结构：

1. Android 原生引擎（`android/.../booksource/`）解析 Legado 规则并执行网络请求。
2. Flutter 适配层（`lib/book_sources/`）负责 JSON 校验、来源存储、整数书籍 ID、章节 ID、离线缓存与现有阅读器格式转换。

Flutter 不解析 `ruleSearch`、`ruleBookInfo`、`ruleToc` 或 `ruleContent`。新增规则支持应修改原生解析器，避免形成第二套书源规则。

## 已接入

- 单个书源对象、书源数组、`sources` / `bookSources` 包装对象导入，书源总量上限 10000 个。
- 从 `http` / `https` 链接直接下载书源 JSON 导入，单文件上限 128 MB；返回网页的链接会被拒绝。
- 文字类型 `bookSourceType: 0`；文件类型 `3` 目前按文字规则尝试解析。
- 搜索、详情、目录、正文；正文规则返回多条结果时全部拼接，`nextContentUrl` 支持并列多页与串行翻页（最多 100 页），下一页命中下一章时熔断；正文开头与目录重复的章节标题会被剥离，由阅读器单独渲染章节头。正文提取规则升级后，联网阅读会忽略旧版缓存重新抓取一次，离线仍可读旧缓存。
- 搜索并发查询当前范围内已启用且支持搜索的书源，结果渐进显示；单个来源超时不会中断其他来源，新搜索或离开搜索页会取消上一轮未完成请求。
- 搜索范围可切换为全部书源、一个或多个分组，或指定书源；范围只影响导入书源，不影响轻小说文库结果。范围会持久化，并在下一次搜索时生效。
- 发现页读取已启用书源的 `exploreUrl`，支持 Legado 发现入口、分类、筛选条件、分页、`exploreUrl` 联合规则和发现动作；未填写 `exploreUrl` 的来源仍可用于搜索。
- 发现页默认直接展示榜单：优先排列名称或地址包含起点、番茄的书源，自动读取其榜单入口并加载书籍，不再先显示书源卡片列表；其他带发现地址的书源作为补充来源。
- 换源使用独立的全来源同名检索，可开启/关闭作者校验；候选按章节数排序，搜索进度逐来源更新。选中候选后直接切换，不再显示迁移确认；封面采用新书源，作者名保持本书原值，阅读进度、书签、分类与阅读配置按书保留。
- 书源管理支持按名称、链接、分组搜索，按启用状态/分组筛选，按导入顺序/名称/最近更新/启用状态排序，以及多选批量启用、停用、删除、导出和加入/移出分组。
- 单个书源可编辑名称、分组、搜索地址、发现地址、启用状态和发现开关；源地址作为书源身份保持不变，其他未展示的 Legado 字段继续原样保留。
- CSS/jsoup 选择器、`tag.` / `class.` / `id.` 写法、`@text` / `@html` / 属性提取与 `!N` 索引。
- JSONPath（`$.`、`@json:`）、XPath（`//`、`@xpath:`，含 `//a/@href` 属性轴）、正则（`@regex:`）和 JavaScript（`@js:`）；JS 规则返回数组时会逐项展开，避免多段正文或多个下一页地址只取到第一项。
- `jsLib` 支持内联 JavaScript，以及 `{"名称":"https://..."}` 形式的远程脚本映射；远程脚本会在当前进程内缓存，加载失败时显示具体行和该行代码。
- `{{key}}`、`{{page}}`、`{{baseUrl}}` 以及通用 `{{JS 表达式}}`。
- 请求头、POST 表单/JSON、Cookie、编码检测；搜索地址支持多行回退。
- 书源封面和正文插图通过原生桥加载，复用书源请求头与 Cookie；正文插图可离线缓存。
- `java.get` / `java.post` 返回带 `body()`、`statusCode`、`url`、`headers()` 的响应对象。
- 表单登录：解析 `loginUi`（含 `@js:`、`<js>` 动态表单）和 `loginUrl`，支持 `text`、`password`、`select`、`toggle`、`button` 行；登录后自动保存登录 Header 与 Cookie，并在后续搜索、详情、目录、正文和图片请求中自动携带。
- 登录信息、登录 Header 和 Cookie 使用 Android Keystore 加密保存；书源管理页的更多菜单可登录或退出登录，发现页长按书源卡片标题区域也可打开登录弹层。
- 应用内 WebView 网页登录：当书源有 `loginUrl` 但没有可解析的 `loginUi` 时，可打开登录页完成账号密码、验证码和网页内跳转；返回后只保存 Cookie，不保存网页中输入的账号密码。
- `loginCheckJs` 会在搜索、发现、详情、目录和正文响应后执行，可读取 `result.body()`、`result.url`、`result.statusCode` 和 `source.getLoginHeader()`，并通过 `source.putLoginHeader()`、`java.connect()` 刷新登录 Header 或重新请求；书源更多菜单提供“运行登录检测”手动执行一次。

音频、图片、视频书源会保留在管理页但标记为暂不支持。下载型文件规则、漫画图片规则和书源调试器尚未接入。网页登录暂不完整支持 WebView 弹窗/多窗口、部分扫码或依赖外部 App 的回调；`loginCheckJs` 兼容 Legado 的“执行脚本并修正响应”语义，但不同书源不一定会返回统一的登录成功/失效字段，因此“运行登录检测”成功只表示脚本已执行，不能保证所有来源都能明确判断账号状态。

脚本引擎使用 Rhino 1.8.1，与参考 Legado 实现一致，但仍不支持部分 ES2015+ 语法（例如 `class`、`async/await`、`f(...args)` 展开调用、对象剩余/展开解构）。使用这些语法的 `jsLib` 会读取失败，并在错误信息中显示具体行号与该行代码；这不是登录问题。

## 官网榜单（发现页直连）

发现页的起点、番茄榜单由 `lib/official_books.dart` 直接请求官网接口，不经过书源规则，也不会出现在书源管理列表里。

- `起点`：9 个榜单，接口为移动站 `/webcommon/rank/*list`（桌面站由 WAF 拦截）；每页 20 本，用 `pageNum` 翻页。
- `番茄`：推荐榜与更新榜，接口为 `/api/rank/recommend/list`、`/api/rank/recent/update/list`；更新榜用 offset 翻页。

点击榜单书籍直接进入官方详情页：封面、书名、作者、标签、简介、目录和状态来自官网 SSR，起点还会显示字数。正文只提供免费章节试读；起点 VIP 章节（`vipStatus=1`）和番茄锁定章节（`isChapterLock=true`）会提示换源。番茄免费章节正文使用随机字体把部分汉字映射到私用区，按 `assets/book_sources/fanqie_font_map.json` 还原；字体文件变化时需要重新生成该映射。

旧版本曾把起点/番茄作为内置书源写入书源库；`BookSourceRepository.builtinSourcesVersion` 升到 `4` 后，升级会清理这两个旧内置来源，`assets/book_sources/builtin_sources.json` 保持为空。

## 数据位置

- 书源：应用支持目录 `/wenku8-book-sources-v1/sources.json`
- 搜索范围：同目录 `/search_scope.json`
- 书源书籍身份：同目录 `/identities.json`
- 书源书籍 ID：`0x50000000` 到 `0x5FFFFFFF`
- 书单待匹配占位书 ID：`0x40000000` 到 `0x4FFFFFFF`；导入后先加入书架，点开时匹配书源并替换
- 本地导入书籍 ID 从 `0x60000000` 开始
- 登录信息、登录 Header、Cookie：Android `SharedPreferences` 中由 Android Keystore 加密的密文；旧版明文变量会在首次读取时自动迁移并删除明文

## 验证

无 Android 原生构建环境时，至少检查：

```powershell
flutter analyze
flutter test
```

并在一台 Android 设备上导入一个文字书源，分别验证搜索、详情、目录、正文和断网后的已缓存章节。

## 安全边界

书源规则中的 JavaScript 与 Legado 一样可以访问 Java 类并发起网络请求；应用也为用户书源放开了 HTTP。只应导入可信来源，不要把未知书源当作纯数据文件处理。
