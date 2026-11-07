import 'dart:math' as math;

import '../../models/level_reading.dart';

typedef _Vector = ({double x, double y, double z});

_Vector _normalize(double x, double y, double z) {
  final length = math.sqrt(x * x + y * y + z * z);
  if (length < 1e-9) return (x: 0, y: 0, z: 1);
  return (x: x / length, y: y / length, z: z / length);
}

_Vector _referenceVector(List<double>? reference) {
  if (reference == null || reference.length != 3) {
    return (x: 0, y: 0, z: 1);
  }
  return _normalize(reference[0], reference[1], reference[2]);
}

/// Angle between the current gravity vector and the calibration reference.
///
/// The absolute dot product is used so a phone facing down over a sheet of
/// paper reads as flat, just like one facing up.
double gravityTiltDegrees({
  required double x,
  required double y,
  required double z,
  List<double>? reference,
}) {
  final current = _normalize(x, y, z);
  final target = _referenceVector(reference);
  final dot =
      (current.x * target.x + current.y * target.y + current.z * target.z)
          .clamp(-1.0, 1.0)
          .abs();
  return math.acos(dot) * 180 / math.pi;
}

/// Human readable direction the phone should be corrected towards.
String gravityTiltHint({
  required double x,
  required double y,
  required double z,
  List<double>? reference,
}) {
  final current = _normalize(x, y, z);
  final target = _referenceVector(reference);
  final dot =
      current.x * target.x + current.y * target.y + current.z * target.z;
  final px = current.x - target.x * dot;
  final py = current.y - target.y * dot;
  final magnitude = math.sqrt(px * px + py * py);
  if (magnitude < 0.004) return '';
  if (px.abs() >= py.abs()) {
    return px > 0 ? 'Lower left side' : 'Lower right side';
  }
  return py > 0 ? 'Lower top edge' : 'Lower bottom edge';
}

/// Maps a tilt angle to a color state, applying hysteresis so the indicator
/// does not flicker while the phone hovers on a threshold.
LevelStatus resolveLevelStatus(
  double tilt,
  LevelThresholds thresholds, {
  LevelStatus? previous,
}) {
  final LevelStatus base;
  if (tilt <= thresholds.goodMax) {
    base = LevelStatus.good;
  } else if (tilt <= thresholds.warningMax) {
    base = LevelStatus.warning;
  } else {
    base = LevelStatus.tilted;
  }

  if (previous == null || previous == LevelStatus.unavailable) return base;

  const hysteresis = 0.4;
  switch (previous) {
    case LevelStatus.good:
      if (base == LevelStatus.warning &&
          tilt < thresholds.goodMax + hysteresis) {
        return LevelStatus.good;
      }
    case LevelStatus.warning:
      if (base == LevelStatus.good && tilt > thresholds.goodMax - hysteresis) {
        return LevelStatus.warning;
      }
      if (base == LevelStatus.tilted &&
          tilt < thresholds.warningMax + hysteresis) {
        return LevelStatus.warning;
      }
    case LevelStatus.tilted:
      if (base == LevelStatus.warning &&
          tilt > thresholds.warningMax - hysteresis) {
        return LevelStatus.tilted;
      }
    case LevelStatus.unavailable:
      break;
  }
  return base;
}
