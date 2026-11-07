import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/level_reading.dart';

enum ProcessingQuality {
  fast('Fast', '1280 px • quickest', 1280),
  balanced('Balanced', '1600 px • recommended', 1600),
  high('High', '2048 px • best detail', 2048);

  const ProcessingQuality(this.label, this.detail, this.maxDimension);

  final String label;
  final String detail;
  final int maxDimension;
}

/// Persisted application preferences.
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs);

  static const String _prefix = 'sketchify.';
  static const String _kThemeMode = '${_prefix}theme_mode';
  static const String _kDefaultOpacity = '${_prefix}default_opacity';
  static const String _kKeepAwake = '${_prefix}keep_awake';
  static const String _kHaptics = '${_prefix}haptics';
  static const String _kLevelSensitivity = '${_prefix}level_sensitivity';
  static const String _kProcessingQuality = '${_prefix}processing_quality';
  static const String _kOnlineAnimeEnabled = '${_prefix}online_anime_enabled';
  static const String _kOnlineAnimeConsent = '${_prefix}online_anime_consent';
  static const String _kFaceTransformEnabled =
      '${_prefix}face_transform_enabled';
  static const String _kFaceTransformConsent =
      '${_prefix}face_transform_consent';
  static const String _kLevelCalibration = '${_prefix}level_calibration';

  final SharedPreferences _prefs;

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService._(prefs);
  }

  ThemeMode get themeMode {
    final raw = _prefs.getString(_kThemeMode);
    return switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  double get defaultOpacity {
    final value = _prefs.getDouble(_kDefaultOpacity) ?? 0.5;
    return value.clamp(0.0, 1.0).toDouble();
  }

  Future<void> setDefaultOpacity(double value) async {
    await _prefs.setDouble(_kDefaultOpacity, value.clamp(0.0, 1.0).toDouble());
    notifyListeners();
  }

  bool get keepScreenAwake => _prefs.getBool(_kKeepAwake) ?? true;

  Future<void> setKeepScreenAwake(bool value) async {
    await _prefs.setBool(_kKeepAwake, value);
    notifyListeners();
  }

  bool get haptics => _prefs.getBool(_kHaptics) ?? true;

  Future<void> setHaptics(bool value) async {
    await _prefs.setBool(_kHaptics, value);
    notifyListeners();
  }

  LevelSensitivity get levelSensitivity {
    final raw = _prefs.getString(_kLevelSensitivity);
    return LevelSensitivity.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => LevelSensitivity.standard,
    );
  }

  Future<void> setLevelSensitivity(LevelSensitivity value) async {
    await _prefs.setString(_kLevelSensitivity, value.name);
    notifyListeners();
  }

  ProcessingQuality get processingQuality {
    final raw = _prefs.getString(_kProcessingQuality);
    return ProcessingQuality.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ProcessingQuality.balanced,
    );
  }

  Future<void> setProcessingQuality(ProcessingQuality value) async {
    await _prefs.setString(_kProcessingQuality, value.name);
    notifyListeners();
  }

  /// Opt-in switch for the optional hosted anime service.
  bool get onlineAnimeEnabled => _prefs.getBool(_kOnlineAnimeEnabled) ?? false;

  Future<void> setOnlineAnimeEnabled(bool value) async {
    await _prefs.setBool(_kOnlineAnimeEnabled, value);
    notifyListeners();
  }

  /// True once the user has agreed to send photos to the hosted service.
  bool get onlineAnimeConsent => _prefs.getBool(_kOnlineAnimeConsent) ?? false;

  Future<void> setOnlineAnimeConsent(bool value) async {
    await _prefs.setBool(_kOnlineAnimeConsent, value);
    notifyListeners();
  }

  /// Opt-in switch for the online-only face transform filters.
  bool get faceTransformEnabled =>
      _prefs.getBool(_kFaceTransformEnabled) ?? false;

  Future<void> setFaceTransformEnabled(bool value) async {
    await _prefs.setBool(_kFaceTransformEnabled, value);
    notifyListeners();
  }

  /// True once the user confirmed they have permission to transform a photo.
  bool get faceTransformConsent =>
      _prefs.getBool(_kFaceTransformConsent) ?? false;

  Future<void> setFaceTransformConsent(bool value) async {
    await _prefs.setBool(_kFaceTransformConsent, value);
    notifyListeners();
  }

  /// Calibration reference gravity vector as `[x, y, z]`, or null.
  List<double>? get levelCalibration {
    final raw = _prefs.getStringList(_kLevelCalibration);
    if (raw == null || raw.length != 3) return null;
    final parsed = raw.map(double.tryParse).toList();
    if (parsed.any((value) => value == null)) return null;
    return parsed.cast<double>();
  }

  Future<void> setLevelCalibration(List<double>? values) async {
    if (values == null || values.length != 3) {
      await _prefs.remove(_kLevelCalibration);
    } else {
      await _prefs.setStringList(
        _kLevelCalibration,
        values.map((value) => value.toString()).toList(),
      );
    }
    notifyListeners();
  }

  Future<void> reset() async {
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await _prefs.remove(key);
    }
    notifyListeners();
  }
}
