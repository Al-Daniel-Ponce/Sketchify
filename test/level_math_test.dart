import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/core/utils/level_math.dart';
import 'package:sketchify/models/level_reading.dart';

void main() {
  group('gravityTiltDegrees', () {
    test('a flat phone reads as level', () {
      expect(gravityTiltDegrees(x: 0, y: 0, z: 9.81), closeTo(0, 0.001));
    });

    test('a 45 degree tilt reads as 45 degrees', () {
      final component = 9.81 / math.sqrt2;
      expect(
        gravityTiltDegrees(x: component, y: 0, z: component),
        closeTo(45, 0.001),
      );
    });

    test('phone facing down still reads level', () {
      expect(gravityTiltDegrees(x: 0, y: 0, z: -9.81), closeTo(0, 0.001));
    });

    test('calibration is relative to the saved reference', () {
      final reference = <double>[0, 9.81, 0];
      expect(
        gravityTiltDegrees(x: 0, y: 9.81, z: 0, reference: reference),
        closeTo(0, 0.001),
      );
      expect(
        gravityTiltDegrees(x: 0, y: 0, z: 9.81, reference: reference),
        closeTo(90, 0.001),
      );
    });

    test('an invalid reference falls back to flat', () {
      expect(
        gravityTiltDegrees(x: 0, y: 0, z: -9.81, reference: <double>[1, 2]),
        closeTo(0, 0.001),
      );
    });

    test('a zero vector is treated as flat rather than NaN', () {
      final angle = gravityTiltDegrees(x: 0, y: 0, z: 0);
      expect(angle.isNaN, isFalse);
      expect(angle, closeTo(0, 0.001));
    });
  });

  group('gravityTiltHint', () {
    test('gives no hint when level', () {
      expect(gravityTiltHint(x: 0, y: 0, z: 9.81), isEmpty);
    });

    test('reports an axis to lower when tilted', () {
      final hint = gravityTiltHint(x: 3, y: 0, z: 9.4);
      expect(hint, isNotEmpty);
    });
  });

  group('resolveLevelStatus', () {
    const thresholds = LevelThresholds.standard;

    test('maps angles to green, yellow and red', () {
      expect(resolveLevelStatus(0.5, thresholds), LevelStatus.good);
      expect(resolveLevelStatus(3.4, thresholds), LevelStatus.warning);
      expect(resolveLevelStatus(8.2, thresholds), LevelStatus.tilted);
    });

    test('green holds just above the threshold until hysteresis passes', () {
      expect(
        resolveLevelStatus(2.2, thresholds, previous: LevelStatus.good),
        LevelStatus.good,
      );
      expect(
        resolveLevelStatus(2.5, thresholds, previous: LevelStatus.good),
        LevelStatus.warning,
      );
    });

    test('yellow holds just below the green threshold', () {
      expect(
        resolveLevelStatus(1.8, thresholds, previous: LevelStatus.warning),
        LevelStatus.warning,
      );
      expect(
        resolveLevelStatus(1.4, thresholds, previous: LevelStatus.warning),
        LevelStatus.good,
      );
    });

    test('red holds just above the yellow threshold', () {
      expect(
        resolveLevelStatus(5.2, thresholds, previous: LevelStatus.warning),
        LevelStatus.warning,
      );
      expect(
        resolveLevelStatus(4.7, thresholds, previous: LevelStatus.tilted),
        LevelStatus.tilted,
      );
    });

    test('unavailable previous state does not apply hysteresis', () {
      expect(
        resolveLevelStatus(1.9, thresholds, previous: LevelStatus.unavailable),
        LevelStatus.good,
      );
    });

    test('sensitivity presets use increasingly strict thresholds', () {
      expect(LevelSensitivity.relaxed.thresholds.goodMax, 3);
      expect(LevelSensitivity.standard.thresholds.goodMax, 2);
      expect(LevelSensitivity.strict.thresholds.goodMax, 1);
      expect(LevelSensitivity.relaxed.thresholds.warningMax, 7);
      expect(LevelSensitivity.standard.thresholds.warningMax, 5);
      expect(LevelSensitivity.strict.thresholds.warningMax, 3);
    });
  });

  group('LevelReading', () {
    test('formats angles and labels', () {
      const good = LevelReading(
        status: LevelStatus.good,
        tiltDegrees: 0.42,
        calibrated: true,
      );
      expect(good.angleText, '0.4°');
      expect(good.statusLabel, 'Level');
      expect(good.hasReading, isTrue);
      expect(good.semanticsLabel, contains('0.4°'));
    });

    test('unavailable reading has no angle', () {
      const reading = LevelReading.unavailable();
      expect(reading.hasReading, isFalse);
      expect(reading.angleText, '--');
      expect(reading.statusLabel, 'No sensor');
      expect(reading.semanticsLabel, 'Smart level unavailable');
    });
  });
}
