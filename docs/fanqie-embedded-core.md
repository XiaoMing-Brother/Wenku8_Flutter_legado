# 番茄内嵌 Rust 核心（route A）——集成说明

> 目标：把 [ch6vip/novel-sound](https://github.com/ch6vip/novel-sound) 的 Rust 原生核心
> （crate `fqapi_core`，GPL-3.0）以 `flutter_rust_bridge` 2.13.0 方式内嵌进本仓库，
> 让番茄的**搜索 / 榜单 / 段评 / 正文**走官方 App 协议，替代现有的 web 抓取
> （`lib/official_books.dart` 的 `_fanqieSearch` / `_fanqieContent`、
> `lib/book_sources/fanqie_review_service.dart`），从而「番茄的书基本不需要别的书源」。

## 1. 架构与数据流

```
Flutter (Dart)                   进程内                    Rust (fqapi_core)
──────────────────────────────────────────────────────────────────────────
FanqieCoreSource ──► FanqieCoreService ──► rust.request() ──► dispatch ──► endpoints/*
   (业务适配)          (启动/资产部署)         (FRB FFI)          │            │
                                                                 └── upstream/*（签名反爬 + 设备池轮换）
                                                                     sign/*（x-argus/x-gorgon/x-ladon/a_bogus）
                                                                     device/*（注册/持久化设备池）
```

- **不经过网络端口**：Dart 用 FRB 的 `request()` 直接调进程内 dispatch（`rust/src/api/mod.rs`）。
  核心同时会起一个本地回环 HTTP（`rust/src/server.rs`，`/src/*` 资源用），但业务请求走 FFI。
- **签名/解密全在 Rust**：`x-argus`/`x-gorgon`/`x-ladon`/`a_bogus`、设备注册池、AES/DH/CM 解密，
  Dart 只传 `method/path/query/body`。

## 2. 目录/文件清单（本分支已落）

| 路径 | 说明 |
|---|---|
| `rust/` | 原样 vendored 的 `fqapi_core` crate（114 文件，含 `Cargo.toml`/`Cargo.lock`/`build.rs`） |
| `lib/src/rust/` | FRB 生成的 Dart 绑定（`api.dart` / `frb_generated.dart` / `frb_generated.io.dart`），与 vendored crate 同源同版 |
| `flutter_rust_bridge.yaml` | codegen 配置（`rust_root: rust/`，`dart_output: lib/src/rust`） |
| `assets/config/` | `config.json`（port=18921）、`filter.json`、`device_pool.example.json` |
| `assets/filters/` | 端点过滤脚本（`filter.json` 引用 `filters/*.js`） |
| `scripts/build_rust_backend.ps1` / `.sh` | codegen + NDK 交叉编译 + 落 `.so` 到 `jniLibs/<abi>` |
| `lib/services/fanqie_core_service.dart` | 懒启动 + 运行文件部署 + `request()` 封装 |
| `lib/services/fanqie_core_source.dart` | 业务适配：搜索/榜单/段评/正文 |
| `android/app/src/main/jniLibs/.gitignore` | 忽略编译产物 `.so` |

`pubspec.yaml` 已加：依赖 `flutter_rust_bridge: 2.13.0`；资产 `assets/config/`、`assets/filters/`。

## 3. 构建步骤（在**你的构建机**，本沙箱无 cargo/flutter）

前置：Rust 工具链（含 `cargo`）、`flutter_rust_bridge_codegen` 2.13.0、Android NDK **28.2.13676358**、Flutter。

```powershell
# 1) 安装与 crate 同版的 codegen（只需一次）
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked

# 2) 生成绑定 + 交叉编译 arm64/armv7，并落 .so 到 android/app/src/main/jniLibs/
#    脚本会先跑 flutter_rust_bridge_codegen generate，再 cargo build --target ...
pwsh -NoProfile -File .\scripts\build_rust_backend.ps1

# 3) 正常构建 APK（.so 由 AGP 从 jniLibs 自动打包）
flutter build apk --split-per-abi --target-platform=android-arm64
```

> 说明：
> - 本分支已自带与 crate 同源的 `lib/src/rust/` 绑定，**可先用 `-SkipCodegen` 跳过程序生成**；
>   改动 `rust/src/api` 的对外签名后再重跑 codegen。
> - `build_rust_backend.ps1` 固定 NDK 28.2.13676358，其它版本会硬报错。
> - 若你的 `flutter.ndkVersion` 不同，需保证机器上安装了 28.2.13676358（脚本按此版本找）。

### 构建验证记录（本机实测，2026-11）

- `flutter pub get` ✅（`flutter_rust_bridge: 2.13.0` 解析通过，无冲突）；`flutter analyze`（4 个改动文件）✅ **No issues found**。
- Rust 交叉编译需 **rustc ≥ 1.88**（依赖 `icu_* 2.3.0` 要求）；本机用 **1.100.0** 成功（旧 1.87 会报 icu 需 1.88）。
- Windows 宿主需 MSVC 链接器：先 `call vcvars64.bat` 再跑 `build_rust_backend.ps1`，否则报 `linker link.exe not found`。
- NDK `28.2.13676358`：arm64-v8a 与 armv7 `.so` 均产出（6.9MB / 4.5MB）。
- `flutter build apk --split-per-abi --target-platform=android-arm64` ✅ 生成
  `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，包内含 `lib/arm64-v8a/libfqapi_core.so`
  与 `assets/flutter_assets/assets/config|filters/*`。

### 真机运行验证（Xiaomi 23127PN0CC / Android 16 / arm64-v8a）

- `.so` 加载 + 核心初始化成功：logcat `fqapi_core::api: core init: port=18921 ...`、`[FQ] rust.init => running`。
- 设备池工作：`fqapi_core::device: saving device pool unencrypted`。
- 番茄榜单目录经核心拉取：`catalog cell=7098235271900037133 tabs=4`（真实首页 `rank_with_category_data`）。
- **正文经核心解密成功**：第 1 章 `id=7694519738617053721 len=2288 snip=苍穹之上，劫云密布。`
- **番茄榜单已改为动态目录**：发现页番茄「排行榜」直接渲染官方 `rank_with_category_data`
  的 `推荐榜/完本榜/巅峰榜/口碑榜` 与子分类（全部/穿越/系统/都市/现代言情…），条目走核心
  `cell/change`，中文正常无 □（真机已验证）。写死的旧榜已移除，核心不可用时显示加载失败与重试。

## 4. 端点映射（Dart 适配层 ↔ Rust handler）

| 能力 | 适配层方法 | 本地路由 | Rust 源 |
|---|---|---|---|
| 书籍搜索 | `search(query,page)` | `GET /api/v1/search` | `endpoints/search.rs`（fqnovel reading search） |
| 搜索联想 | `searchSuggestions` | `GET /api/v1/search/suggest` | `search.rs` |
| 热搜 | `hotSearch()` | `GET /api/v1/search/hot` | `search.rs`（rank_list show_type=472） |
| 分类页 | `categoryFront(tab)` | `GET /api/v1/category` | `search.rs`（new_category/front） |
| 榜单条目 | `rank(id,algo,subInfoId)` | `GET /api/v1/rank/{id}` | `author.rs`（bookmall/cell/change） |
| 榜单目录 | 解析首页 `rank_with_category_data` | — | 见 `models/rank.dart` |
| 详情 | `bookDetail(id)` | `GET /api/v1/books/{id}/detail` | `book.rs` |
| 目录 | `directory(id)` | `GET /api/v1/books/{id}/directory` | `book.rs`（directory/all_items） |
| 段评计数 | `chapterIdeas(itemId,itemVersion)` | `GET /api/v1/chapters/{id}/reviews` | `comments.rs`（idea_list） |
| 段落评论 | `paragraphComments(bookId,itemId,...)` | `GET /api/v1/books/{id}/reviews` | `comments.rs`（channel **38**） |
| 正文 | `chapterText(itemId)` | `GET /api/v1/chapters/{id}/novel` + 兜底 `/chapters/{id}` | `dhcontent.rs` / `content.rs` |

关键实战结论（照抄即可）：
- 段落评论 `server_channel` 必须 **38**（43 永远 total=0，39 只对部分书）。
- 段落评论三要素 `book_id` + `item_version` + `para_index` 缺一上游报 `103001`；
  `group_id`=章节 item_id，`business_param.book_id`=真实书 id，`group_type=15`。
- 搜索分页靠 `offset`；榜单靠 `algo_type`(rank_algo) + `rank_sub_info_id`(子分类 id)。

## 5. 付费 / VIP 章节行为（重要）

核心**不做付费墙破解**（其 `CONTRIBUTING.md`/`README` 明确「不绕过上游付费与权限控制」）。
正文取不到（付费/VIP/受限/空章）时，`chapterText` 抛 `FanqieContentUnavailable`，
调用方按「仅提供试读 / 请到官方阅读」提示，与现有 web 版 `[[FANQIE_LOCKED]]` 语义一致。
换言之：这条路线能拿到**免费范围**内的完整正文（比 web 抓取干净、覆盖更全、无 a_bogus 限制），
但**不会解锁真正付费的章节**——不要指望它白嫖 VIP。

## 6. 接线状态（本分支）

**已接线（核心优先 → 失败/缺失降级 web，未编译核心时行为与改动前完全一致）：**

- **正文**：`official_books.dart` 的 `_fanqieContent` → `_fanqieCoreContent`。
  核心可用时用 DH/AES 解出的纯文本；取不到正文（付费/VIP/受限）返回
  `[[FANQIE_LOCKED]]`，直接复用既有 `book_source_repository.dart` 的试读提示。
  任何 `FanqieCoreException`（未构建/初始化失败）→ 原 web 抓取。
- **搜索**：`_fanqieSearch` → `_fanqieCoreSearch`。用容忍式递归抽取
  （`_booksFromCoreRecords`）把核心返回体映射为 `OfficialBook`；解析为空或异常
  → 原 v0 web 搜索。
- **段评**：`fanqie_review_service.dart` 的 `fetch` → `_tryCoreReview`。
  先取每段 idea 计数（`chapterIdeas`，含 `item_version`），再对命中段落拉
  `paragraphComments`（`server_channel=38` 配方），映射为 `ParagraphReview`；
  核心无数据/异常 → 原 web `idea_list`/`comment_list` 抓取。
- **榜单（动态目录，不再写死）**：发现页番茄榜优先调 `OfficialBookService.fanqieRankCatalog()`
  → `FanqieCoreSource.rankCatalog()` 从首页 `rank_with_category_data` 生成榜列表（`推荐榜/完本榜/
  巅峰榜/口碑榜`）与子分类；每个榜用 `OfficialRanking(cellId, algo)` 携带，`_fanqieRanking` 走
  `rankEntries(cellId, algo)` 取 `cell_view.cell_data[].book_data`。已移除写死的旧榜和 web
  `/api/rank/category/list` 回落；核心不可用时页面显示失败态，可下拉或点重试重新拉取目录。

**已知限制：**
- 番茄榜 tab/子分类只来自 core 首页目录（`rank_with_category_data`）；核心不可用时不再展示
  旧榜，只显示失败态。目录缓存在进程内，官方改版后重启 App 生效。
- 目录 tab 与子分类随账号/性别卡（`tab_type`/`req_rank_category_id`）返回，可能因卡不同而不同；
  如需固定性别可调 `rankCatalog(tabType)` 参数。

**统一模式**：搜索、段评等能力核心优先 → 解析失败/核心缺失 → 现有 web 逻辑；榜单只走核心，
目录或条目失败时展示失败态，不回落到旧榜。
可用 `--dart-define=WENKU_FANQIE_CORE=false` 整体关闭核心（测试/无 Rust 构建环境）。

## 7. 许可与维护

- **许可已统一为 GPL-3.0**：根 `LICENSE` 原先落单为 GPL-2.0 文本，但 `README` 徽章、`NOTICE`
  与 `assets/licenses/GPL-3.0.txt` 早已声明 GPL-3.0。本分支已把根 `LICENSE` 换成 GPL-3.0 全文，
  与 novel-sound（GPL-3.0）**直接兼容**，无需再纠结 2.0-only 的不兼容问题；保留其署名（见
  `NOTICE`）。`rust/src/sign/v5.rs` 另转自 `N3urda/hongguoTV`(GPL-3.0)，署名一并保留。
  - 附注：项目内含 Apache-2.0 依赖（okhttp/pdfbox/poi/opencc 等），Apache-2.0 与 **GPL-2.0 不兼容、
    与 GPL-3.0 兼容**，这进一步说明 GPL-3.0 才是本仓库正确的整体许可。
  - 附注：`juniversalchardet` 若要严格并入 GPL-3.0，应选择其 **GPL-2.0-or-later** 授权分支
    （而不是 MPL-1.1，MPL-1.1 与 GPL 不兼容）。
  - 若仓库存在你之外的版权贡献者，改整体许可前需取得其同意；个人/自有仓库则直接改即可。
- 维护成本：`version_code/version_name/UA/密钥` 均硬编码在 `rust/src/endpoints/*` 与
  `rust/src/config.rs`，上游 App 版本一变就要跟版；签名与设备注册是长期维护重点。
  把「跟版参数」集中到 `assets/config/config.json` 的 `upstream` 段可减少发版。

## 8. 冒烟验证（构建出 .so 后）

```dart
final src = FanqieCoreSource.shared();
final r = await src.search('斗罗大陆');
// r['data'] 里即 fqnovel 搜索原始结构；用现有 parseSearchTabs 解析。
final text = await src.chapterText('<某个免费章节 item_id>');
```

失败路径：核心未就绪 → 抛 `FanqieCoreException('...')`，应被 UI 降级捕获。
