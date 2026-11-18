# 书源适配

书源采用两层结构：

1. Android 原生引擎（`android/.../booksource/`）解析 Legado 规则并执行网络请求。
2. Flutter 适配层（`lib/book_sources/`）负责 JSON 校验、来源存储、整数书籍 ID、章节 ID、离线缓存与现有阅读器格式转换。

Flutter 不解析 `ruleSearch`、`ruleBookInfo`、`ruleToc` 或 `ruleContent`。新增规则支持应修改原生解析器，避免形成第二套书源规则。

## 已接入

- 单个书源对象、书源数组、`sources` / `bookSources` 包装对象导入，书源总量上限 10000 个。
- 从 `http` / `https` 链接直接下载书源 JSON 导入，单文件上限 128 MB；返回网页的链接会被拒绝。
- 文字类型 `bookSourceType: 0`；文件类型 `3` 目前按文字规则尝试解析。
- 搜索、详情、目录、正文；正文 `nextContentUrl` 多页拼接。
- 搜索并发查询当前范围内已启用且支持搜索的书源，结果渐进显示；单个来源超时不会中断其他来源，新搜索或离开搜索页会取消上一轮未完成请求。
- 搜索范围可切换为全部书源、一个或多个分组，或指定书源；范围只影响导入书源，不影响轻小说文库结果。范围会持久化，并在下一次搜索时生效。
- 发现页读取已启用书源的 `exploreUrl`，支持 Legado 发现入口、分类、筛选条件、分页、`exploreUrl` 联合规则和发现动作；未填写 `exploreUrl` 的来源仍可用于搜索。
- 换源使用独立的全来源同名检索，可开启/关闭作者校验；候选按章节数排序，搜索进度逐来源更新，换源后沿用原有的章节标题/序号定位阅读进度。
- 书源管理支持按名称、链接、分组搜索，按启用状态/分组筛选，按导入顺序/名称/最近更新/启用状态排序，以及多选批量启用、停用、删除、导出和加入/移出分组。
- 单个书源可编辑名称、分组、搜索地址、发现地址、启用状态和发现开关；源地址作为书源身份保持不变，其他未展示的 Legado 字段继续原样保留。
- CSS/jsoup 选择器、`tag.` / `class.` / `id.` 写法、`@text` / `@html` / 属性提取与 `!N` 索引。
- JSONPath（`$.`、`@json:`）、XPath（`//`、`@xpath:`）、正则（`@regex:`）和 JavaScript（`@js:`）。
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
