import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/filter_type.dart';

/// Pure-Dart image effects operating on tightly packed RGBA bytes.
///
/// Everything here is synchronous on purpose: the caller runs it inside an
/// isolate. Results are always opaque RGBA.
abstract final class FilterEngine {
  static Uint8List apply({
    required Uint8List rgba,
    required int width,
    required int height,
    required FilterType filter,
  }) {
    if (width < 1 || height < 1) {
      throw ArgumentError('Image dimensions must be positive.');
    }
    final expected = width * height * 4;
    if (rgba.length < expected) {
      throw ArgumentError(
        'Expected at least $expected bytes for $width×$height RGBA, '
        'received ${rgba.length}.',
      );
    }

    return switch (filter) {
      FilterType.original => _opaqueCopy(rgba, width * height),
      FilterType.anime => _animeFallback(rgba, width, height),
      FilterType.sketch => _pencilSketch(rgba, width, height),
      FilterType.edges => _edgeDetection(rgba, width, height),
      FilterType.mono => _mono(rgba, width * height),
      FilterType.noir => _noir(rgba, width, height),
      FilterType.comic => _comic(rgba, width, height),
      FilterType.vintage => _vintage(rgba, width, height),
      FilterType.poster => _poster(rgba, width * height),
      FilterType.feminine => _feminineLook(rgba, width, height),
      FilterType.masculine => _masculineLook(rgba, width, height),
      FilterType.feminizeFace ||
      FilterType.masculinizeFace => throw UnsupportedError(
        'Face transform filters run on the online AI service.',
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Anime fallback
  // ---------------------------------------------------------------------------

  /// Used when the neural model is unavailable or times out. This is a
  /// deterministic stylisation, not a replacement for the AI path.
  static Uint8List _animeFallback(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);

    final shortest = math.min(width, height);
    final radius = (shortest / 200).round().clamp(2, 10);
    final blurred = _boxBlurRgb(
      _boxBlurRgb(rgb, width, height, radius),
      width,
      height,
      radius,
    );

    final stylized = Uint8List(n * 3);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final r = blurred[o].toDouble();
      final g = blurred[o + 1].toDouble();
      final b = blurred[o + 2].toDouble();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;

      final rr = _posterize((lum + (r - lum) * 1.28).clamp(0, 255), 7);
      final gg = _posterize((lum + (g - lum) * 1.28).clamp(0, 255), 7);
      final bb = _posterize((lum + (b - lum) * 1.28).clamp(0, 255), 7);
      stylized[o] = rr;
      stylized[o + 1] = gg;
      stylized[o + 2] = bb;
    }

    final gray = _grayscale(blurred, n);
    final magnitude = _sobelMagnitude(gray, width, height);
    final threshold = math.max(16, _otsuThreshold(magnitude));
    final mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      mask[i] = magnitude[i] > threshold ? 255 : 0;
    }
    _dilateMask(mask, width, height);

    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final q = i * 4;
      final ink = mask[i] > 0;
      out[q] = ink ? (stylized[o] * 0.18).round() : stylized[o];
      out[q + 1] = ink ? (stylized[o + 1] * 0.18).round() : stylized[o + 1];
      out[q + 2] = ink ? (stylized[o + 2] * 0.18).round() : stylized[o + 2];
      out[q + 3] = 255;
    }
    return out;
  }

  static int _posterize(num value, int levels) {
    final step = 255 / (levels - 1);
    final quantized = (value / step).round() * step;
    return quantized.round().clamp(0, 255);
  }

  // ---------------------------------------------------------------------------
  // Pencil sketch
  // ---------------------------------------------------------------------------

  static Uint8List _pencilSketch(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final gray = _grayscale(rgb, n);

    final inverted = Uint8List(n);
    for (var i = 0; i < n; i++) {
      inverted[i] = 255 - gray[i];
    }

    final shortest = math.min(width, height);
    final radius = (shortest / 100).round().clamp(5, 26);
    final blurred = _boxBlurGray(
      _boxBlurGray(inverted, width, height, radius),
      width,
      height,
      radius,
    );

    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final base = gray[i].toDouble();
      final blend = blurred[i].toDouble();
      // Color dodge: white paper with graphite strokes.
      final dodge = base * 255 / (255 - blend + 1);
      final tone = ((dodge - 6) * 1.06).clamp(0, 255).round();
      final q = i * 4;
      out[q] = tone;
      out[q + 1] = tone;
      out[q + 2] = tone;
      out[q + 3] = 255;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Edge detection
  // ---------------------------------------------------------------------------

  static Uint8List _edgeDetection(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final gray = _grayscale(rgb, n);
    final softened = _boxBlurGray(gray, width, height, 1);
    final magnitude = _sobelMagnitude(softened, width, height);

    final threshold = math.max(20, _otsuThreshold(magnitude));
    final mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      mask[i] = magnitude[i] > threshold ? 255 : 0;
    }
    _dilateMask(mask, width, height);

    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final value = mask[i] > 0 ? 0 : 255;
      final q = i * 4;
      out[q] = value;
      out[q + 1] = value;
      out[q + 2] = value;
      out[q + 3] = 255;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Black & white family
  // ---------------------------------------------------------------------------

  /// Clean monochrome with a gentle contrast curve.
  static Uint8List _mono(Uint8List rgba, int n) {
    final rgb = _toRgb(rgba, n);
    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final q = i * 4;
      final lum = 0.299 * rgb[o] + 0.587 * rgb[o + 1] + 0.114 * rgb[o + 2];
      final tone = _clamp255((lum - 128) * 1.16 + 128);
      out[q] = tone;
      out[q + 1] = tone;
      out[q + 2] = tone;
      out[q + 3] = 255;
    }
    return out;
  }

  /// High-contrast silver tones with a soft vignette.
  static Uint8List _noir(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final out = Uint8List(n * 4);
    final centerX = (width - 1) / 2;
    final centerY = (height - 1) / 2;
    final radiusX = math.max(1.0, centerX);
    final radiusY = math.max(1.0, centerY);

    for (var y = 0; y < height; y++) {
      final ny = (y - centerY) / radiusY;
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final o = i * 3;
        final q = i * 4;
        final nx = (x - centerX) / radiusX;
        final distance = (nx * nx + ny * ny) / 2;
        final vignette = (1 - 0.52 * distance).clamp(0.32, 1.0);
        final lum = 0.299 * rgb[o] + 0.587 * rgb[o + 1] + 0.114 * rgb[o + 2];
        final tone = _clamp255((lum - 128) * 1.38 + 122);
        final value = _clamp255(tone * vignette);
        out[q] = value;
        out[q + 1] = value;
        out[q + 2] = value;
        out[q + 3] = 255;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Comic, vintage and poster
  // ---------------------------------------------------------------------------

  /// Flat, saturated colour bands with bold ink outlines.
  static Uint8List _comic(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final smoothed = _boxBlurRgb(rgb, width, height, 1);

    final gray = _grayscale(smoothed, n);
    final magnitude = _sobelMagnitude(gray, width, height);
    final threshold = math.max(18, _otsuThreshold(magnitude));
    final mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      mask[i] = magnitude[i] > threshold ? 255 : 0;
    }
    _dilateMask(mask, width, height);

    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final q = i * 4;
      final r = smoothed[o].toDouble();
      final g = smoothed[o + 1].toDouble();
      final b = smoothed[o + 2].toDouble();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      final inked = mask[i] != 0;
      final rr = inked
          ? 12
          : _posterize((lum + (r - lum) * 1.55).clamp(0, 255), 5);
      final gg = inked
          ? 12
          : _posterize((lum + (g - lum) * 1.55).clamp(0, 255), 5);
      final bb = inked
          ? 14
          : _posterize((lum + (b - lum) * 1.55).clamp(0, 255), 5);
      out[q] = rr;
      out[q + 1] = gg;
      out[q + 2] = bb;
      out[q + 3] = 255;
    }
    return out;
  }

  /// Faded sepia with lifted shadows, a vignette and fine grain.
  static Uint8List _vintage(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final out = Uint8List(n * 4);
    final centerX = (width - 1) / 2;
    final centerY = (height - 1) / 2;
    final radiusX = math.max(1.0, centerX);
    final radiusY = math.max(1.0, centerY);

    for (var y = 0; y < height; y++) {
      final ny = (y - centerY) / radiusY;
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final o = i * 3;
        final q = i * 4;
        final r = rgb[o].toDouble();
        final g = rgb[o + 1].toDouble();
        final b = rgb[o + 2].toDouble();

        final sepiaR = 0.393 * r + 0.769 * g + 0.189 * b;
        final sepiaG = 0.349 * r + 0.686 * g + 0.168 * b;
        final sepiaB = 0.272 * r + 0.534 * g + 0.131 * b;

        final nx = (x - centerX) / radiusX;
        final distance = (nx * nx + ny * ny) / 2;
        final vignette = (1 - 0.34 * distance).clamp(0.5, 1.0);
        final hash = (x * 73856093) ^ (y * 19349663);
        final grain = hash % 11 - 5;

        out[q] = _clamp255(
          (0.3 * r + 0.7 * sepiaR) * 0.84 * vignette + 20 + grain,
        );
        out[q + 1] = _clamp255(
          (0.3 * g + 0.7 * sepiaG) * 0.84 * vignette + 18 + grain,
        );
        out[q + 2] = _clamp255(
          (0.3 * b + 0.7 * sepiaB) * 0.84 * vignette + 15 + grain,
        );
        out[q + 3] = 255;
      }
    }
    return out;
  }

  /// Flat colour bands, like a screen-printed poster.
  static Uint8List _poster(Uint8List rgba, int n) {
    final rgb = _toRgb(rgba, n);
    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final q = i * 4;
      final r = rgb[o].toDouble();
      final g = rgb[o + 1].toDouble();
      final b = rgb[o + 2].toDouble();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      out[q] = _posterize((lum + (r - lum) * 1.32).clamp(0, 255), 5);
      out[q + 1] = _posterize((lum + (g - lum) * 1.32).clamp(0, 255), 5);
      out[q + 2] = _posterize((lum + (b - lum) * 1.32).clamp(0, 255), 5);
      out[q + 3] = 255;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Portrait tone presets
  // ---------------------------------------------------------------------------

  /// Cosmetic soft-focus glow with warm rose tones. This is a tone preset,
  /// not a transformation of the person in the photo.
  static Uint8List _feminineLook(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final radius = (math.min(width, height) / 320).round().clamp(1, 3);
    final blurred = _boxBlurRgb(
      _boxBlurRgb(rgb, width, height, radius),
      width,
      height,
      radius,
    );

    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final q = i * 4;
      final r = rgb[o] * 0.58 + blurred[o] * 0.42;
      final g = rgb[o + 1] * 0.58 + blurred[o + 1] * 0.42;
      final b = rgb[o + 2] * 0.58 + blurred[o + 2] * 0.42;

      out[q] = _clamp255(r * 0.92 + 29);
      out[q + 1] = _clamp255(g * 0.90 + 18);
      out[q + 2] = _clamp255(b * 0.88 + 24);
      out[q + 3] = 255;
    }
    return out;
  }

  /// Cosmetic cool tones, deeper shadows and crisp detail. This is a tone
  /// preset, not a transformation of the person in the photo.
  static Uint8List _masculineLook(Uint8List rgba, int width, int height) {
    final n = width * height;
    final rgb = _toRgb(rgba, n);
    final blurred = _boxBlurRgb(rgb, width, height, 1);
    final out = Uint8List(n * 4);

    for (var i = 0; i < n; i++) {
      final o = i * 3;
      final q = i * 4;
      // Unsharp mask: crisp detail without halos.
      final r = rgb[o] + (rgb[o] - blurred[o]) * 0.55;
      final g = rgb[o + 1] + (rgb[o + 1] - blurred[o + 1]) * 0.55;
      final b = rgb[o + 2] + (rgb[o + 2] - blurred[o + 2]) * 0.55;
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;

      out[q] = _clamp255((lum + (r - lum) * 0.9 - 120) * 1.14 + 115);
      out[q + 1] = _clamp255((lum + (g - lum) * 0.9 - 120) * 1.14 + 119);
      out[q + 2] = _clamp255((lum + (b - lum) * 0.9 - 120) * 1.14 + 126);
      out[q + 3] = 255;
    }
    return out;
  }

  static int _clamp255(num value) => value.round().clamp(0, 255).toInt();

  // ---------------------------------------------------------------------------
  // Pixel helpers
  // ---------------------------------------------------------------------------

  static Uint8List _opaqueCopy(Uint8List rgba, int n) {
    final out = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final alpha = rgba[o + 3];
      if (alpha == 255) {
        out[o] = rgba[o];
        out[o + 1] = rgba[o + 1];
        out[o + 2] = rgba[o + 2];
      } else {
        out[o] = _overWhite(rgba[o], alpha);
        out[o + 1] = _overWhite(rgba[o + 1], alpha);
        out[o + 2] = _overWhite(rgba[o + 2], alpha);
      }
      out[o + 3] = 255;
    }
    return out;
  }

  static Uint8List _toRgb(Uint8List rgba, int n) {
    final rgb = Uint8List(n * 3);
    for (var i = 0; i < n; i++) {
      final s = i * 4;
      final d = i * 3;
      final alpha = rgba[s + 3];
      if (alpha == 255) {
        rgb[d] = rgba[s];
        rgb[d + 1] = rgba[s + 1];
        rgb[d + 2] = rgba[s + 2];
      } else {
        rgb[d] = _overWhite(rgba[s], alpha);
        rgb[d + 1] = _overWhite(rgba[s + 1], alpha);
        rgb[d + 2] = _overWhite(rgba[s + 2], alpha);
      }
    }
    return rgb;
  }

  static int _overWhite(int channel, int alpha) {
    return (channel * alpha + 255 * (255 - alpha)) ~/ 255;
  }

  static Uint8List _grayscale(Uint8List rgb, int n) {
    final gray = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      gray[i] = (rgb[o] * 0.299 + rgb[o + 1] * 0.587 + rgb[o + 2] * 0.114)
          .round()
          .clamp(0, 255);
    }
    return gray;
  }

  static Uint8List _boxBlurRgb(
    Uint8List src,
    int width,
    int height,
    int radius,
  ) {
    if (radius <= 0) return Uint8List.fromList(src);
    final temp = Uint8List(src.length);
    final dst = Uint8List(src.length);
    final window = radius * 2 + 1;
    final maxX = width - 1;
    final maxY = height - 1;

    for (var y = 0; y < height; y++) {
      final row = y * width;
      var rs = 0;
      var gs = 0;
      var bs = 0;
      for (var k = -radius; k <= radius; k++) {
        final x = k.clamp(0, maxX);
        final i = (row + x) * 3;
        rs += src[i];
        gs += src[i + 1];
        bs += src[i + 2];
      }
      for (var x = 0; x < width; x++) {
        final o = (row + x) * 3;
        temp[o] = rs ~/ window;
        temp[o + 1] = gs ~/ window;
        temp[o + 2] = bs ~/ window;

        final remove = (x - radius).clamp(0, maxX);
        final add = (x + radius + 1).clamp(0, maxX);
        final ri = (row + remove) * 3;
        final ai = (row + add) * 3;
        rs += src[ai] - src[ri];
        gs += src[ai + 1] - src[ri + 1];
        bs += src[ai + 2] - src[ri + 2];
      }
    }

    for (var x = 0; x < width; x++) {
      var rs = 0;
      var gs = 0;
      var bs = 0;
      for (var k = -radius; k <= radius; k++) {
        final y = k.clamp(0, maxY);
        final i = (y * width + x) * 3;
        rs += temp[i];
        gs += temp[i + 1];
        bs += temp[i + 2];
      }
      for (var y = 0; y < height; y++) {
        final o = (y * width + x) * 3;
        dst[o] = rs ~/ window;
        dst[o + 1] = gs ~/ window;
        dst[o + 2] = bs ~/ window;

        final remove = (y - radius).clamp(0, maxY);
        final add = (y + radius + 1).clamp(0, maxY);
        final ri = (remove * width + x) * 3;
        final ai = (add * width + x) * 3;
        rs += temp[ai] - temp[ri];
        gs += temp[ai + 1] - temp[ri + 1];
        bs += temp[ai + 2] - temp[ri + 2];
      }
    }
    return dst;
  }

  static Uint8List _boxBlurGray(
    Uint8List src,
    int width,
    int height,
    int radius,
  ) {
    if (radius <= 0) return Uint8List.fromList(src);
    final temp = Uint8List(src.length);
    final dst = Uint8List(src.length);
    final window = radius * 2 + 1;
    final maxX = width - 1;
    final maxY = height - 1;

    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += src[row + k.clamp(0, maxX)];
      }
      for (var x = 0; x < width; x++) {
        temp[row + x] = sum ~/ window;
        final remove = (x - radius).clamp(0, maxX);
        final add = (x + radius + 1).clamp(0, maxX);
        sum += src[row + add] - src[row + remove];
      }
    }

    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += temp[k.clamp(0, maxY) * width + x];
      }
      for (var y = 0; y < height; y++) {
        dst[y * width + x] = sum ~/ window;
        final remove = (y - radius).clamp(0, maxY);
        final add = (y + radius + 1).clamp(0, maxY);
        sum += temp[add * width + x] - temp[remove * width + x];
      }
    }
    return dst;
  }

  static Uint8List _sobelMagnitude(Uint8List gray, int width, int height) {
    final out = Uint8List(width * height);
    if (width < 3 || height < 3) return out;

    for (var y = 1; y < height - 1; y++) {
      final row = y * width;
      for (var x = 1; x < width - 1; x++) {
        final i = row + x;
        final tl = gray[i - width - 1];
        final t = gray[i - width];
        final tr = gray[i - width + 1];
        final l = gray[i - 1];
        final r = gray[i + 1];
        final bl = gray[i + width - 1];
        final b = gray[i + width];
        final br = gray[i + width + 1];

        final gx = -tl + tr - 2 * l + 2 * r - bl + br;
        final gy = -tl - 2 * t - tr + bl + 2 * b + br;
        final magnitude = math.sqrt((gx * gx + gy * gy).toDouble());
        out[i] = (magnitude / 5.657).round().clamp(0, 255);
      }
    }
    return out;
  }

  static void _dilateMask(Uint8List mask, int width, int height) {
    final source = Uint8List.fromList(mask);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (source[y * width + x] != 0) continue;
        var edge = false;
        for (var dy = -1; dy <= 1 && !edge; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            if (source[ny * width + nx] != 0) {
              edge = true;
              break;
            }
          }
        }
        if (edge) mask[y * width + x] = 255;
      }
    }
  }

  static int _otsuThreshold(Uint8List values) {
    if (values.isEmpty) return 0;
    final histogram = List<int>.filled(256, 0);
    for (final value in values) {
      histogram[value]++;
    }

    final total = values.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    var sumBackground = 0.0;
    var weightBackground = 0;
    var bestVariance = -1.0;
    var threshold = 0;

    for (var i = 0; i < 256; i++) {
      weightBackground += histogram[i];
      if (weightBackground == 0) continue;
      final weightForeground = total - weightBackground;
      if (weightForeground == 0) break;

      sumBackground += i * histogram[i];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sum - sumBackground) / weightForeground;
      final difference = meanBackground - meanForeground;
      final variance =
          weightBackground * weightForeground * difference * difference;

      if (variance > bestVariance) {
        bestVariance = variance;
        threshold = i;
      }
    }
    return threshold;
  }
}
