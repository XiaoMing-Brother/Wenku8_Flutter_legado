/// Public presentation code depends on domain models, not a service protocol.
class OnlineComponentUnavailable implements Exception {
  const OnlineComponentUnavailable();
  static const message = '此源码构建未包含在线组件，可继续使用本地导入与阅读';
  @override
  String toString() => message;
}

Future<T> unavailableOnline<T>() =>
    Future<T>.error(const OnlineComponentUnavailable());
