import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared, theme-independent optics for transparent control surfaces.
/// This is a thin-lens UI approximation, not a second opaque border material.
abstract final class GlassOptics {
  // A subtler meniscus keeps small controls readable while still refracting
  // the live background. Shared by controls and their expanding overlays.
  static const refractiveIndex = 1.33;
  static const lightDirection = Offset(-.70710678118, -.70710678118);

  /// Unpolarized Fresnel reflectance at an air/glass interface.
  /// Reflection replaces transmission; it is not added to the backdrop RGB.
  static double fresnel(double cosIncident) {
    final cosI = cosIncident.clamp(0.0, 1.0);
    final sinT2 = (1 - cosI * cosI) / (refractiveIndex * refractiveIndex);
    final cosT = math.sqrt(1 - sinT2);
    final rs =
        (cosI - refractiveIndex * cosT) / (cosI + refractiveIndex * cosT);
    final rp =
        (refractiveIndex * cosI - cosT) / (refractiveIndex * cosI + cosT);
    return (rs * rs + rp * rp) / 2;
  }

  /// A neutral upper-left area light reflected by a rounded meniscus.
  /// The unlit side transmits its surroundings instead of receiving a gray
  /// outline or an equally strong, fabricated opposite light.
  static double reflectionAlpha({
    required Offset outwardNormal,
    required double depth,
    required double bevel,
    double strength = 1,
  }) {
    final slope = (1 - depth / bevel).clamp(0.0, 1.0);
    final cosIncident = math.sqrt(1 - slope * slope);
    final alignment = math.max(
      0.0,
      outwardNormal.dx * lightDirection.dx +
          outwardNormal.dy * lightDirection.dy,
    );
    final edgeFade = (1 - depth / bevel).clamp(0.0, 1.0);
    return (fresnel(cosIncident) *
            (.025 + .975 * alignment * alignment) *
            edgeFade *
            strength)
        .clamp(0.0, 1.0);
  }
}
