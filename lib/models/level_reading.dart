/// Tilt thresholds in degrees.
class LevelThresholds {
  const LevelThresholds({required this.goodMax, required this.warningMax});

  /// At or below this angle the level is green.
  final double goodMax;

  /// At or below this angle (but above [goodMax]) it is yellow.
  final double warningMax;

  static const LevelThresholds relaxed = LevelThresholds(
    goodMax: 3,
    warningMax: 7,
  );
  static const LevelThresholds standard = LevelThresholds(
    goodMax: 2,
    warningMax: 5,
  );
  static const LevelThresholds strict = LevelThresholds(
    goodMax: 1,
    warningMax: 3,
  );
}

enum LevelSensitivity {
  relaxed(LevelThresholds.relaxed, 'Relaxed', 'Green up to 3°, red after 7°.'),
  standard(
    LevelThresholds.standard,
    'Standard',
    'Green up to 2°, red after 5°.',
  ),
  strict(LevelThresholds.strict, 'Strict', 'Green up to 1°, red after 3°.');

  const LevelSensitivity(this.thresholds, this.label, this.description);

  final LevelThresholds thresholds;
  final String label;
  final String description;
}

enum LevelStatus { good, warning, tilted, unavailable }

/// Immutable snapshot of the Smart Level indicator.
class LevelReading {
  const LevelReading({
    required this.status,
    this.tiltDegrees,
    this.hint = '',
    this.calibrated = false,
    this.moving = false,
  });

  const LevelReading.unavailable()
    : status = LevelStatus.unavailable,
      tiltDegrees = null,
      hint = '',
      calibrated = false,
      moving = false;

  final double? tiltDegrees;
  final LevelStatus status;
  final String hint;
  final bool calibrated;
  final bool moving;

  bool get hasReading =>
      tiltDegrees != null && status != LevelStatus.unavailable;

  String get angleText =>
      tiltDegrees == null ? '--' : '${tiltDegrees!.toStringAsFixed(1)}°';

  String get statusLabel => switch (status) {
    LevelStatus.good => 'Level',
    LevelStatus.warning => 'Slight tilt',
    LevelStatus.tilted => 'Tilted',
    LevelStatus.unavailable => 'No sensor',
  };

  String get semanticsLabel => switch (status) {
    LevelStatus.unavailable => 'Smart level unavailable',
    _ => 'Smart level: ${statusLabel.toLowerCase()}. Tilt $angleText.',
  };
}
