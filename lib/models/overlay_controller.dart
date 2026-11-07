import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Holds the transform of the tracing overlay: position, scale, rotation,
/// horizontal flip, lock state and opacity.
class OverlayController extends ChangeNotifier {
  OverlayController({double opacity = 0.5})
    : _opacity = opacity.clamp(minOpacity, maxOpacity).toDouble();

  static const double minScale = 0.2;
  static const double maxScale = 5.0;
  static const double minOpacity = 0.0;
  static const double maxOpacity = 1.0;

  double _opacity;
  double _scale = 1.0;
  double _rotation = 0.0;
  Offset _offset = Offset.zero;
  bool _flipHorizontal = false;
  bool _locked = false;

  double get opacity => _opacity;
  double get scale => _scale;
  double get rotation => _rotation;
  Offset get offset => _offset;
  bool get flipHorizontal => _flipHorizontal;
  bool get locked => _locked;

  set opacity(double value) => setOpacity(value);

  void setOpacity(double value) {
    final next = value.clamp(minOpacity, maxOpacity).toDouble();
    if (next == _opacity) return;
    _opacity = next;
    notifyListeners();
  }

  void setScale(double value) {
    final next = value.clamp(minScale, maxScale).toDouble();
    if (next == _scale) return;
    _scale = next;
    notifyListeners();
  }

  void zoomBy(double factor) => setScale(_scale * factor);

  void panBy(Offset delta) {
    if (_locked) return;
    if (delta == Offset.zero) return;
    _offset += delta;
    notifyListeners();
  }

  void setOffset(Offset value) {
    if (_locked || value == _offset) return;
    _offset = value;
    notifyListeners();
  }

  void rotateBy(double radians) {
    _rotation = _normalizeAngle(_rotation + radians);
    notifyListeners();
  }

  void setRotation(double radians) {
    final next = _normalizeAngle(radians);
    if (next == _rotation) return;
    _rotation = next;
    notifyListeners();
  }

  void toggleFlip() {
    _flipHorizontal = !_flipHorizontal;
    notifyListeners();
  }

  void setLocked(bool value) {
    if (value == _locked) return;
    _locked = value;
    notifyListeners();
  }

  void toggleLocked() => setLocked(!_locked);

  void reset() {
    _scale = 1.0;
    _rotation = 0.0;
    _offset = Offset.zero;
    _flipHorizontal = false;
    notifyListeners();
  }

  /// Transform applied to the reference image. Built by hand so no deprecated
  /// vector_math helpers are needed.
  Matrix4 get matrix {
    final sx = _flipHorizontal ? -_scale : _scale;
    final sy = _scale;
    final cos = math.cos(_rotation);
    final sin = math.sin(_rotation);
    return Matrix4.identity()
      ..setEntry(0, 0, cos * sx)
      ..setEntry(0, 1, -sin * sy)
      ..setEntry(0, 3, _offset.dx)
      ..setEntry(1, 0, sin * sx)
      ..setEntry(1, 1, cos * sy)
      ..setEntry(1, 3, _offset.dy);
  }

  static double _normalizeAngle(double value) {
    var angle = value;
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    while (angle < -math.pi) {
      angle += 2 * math.pi;
    }
    return angle;
  }
}
