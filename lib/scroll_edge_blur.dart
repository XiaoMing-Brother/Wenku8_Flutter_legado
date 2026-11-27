import 'dart:async';

import 'package:flutter/material.dart';

import 'native_effects.dart';
import 'dock_layout.dart';

/// Pauses live backdrops while the nearest page is moving. A short resume
/// delay avoids paying the blur cost in the same frame that ends a fling.
class ScrollBackdropPause extends StatefulWidget {
  const ScrollBackdropPause({
    super.key,
    required this.child,
    this.resumeDelay = const Duration(milliseconds: 180),
  });

  final Widget child;
  final Duration resumeDelay;

  @override
  State<ScrollBackdropPause> createState() => _ScrollBackdropPauseState();
}

class _ScrollBackdropPauseState extends State<ScrollBackdropPause> {
  Timer? _resume;
  bool _paused = false;

  void _setPaused(bool value) {
    _resume?.cancel();
    if (!mounted || _paused == value) return;
    setState(() => _paused = value);
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    _resume?.cancel();
    if (notification is ScrollEndNotification) {
      _resume = Timer(widget.resumeDelay, () => _setPaused(false));
    } else {
      _setPaused(true);
    }
    return false;
  }

  @override
  void dispose() {
    _resume?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollBackdropScope(
    paused: _paused,
    child: NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.child,
    ),
  );
}

class ScrollBackdropScope extends InheritedWidget {
  const ScrollBackdropScope({
    super.key,
    required this.paused,
    required super.child,
  });

  final bool paused;

  static bool pausedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ScrollBackdropScope>()
          ?.paused ??
      false;

  @override
  bool updateShouldNotify(ScrollBackdropScope oldWidget) =>
      paused != oldWidget.paused;
}

/// Reference radius profile for the continuous-kernel renderer. The default
/// renderer feathers a live native Gaussian, without an opaque gradient fill.
abstract final class ScrollEdgeProfile {
  static double sigma(double progress, {double maximum = 20}) {
    final depth = 1 - progress.clamp(0.0, 1.0);
    // Zero radius and zero slope where clear content first enters the feather.
    return maximum * depth * depth;
  }
}

class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    super.key,
    this.maxSigma = 8,
    this.plateauHeight = 0,
    this.fromBottom = false,
    this.shadeOpacity = DockLayout.edgeShadeOpacity,
  });

  final double maxSigma;
  final double plateauHeight;
  final bool fromBottom;
  final double shadeOpacity;

  @override
  Widget build(BuildContext context) {
    final paused = ScrollBackdropScope.pausedOf(context);
    return IgnorePointer(
      child: maxSigma <= 0 && shadeOpacity <= 0
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, constraints) {
                final shade = DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: fromBottom
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      end: fromBottom
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      colors: paused
                          ? [
                              Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: .82),
                              Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: .82),
                              Colors.transparent,
                            ]
                          : [
                              Colors.black.withValues(alpha: shadeOpacity),
                              Colors.black.withValues(alpha: shadeOpacity),
                              Colors.transparent,
                            ],
                      stops: [
                        0,
                        (plateauHeight / constraints.maxHeight).clamp(0.0, 1.0),
                        1,
                      ],
                    ),
                  ),
                );
                if (paused) return shade;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    NativeBackdrop(
                      effect: NativeEffect.progressive,
                      blur: maxSigma,
                      plateau: plateauHeight,
                      fromBottom: fromBottom,
                      child: const SizedBox.expand(),
                    ),
                    if (shadeOpacity > 0) shade,
                  ],
                );
              },
            ),
    );
  }
}
