import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/utils/level_math.dart';
import '../models/level_reading.dart';
import 'settings_service.dart';

/// Streams accelerometer/gyroscope data into a smoothed [LevelReading].
///
/// The accelerometer supplies gravity; the gyroscope is used only to detect
/// rapid movement so the indicator can respond faster while the phone is being
/// repositioned.
class SensorService {
  SensorService(this._settings);

  final SettingsService _settings;

  final ValueNotifier<LevelReading> reading = ValueNotifier<LevelReading>(
    const LevelReading.unavailable(),
  );

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  Timer? _healthTimer;

  bool _started = false;
  double? _smoothedX;
  double? _smoothedY;
  double? _smoothedZ;
  double _angularSpeed = 0;
  List<double>? _reference;
  LevelStatus _lastStatus = LevelStatus.unavailable;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastAccelerometerAt;

  bool get isCalibrated => _reference != null;
  bool get isAvailable => reading.value.status != LevelStatus.unavailable;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _reference = _settings.levelCalibration;
    _lastStatus = LevelStatus.unavailable;
    _lastAccelerometerAt = null;
    _smoothedX = null;
    _smoothedY = null;
    _smoothedZ = null;
    _angularSpeed = 0;
    reading.value = const LevelReading.unavailable();

    try {
      _accelerometerSubscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onAccelerometer, onError: (_) => _markUnavailable());
      _gyroscopeSubscription =
          gyroscopeEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen(
            _onGyroscope,
            onError: (_) {
              // Gyroscope is optional; tracing still works without it.
              _angularSpeed = 0;
            },
          );
    } catch (_) {
      _started = false;
      await _accelerometerSubscription?.cancel();
      await _gyroscopeSubscription?.cancel();
      _accelerometerSubscription = null;
      _gyroscopeSubscription = null;
      _markUnavailable();
      return;
    }

    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final last = _lastAccelerometerAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 2)) {
        _markUnavailable();
      }
    });
  }

  Future<void> stop() async {
    _started = false;
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _smoothedX = null;
    _smoothedY = null;
    _smoothedZ = null;
    _angularSpeed = 0;
    _lastStatus = LevelStatus.unavailable;
    reading.value = const LevelReading.unavailable();
  }

  Future<bool> calibrate() async {
    final x = _smoothedX;
    final y = _smoothedY;
    final z = _smoothedZ;
    if (x == null || y == null || z == null) return false;

    final values = <double>[x, y, z];
    await _settings.setLevelCalibration(values);
    _reference = values;
    _lastStatus = LevelStatus.good;
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    reading.value = const LevelReading(
      status: LevelStatus.good,
      tiltDegrees: 0,
      calibrated: true,
    );
    return true;
  }

  Future<void> resetCalibration() async {
    await _settings.setLevelCalibration(null);
    _reference = null;
    _lastStatus = LevelStatus.unavailable;
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    reading.value = const LevelReading.unavailable();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final length = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (length < 0.5) return;

    _lastAccelerometerAt = DateTime.now();
    final alpha = _angularSpeed > 1.6 ? 0.35 : 0.16;
    _smoothedX = _smoothedX == null
        ? event.x
        : _smoothedX! + (event.x - _smoothedX!) * alpha;
    _smoothedY = _smoothedY == null
        ? event.y
        : _smoothedY! + (event.y - _smoothedY!) * alpha;
    _smoothedZ = _smoothedZ == null
        ? event.z
        : _smoothedZ! + (event.z - _smoothedZ!) * alpha;

    final thresholds = _settings.levelSensitivity.thresholds;
    final angle = gravityTiltDegrees(
      x: _smoothedX!,
      y: _smoothedY!,
      z: _smoothedZ!,
      reference: _reference,
    );
    final status = resolveLevelStatus(angle, thresholds, previous: _lastStatus);
    _lastStatus = status;

    final now = DateTime.now();
    final changed = status != reading.value.status;
    final due = now.difference(_lastEmit).inMilliseconds >= 50;
    if (!changed && !due) return;
    _lastEmit = now;

    final hint = angle <= thresholds.goodMax
        ? ''
        : gravityTiltHint(
            x: _smoothedX!,
            y: _smoothedY!,
            z: _smoothedZ!,
            reference: _reference,
          );

    reading.value = LevelReading(
      status: status,
      tiltDegrees: angle,
      hint: hint,
      calibrated: _reference != null,
      moving: _angularSpeed > 1.6,
    );
  }

  void _onGyroscope(GyroscopeEvent event) {
    final raw = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _angularSpeed = _angularSpeed * 0.65 + raw * 0.35;
  }

  void _markUnavailable() {
    _lastStatus = LevelStatus.unavailable;
    if (reading.value.status != LevelStatus.unavailable) {
      reading.value = const LevelReading.unavailable();
    }
  }

  Future<void> dispose() async {
    await stop();
    reading.dispose();
  }
}
