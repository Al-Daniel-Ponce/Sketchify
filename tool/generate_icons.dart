// Generates the legacy launcher icons for Sketchify.
//
// Run from the project root:
//   dart run tool/generate_icons.dart
//
// The adaptive icon (API 26+) uses vector drawables, so only the legacy
// mipmap PNGs (API 24-25) are rasterised here. The mark matches
// lib/shared/widgets/app_logo.dart: a gradient tile, a lens ring, and a
// pencil stroke.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int _renderSize = 1024;
const int _samples = 4;

// Brand palette, kept in sync with lib/core/theme/app_colors.dart.
const _primary = _Rgb(0xFF, 0x7A, 0x45);
const _primarySoft = _Rgb(0xFF, 0x9A, 0x62);
const _secondary = _Rgb(0x8B, 0x7C, 0xFF);
const _white = _Rgb(0xFF, 0xFF, 0xFF);
const _tip = _Rgb(0x2A, 0x12, 0x06);

const _densities = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

void main() {
  final source = _renderIcon(_renderSize);
  final roundSource = _renderIcon(_renderSize, round: true);
  final resDir = Directory('android/app/src/main/res');

  for (final entry in _densities.entries) {
    final target = Directory('${resDir.path}/${entry.key}');
    target.createSync(recursive: true);
    final scaled = img.copyResize(
      source,
      width: entry.value,
      height: entry.value,
      interpolation: img.Interpolation.cubic,
    );
    File('${target.path}/ic_launcher.png')
        .writeAsBytesSync(img.encodePng(scaled, level: 9));
    final scaledRound = img.copyResize(
      roundSource,
      width: entry.value,
      height: entry.value,
      interpolation: img.Interpolation.cubic,
    );
    File('${target.path}/ic_launcher_round.png')
        .writeAsBytesSync(img.encodePng(scaledRound, level: 9));
    stdout.writeln('wrote ${target.path}/ic_launcher.png (${entry.value}px)');
  }

  final previewDir = Directory('build');
  previewDir.createSync(recursive: true);
  File('build/icon_preview.png').writeAsBytesSync(img.encodePng(source));
  File(
    'build/icon_preview_round.png',
  ).writeAsBytesSync(img.encodePng(roundSource));
  stdout.writeln('wrote build/icon_preview.png');
}

img.Image _renderIcon(int size, {bool round = false}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  final center = size / 2;
  final half = size / 2;
  final radius = size * 0.28;
  final step = 1 / _samples;

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var a = 0.0;

      for (var sy = 0; sy < _samples; sy++) {
        for (var sx = 0; sx < _samples; sx++) {
          final px = x + (sx + 0.5) * step;
          final py = y + (sy + 0.5) * step;
          final sample = _sample(px, py, center, half, radius, round);
          r += sample.r * sample.a;
          g += sample.g * sample.a;
          b += sample.b * sample.a;
          a += sample.a;
        }
      }

      final alpha = a / (_samples * _samples);
      if (alpha <= 0) continue;
      image.setPixelRgba(
        x,
        y,
        ((r / a) * 255).round(),
        ((g / a) * 255).round(),
        ((b / a) * 255).round(),
        (alpha * 255).round(),
      );
    }
  }

  return image;
}

_Sample _sample(
  double x,
  double y,
  double center,
  double half,
  double radius,
  bool round,
) {
  // Everything outside the tile stays transparent.
  final inside = round
      ? _distance(x, y, center, center) <= half
      : _insideRoundedRect(x, y, center, half, radius);
  if (!inside) {
    return const _Sample(0, 0, 0, 0);
  }

  // Diagonal brand gradient with a warm midpoint.
  final t = ((x + y) / (half * 4)).clamp(0.0, 1.0);
  var color = t < 0.55
      ? _lerp(_primary, _primarySoft, t / 0.55)
      : _lerp(_primarySoft, _secondary, (t - 0.55) / 0.45);

  // A soft highlight keeps the flat gradient from looking muddy.
  final highlight = _clamp01(
    1 - _distance(x, y, center * 0.55, center * 0.4) / (half * 0.85),
  );
  color = _lerp(color, _white, highlight * 0.12);

  final glyph = _glyphColor(x, y, half * 2);
  if (glyph != null) {
    color = glyph;
  }
  return _Sample(color.r / 255, color.g / 255, color.b / 255, 1);
}

_Rgb? _glyphColor(double x, double y, double size) {
  final cx = size * 0.5;
  final cy = size * 0.53;
  final lensRadius = size * 0.215;
  final lensStroke = size * 0.052;
  final dotRadius = size * 0.075;
  final pencilWidth = size * 0.072;
  final tipRadius = size * 0.042;

  final lensDistance = (x - cx) * (x - cx) + (y - cy) * (y - cy);
  if (lensDistance <= dotRadius * dotRadius) {
    return _white;
  }
  final outer = lensRadius + lensStroke / 2;
  final inner = lensRadius - lensStroke / 2;
  if (lensDistance <= outer * outer && lensDistance >= inner * inner) {
    return _white;
  }

  if (_distanceToSegment(
        x,
        y,
        size * 0.31,
        size * 0.72,
        size * 0.665,
        size * 0.345,
      ) <=
      pencilWidth / 2) {
    return _white;
  }

  final tipX = size * 0.705;
  final tipY = size * 0.295;
  if ((x - tipX) * (x - tipX) + (y - tipY) * (y - tipY) <=
      tipRadius * tipRadius) {
    return _tip;
  }

  return null;
}

bool _insideRoundedRect(
  double x,
  double y,
  double center,
  double half,
  double radius,
) {
  final dx = (x - center).abs() - (half - radius);
  final dy = (y - center).abs() - (half - radius);
  if (dx <= 0 || dy <= 0) {
    return x >= 0 && x <= center * 2 && y >= 0 && y <= center * 2;
  }
  return dx * dx + dy * dy <= radius * radius;
}

double _distance(double x1, double y1, double x2, double y2) {
  final dx = x1 - x2;
  final dy = y1 - y2;
  return math.sqrt(dx * dx + dy * dy);
}

double _distanceToSegment(
  double px,
  double py,
  double x1,
  double y1,
  double x2,
  double y2,
) {
  final dx = x2 - x1;
  final dy = y2 - y1;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return _distance(px, py, x1, y1);
  final t = (((px - x1) * dx + (py - y1) * dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return _distance(px, py, x1 + t * dx, y1 + t * dy);
}

double _clamp01(double value) => value.clamp(0.0, 1.0);

_Rgb _lerp(_Rgb a, _Rgb b, double t) {
  final clamped = t.clamp(0.0, 1.0);
  return _Rgb(
    (a.r + (b.r - a.r) * clamped).round(),
    (a.g + (b.g - a.g) * clamped).round(),
    (a.b + (b.b - a.b) * clamped).round(),
  );
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}

class _Sample {
  const _Sample(this.r, this.g, this.b, this.a);

  final double r;
  final double g;
  final double b;
  final double a;
}
