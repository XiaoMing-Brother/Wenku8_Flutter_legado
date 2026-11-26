import 'dart:async';

import 'package:flutter/widgets.dart';

/// 首帧先布局封面与占位内容，目录处理和内容落地留到切页动画结束。
/// 网络详情请求可提前启动；退出中的页面释放等待后跳过后续工作。
Future<bool> waitForRouteEntry(BuildContext context) async {
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return false;
  final route = RouteIdentity.read(context);
  final animation = route?.animation;
  if (animation != null && animation.status != AnimationStatus.completed) {
    final settled = Completer<void>();
    void changed(AnimationStatus status) {
      if ((status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) &&
          !settled.isCompleted) {
        settled.complete();
      }
    }

    animation.addStatusListener(changed);
    try {
      await Future.any([settled.future, route!.completed]);
    } finally {
      animation.removeStatusListener(changed);
    }
  }
  return context.mounted &&
      (route == null || route.isActive) &&
      (animation == null || animation.status == AnimationStatus.completed);
}

/// An event can read its existing route without subscribing the triggering page
/// to every later route-focus change. The route itself remains the authority.
class RouteIdentity extends InheritedWidget {
  const RouteIdentity({super.key, required this.route, required super.child});

  final ModalRoute<dynamic>? route;

  static ModalRoute<dynamic>? read(BuildContext context) {
    final route = context.getInheritedWidgetOfExactType<RouteIdentity>()?.route;
    // An embedded Navigator has its own routes; it must not borrow the outer
    // page's origin, slot ownership, or focus state.
    if (route != null && route.navigator == Navigator.maybeOf(context)) {
      return route;
    }
    return ModalRoute.of(context);
  }

  @override
  bool updateShouldNotify(RouteIdentity oldWidget) => route != oldWidget.route;
}
