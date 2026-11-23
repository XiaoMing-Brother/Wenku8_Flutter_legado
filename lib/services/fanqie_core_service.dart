import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:wenku8_flutter/src/rust/api.dart' as rust;
import 'package:wenku8_flutter/src/rust/frb_generated.dart';

/// 番茄内嵌 Rust 核心（novel-sound / fqapi_core）的启动与请求封装。
///
/// 设计要点：
/// - 懒启动：第一次真正用到番茄能力时才 `RustLib.init()` 并起核心，避免拖慢
///   冷启动、也避免旧设备/桌面端因缺少 `.so` 直接闪退。
/// - 运行文件：把 `assets/config/*` 与 `assets/filters/*` 部署到应用支持目录，
///   核心据此读配置、设备池、过滤脚本（与 novel-sound 的 backend_service 等价，
///   但去掉了 LAN/代理/安全存储等本仓库暂不需要的耦合）。
/// - 请求：走 FRB 的 `request()`（进程内 FFI，不经过网络端口），返回原始端点
///   JSON；业务层再解析成模型。
///
/// 失败必须是可降级的：核心没起来时抛 [FanqieCoreException]，调用方应回退到
/// 现有 web 抓取（official_books.dart）而不是崩溃。
class FanqieCoreException implements Exception {
  FanqieCoreException(this.message, {this.statusCode, this.path});

  final String message;
  final int? statusCode;
  final String? path;

  @override
  String toString() => 'FanqieCoreException: $message';
}

class FanqieCoreService {
  FanqieCoreService._();

  static final FanqieCoreService instance = FanqieCoreService._();

  /// 编译期开关：`--dart-define=WENKU_FANQIE_CORE=false` 可整体关闭内嵌核心，
  /// 全部回退到 web 抓取（供测试/未构建 Rust 核心的环境使用）。默认开启。
  static const bool enabled =
      bool.fromEnvironment('WENKU_FANQIE_CORE', defaultValue: true);

  /// 与 assets/config/config.json 的 port 一致；核心绑定失败会自动退化到临时端口。
  static const int _port = 18921;

  /// 单次请求默认超时（毫秒）。章节正文解码在 Rust 侧可能耗时，给足 30s。
  static const int _requestTimeoutMs = 30000;

  static Future<void>? _starting;
  static bool _started = false;
  static int _seq = 0;

  bool get isStarted => _started;

  /// 幂等启动。并发调用共享同一次启动。
  Future<void> ensureStarted() {
    if (_started) return Future<void>.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    if (!enabled) {
      throw FanqieCoreException(
        '内嵌核心已被 WENKU_FANQIE_CORE=false 关闭，请走 web 抓取',
      );
    }
    try {
      await RustLib.init();
    } catch (error) {
      // 热重启/重复初始化时 FRB 会抛；只有「已经初始化」可忽略，其余上抛。
      if (!error.toString().toLowerCase().contains('already')) {
        rethrow;
      }
    }

    final root = await _prepareRuntimeFiles();
    final sep = Platform.pathSeparator;
    final configPath = '${root.path}${sep}config${sep}config.json';
    final poolPath = '${root.path}${sep}config${sep}device_pool.json';
    final filterPath = '${root.path}${sep}config${sep}filter.json';

    final result = await rust.init(
      configPath: configPath,
      poolPath: poolPath,
      filterPath: filterPath,
      runtimeDir: '',
      port: _port,
      lanShare: false,
      mockUpstreamOrigin: '',
    );
    if (result != 'running') {
      throw FanqieCoreException('Rust 核心未能启动：$result');
    }
    _started = true;
  }

  Future<Directory> _prepareRuntimeFiles() async {
    final support = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final root = Directory('${support.path}${sep}fanqie_core');
    final config = Directory('${root.path}${sep}config');
    final filters = Directory('${root.path}${sep}filters');
    await config.create(recursive: true);
    await filters.create(recursive: true);

    // config.json：仅首次写入，保留用户后续改动（如 network_proxy）。
    final cfgFile = File('${config.path}${sep}config.json');
    if (!await cfgFile.exists()) {
      await cfgFile.writeAsString(
        await rootBundle.loadString('assets/config/config.json'),
        flush: true,
      );
    }
    await _copyAsset(
      'assets/config/filter.json',
      File('${config.path}${sep}filter.json'),
    );
    final poolFile = File('${config.path}${sep}device_pool.json');
    if (!await poolFile.exists()) {
      await _copyAsset('assets/config/device_pool.example.json', poolFile);
    }
    for (final name in _filterFiles) {
      await _copyAsset('assets/filters/$name', File('${filters.path}$sep$name'));
    }
    return root;
  }

  static const List<String> _filterFiles = <String>[
    'article.js', 'audio.js', 'author.js', 'book.js', 'chapter.js', 'comment.js',
    'forum_id.js', 'item.js', 'manga.js', 'novel.js', 'rank.js', 'recommend.js',
    'search.js', 'video.js', 'viewer.js',
  ];

  Future<void> _copyAsset(String asset, File dest) async {
    final data = await rootBundle.load(asset);
    await dest.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  String _nextId() => 'wenku-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// 调本地核心的 `/api/v1/*`，返回解析后的 JSON Map。
  ///
  /// [query] 是**不含 `?` 的原始 query 串**（与 `Uri.query` 一致）。
  /// 业务错误（HTTP 200 但 `code != 0`）不在本层抛，交调用方按端点语义判断。
  Future<Map<String, dynamic>> requestJson(
    String method,
    String path, {
    String query = '',
    Object? jsonBody,
  }) async {
    await ensureStarted();
    final body = jsonBody == null
        ? const <int>[]
        : utf8.encode(jsonEncode(jsonBody));
    final resp = await rust.request(
      requestId: _nextId(),
      method: method,
      path: path,
      query: query,
      body: body,
      timeoutMs: _requestTimeoutMs,
    );
    final text = utf8.decode(resp.body, allowMalformed: true);
    if (resp.status >= 400) {
      throw FanqieCoreException(
        '核心返回 HTTP ${resp.status}',
        statusCode: resp.status,
        path: path,
      );
    }
    if (text.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    return <String, dynamic>{'data': decoded};
  }
}
