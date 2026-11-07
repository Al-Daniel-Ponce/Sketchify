import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/models/filter_type.dart';
import 'package:sketchify/services/filters/filter_engine.dart';

/// Builds a small deterministic test image: a light gradient with a dark
/// square in the middle, so filters have both smooth areas and hard edges.
Uint8List _sampleImage({int width = 36, int height = 28}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final inSquare =
          x >= width ~/ 3 &&
          x < width * 2 ~/ 3 &&
          y >= height ~/ 3 &&
          y < height * 2 ~/ 3;
      bytes[i] = inSquare ? 24 : 90 + (x * 3) % 120;
      bytes[i + 1] = inSquare ? 26 : 110 + (y * 4) % 100;
      bytes[i + 2] = inSquare ? 30 : 200 - (x * 2) % 80;
      bytes[i + 3] = 255;
    }
  }
  return bytes;
}

double _averageChannel(Uint8List rgba, int channel) {
  var total = 0;
  var count = 0;
  for (var i = channel; i < rgba.length; i += 4) {
    total += rgba[i];
    count++;
  }
  return count == 0 ? 0 : total / count;
}

void main() {
  group('FilterEngine.apply', () {
    test('returns opaque RGBA for every local filter', () {
      const width = 36;
      const height = 28;
      final source = _sampleImage(width: width, height: height);

      for (final filter in FilterType.values.where(
        (filter) => !filter.isFaceTransform,
      )) {
        final result = FilterEngine.apply(
          rgba: Uint8List.fromList(source),
          width: width,
          height: height,
          filter: filter,
        );

        expect(
          result.length,
          width * height * 4,
          reason: '${filter.name} should keep the pixel count',
        );
        for (var i = 3; i < result.length; i += 4) {
          if (result[i] != 255) {
            fail('${filter.name} produced a non-opaque pixel at $i');
          }
        }
      }
    });

    test('original keeps RGB values and flattens transparency onto white', () {
      const width = 2;
      const height = 1;
      final source = Uint8List.fromList(<int>[10, 20, 30, 255, 255, 0, 0, 0]);

      final result = FilterEngine.apply(
        rgba: source,
        width: width,
        height: height,
        filter: FilterType.original,
      );

      expect(result.sublist(0, 4), <int>[10, 20, 30, 255]);
      expect(result.sublist(4, 8), <int>[255, 255, 255, 255]);
    });

    test('original flattens semi-transparent pixels', () {
      final result = FilterEngine.apply(
        rgba: Uint8List.fromList(<int>[0, 0, 0, 128]),
        width: 1,
        height: 1,
        filter: FilterType.original,
      );
      // 0 * 128/255 + 255 * 127/255 ~= 127
      expect(result[0], inInclusiveRange(126, 128));
      expect(result[3], 255);
    });

    test('pencil sketch is grayscale and mostly light', () {
      const width = 36;
      const height = 28;
      final result = FilterEngine.apply(
        rgba: _sampleImage(width: width, height: height),
        width: width,
        height: height,
        filter: FilterType.sketch,
      );

      var lightPixels = 0;
      var darkPixels = 0;
      for (var i = 0; i < result.length; i += 4) {
        expect(result[i], result[i + 1], reason: 'sketch must be grayscale');
        expect(
          result[i + 1],
          result[i + 2],
          reason: 'sketch must be grayscale',
        );
        if (result[i] > 180) lightPixels++;
        if (result[i] < 80) darkPixels++;
      }

      expect(lightPixels, greaterThan(width * height ~/ 2));
      expect(darkPixels, greaterThan(0));
    });

    test('edge detection produces dark outlines on white paper', () {
      const width = 36;
      const height = 28;
      final result = FilterEngine.apply(
        rgba: _sampleImage(width: width, height: height),
        width: width,
        height: height,
        filter: FilterType.edges,
      );

      var black = 0;
      var white = 0;
      for (var i = 0; i < result.length; i += 4) {
        expect(result[i], result[i + 1]);
        expect(result[i + 1], result[i + 2]);
        if (result[i] == 0) black++;
        if (result[i] == 255) white++;
      }

      expect(black, greaterThan(0), reason: 'edges should draw ink');
      expect(white, greaterThan(width * height ~/ 2));
    });

    test('anime fallback keeps both flat colour and dark ink pixels', () {
      const width = 36;
      const height = 28;
      final result = FilterEngine.apply(
        rgba: _sampleImage(width: width, height: height),
        width: width,
        height: height,
        filter: FilterType.anime,
      );

      var colourful = 0;
      var ink = 0;
      for (var i = 0; i < result.length; i += 4) {
        final r = result[i];
        final g = result[i + 1];
        final b = result[i + 2];
        if (r < 60 && g < 60 && b < 60) ink++;
        if ((r - g).abs() > 12 || (g - b).abs() > 12) colourful++;
      }

      expect(ink, greaterThan(0));
      expect(colourful, greaterThan(0));
    });

    test('mono and noir are grayscale', () {
      const width = 36;
      const height = 28;
      for (final filter in <FilterType>[FilterType.mono, FilterType.noir]) {
        final result = FilterEngine.apply(
          rgba: _sampleImage(width: width, height: height),
          width: width,
          height: height,
          filter: filter,
        );
        for (var i = 0; i < result.length; i += 4) {
          expect(result[i], result[i + 1], reason: '${filter.name} is gray');
          expect(
            result[i + 1],
            result[i + 2],
            reason: '${filter.name} is gray',
          );
        }
      }
    });

    test('comic keeps flat colour and dark ink', () {
      const width = 36;
      const height = 28;
      final result = FilterEngine.apply(
        rgba: _sampleImage(width: width, height: height),
        width: width,
        height: height,
        filter: FilterType.comic,
      );

      var colourful = 0;
      var ink = 0;
      for (var i = 0; i < result.length; i += 4) {
        final r = result[i];
        final g = result[i + 1];
        final b = result[i + 2];
        if (r < 40 && g < 40 && b < 40) ink++;
        if ((r - g).abs() > 12 || (g - b).abs() > 12) colourful++;
      }

      expect(ink, greaterThan(0));
      expect(colourful, greaterThan(0));
    });

    test('poster snaps every channel to a flat band', () {
      const width = 36;
      const height = 28;
      final result = FilterEngine.apply(
        rgba: _sampleImage(width: width, height: height),
        width: width,
        height: height,
        filter: FilterType.poster,
      );

      const bands = <int>{0, 64, 128, 191, 255};
      for (var i = 0; i < result.length; i += 4) {
        expect(bands, contains(result[i]));
        expect(bands, contains(result[i + 1]));
        expect(bands, contains(result[i + 2]));
      }
    });

    test('vintage warms the colours and stays opaque', () {
      const width = 36;
      const height = 28;
      final source = _sampleImage(width: width, height: height);
      final result = FilterEngine.apply(
        rgba: Uint8List.fromList(source),
        width: width,
        height: height,
        filter: FilterType.vintage,
      );

      final warmth = _averageChannel(result, 0) - _averageChannel(result, 2);
      final sourceWarmth =
          _averageChannel(source, 0) - _averageChannel(source, 2);
      expect(warmth, greaterThan(sourceWarmth + 10));
      for (var i = 3; i < result.length; i += 4) {
        expect(result[i], 255);
      }
    });

    test('portrait presets shift tone in opposite directions', () {
      const width = 36;
      const height = 28;
      final source = _sampleImage(width: width, height: height);
      final feminine = FilterEngine.apply(
        rgba: Uint8List.fromList(source),
        width: width,
        height: height,
        filter: FilterType.feminine,
      );
      final masculine = FilterEngine.apply(
        rgba: Uint8List.fromList(source),
        width: width,
        height: height,
        filter: FilterType.masculine,
      );

      final sourceWarmth =
          _averageChannel(source, 0) - _averageChannel(source, 2);
      final feminineWarmth =
          _averageChannel(feminine, 0) - _averageChannel(feminine, 2);
      final masculineWarmth =
          _averageChannel(masculine, 0) - _averageChannel(masculine, 2);

      expect(feminineWarmth, greaterThan(sourceWarmth));
      expect(masculineWarmth, lessThan(sourceWarmth));
    });

    test('face transform filters are rejected by the local engine', () {
      for (final filter in <FilterType>[
        FilterType.feminizeFace,
        FilterType.masculinizeFace,
      ]) {
        expect(
          () => FilterEngine.apply(
            rgba: _sampleImage(),
            width: 36,
            height: 28,
            filter: filter,
          ),
          throwsA(isA<UnsupportedError>()),
          reason: '${filter.name} must run on the online service',
        );
      }
    });

    test('rejects invalid dimensions and short buffers', () {
      expect(
        () => FilterEngine.apply(
          rgba: Uint8List(0),
          width: 0,
          height: 10,
          filter: FilterType.anime,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => FilterEngine.apply(
          rgba: Uint8List(8),
          width: 10,
          height: 10,
          filter: FilterType.edges,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles tiny images without crashing', () {
      for (final filter in FilterType.values.where(
        (filter) => !filter.isFaceTransform,
      )) {
        final result = FilterEngine.apply(
          rgba: Uint8List.fromList(<int>[255, 0, 0, 255]),
          width: 1,
          height: 1,
          filter: filter,
        );
        expect(result.length, 4);
        expect(result[3], 255);
      }
    });
  });
}
