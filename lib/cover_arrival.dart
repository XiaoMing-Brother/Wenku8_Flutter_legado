import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'archive_motion.dart';
import 'route_identity.dart';

/// Wait for a decoded frame, then replace the static skeleton with one shallow
/// diagonal cut. Recycled rows and Hero destinations reuse the presented frame.
class CoverArrival extends StatefulWidget {
  const CoverArrival({
    super.key,
    required this.bytes,
    required this.ready,
    required this.placeholder,
    required this.child,
    this.recordArrival = true,
    this.fade = false,
  });

  final Uint8List bytes;
  final bool ready;
  final Widget placeholder;
  final Widget child;
  final bool recordArrival;
  final bool fade;

  // Weak keys follow the byte cache lifetime; this is not another cover cache.
  static final _presented = Expando<bool>('presented-cover-frame');
  static bool wasPresented(Uint8List bytes) => _presented[bytes] == true;

  @override
  State<CoverArrival> createState() => _CoverArrivalState();
}

class _CoverArrivalState extends State<CoverArrival>
    with SingleTickerProviderStateMixin {
  AnimationController? _clock;
  ModalRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  Animation<double>? _coveringAnimation;
  ValueListenable<TickerModeData>? _tickerMode;
  bool _started = false;
  bool _done = false;
  bool _queued = false;
  bool _hasFrame = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = RouteIdentity.read(context);
    _watchActivity();
    _prepare();
  }

  void _watchActivity() {
    final animation = _done ? null : _route?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeChanged);
    }
    final covering = _done ? null : _route?.secondaryAnimation;
    if (_coveringAnimation != covering) {
      _coveringAnimation?.removeStatusListener(_covered);
      _coveringAnimation = covering;
      covering?.addStatusListener(_covered);
    }
    final mode = _done ? null : TickerMode.getValuesNotifier(context);
    if (_tickerMode != mode) {
      _tickerMode?.removeListener(_activityChanged);
      _tickerMode = mode;
      mode?.addListener(_activityChanged);
    }
  }

  void _covered(AnimationStatus status) {
    if (mounted && !_done) {
      if (_started && _route?.isCurrent == false) {
        setState(_finish);
      } else if (status == AnimationStatus.dismissed) {
        setState(_prepare);
      }
    }
  }

  void _activityChanged() {
    if (mounted && !_done && _tickerMode?.value.enabled == true) {
      setState(_prepare);
    }
  }

  @override
  void didUpdateWidget(CoverArrival oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes)) {
      _clock?.stop();
      _clock?.value = 0;
      _started = false;
      _done = false;
      _hasFrame = false;
      _watchActivity();
    }
    _prepare();
  }

  void _routeChanged(AnimationStatus status) {
    if (mounted && status == AnimationStatus.completed) {
      setState(_prepare);
    }
  }

  void _finish() {
    _clock?.stop();
    _done = true;
    // 已展示的封面不再监听切页和页签状态，避免整屏封面跟着重建。
    _watchActivity();
    if (widget.recordArrival) CoverArrival._presented[widget.bytes] = true;
  }

  void _prepare() {
    // Image's gapless replacement retains the old pixels while a new decode
    // size resolves, but frameBuilder temporarily reports frame == null.
    // Those pixels must not be covered by the skeleton again.
    _hasFrame |= widget.ready;
    if (!_hasFrame || _done) return;
    if (!widget.recordArrival) {
      _finish();
      return;
    }
    if (CoverArrival.wasPresented(widget.bytes) ||
        MediaQuery.disableAnimationsOf(context)) {
      _finish();
      return;
    }
    if (_started || _queued || !_routeReady) return;
    _queued = true;
    // A newly attached Hero route can briefly report completed before its
    // actual push starts. Recheck after that first frame, never during flight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted && _hasFrame && !_done && !_started && _routeReady) {
        setState(_start);
      }
    });
  }

  bool get _routeReady =>
      _tickerMode?.value.enabled != false &&
      _route?.isCurrent != false &&
      (_routeAnimation == null ||
          _routeAnimation!.status == AnimationStatus.completed);

  void _start() {
    _started = true;
    _clock ??=
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 420),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(_finish);
          }
        });
    _clock!.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFrame || (!_started && !_done)) return widget.placeholder;
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.placeholder,
        if (widget.fade)
          FadeTransition(
            key: const ValueKey('cover-arrival-fade'),
            opacity: _clock!.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: RepaintBoundary(child: widget.child),
          )
        else
          ArchivePlaneTransition(
            key: const ValueKey('cover-arrival-plane'),
            animation: _clock!,
            child: RepaintBoundary(child: widget.child),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeChanged);
    _coveringAnimation?.removeStatusListener(_covered);
    _tickerMode?.removeListener(_activityChanged);
    _clock?.dispose();
    super.dispose();
  }
}
