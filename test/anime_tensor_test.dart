import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/services/anime/anime_tensor.dart';

Uint8List _rgba(List<List<int>> pixels) {
  final bytes = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    bytes.setRange(i * 4, i * 4 + 4, pixels[i]);
  }
  return bytes;
}

Uint8List _floatBytes(Float32List values) {
  return Uint8List.fromList(
    values.buffer.asUint8List(values.offsetInBytes, values.lengthInBytes),
  );
}

void main() {
  group('TFLite model contract', () {
    test('detects the TFL3 flatbuffer identifier', () {
      final valid = Uint8List.fromList(<int>[
        0,
        0,
        0,
        0,
        0x54,
        0x46,
        0x4C,
        0x33,
      ]);
      expect(hasTfliteMagic(valid), isTrue);
      expect(hasTfliteMagic(Uint8List(4)), isFalse);
      expect(
        hasTfliteMagic(
          Uint8List.fromList(<int>[0, 0, 0, 0, 0x54, 0x46, 0x4C, 0x00]),
        ),
        isFalse,
      );
    });

    test('reads square NCHW and NHWC layouts', () {
      final nchw = AnimeModelLayout.fromShape(<int>[1, 3, 512, 512]);
      expect(nchw.layout, AnimeTensorLayout.nchw);
      expect(nchw.side, 512);
      expect(nchw.shape, <int>[1, 3, 512, 512]);
      expect(nchw.elementCount, 3 * 512 * 512);

      final nhwc = AnimeModelLayout.fromShape(<int>[1, 256, 256, 3]);
      expect(nhwc.layout, AnimeTensorLayout.nhwc);
      expect(nhwc.side, 256);
      expect(nhwc.shape, <int>[1, 256, 256, 3]);
    });

    test('rejects unsupported tensor shapes', () {
      for (final shape in <List<int>>[
        <int>[3, 512, 512],
        <int>[2, 3, 512, 512],
        <int>[1, 3, 512, 256],
        <int>[1, 512, 512, 4],
        <int>[1, 4, 512, 512],
      ]) {
        expect(
          () => AnimeModelLayout.fromShape(shape),
          throwsA(isA<FormatException>()),
          reason: '$shape should be rejected',
        );
      }
    });
  });

  group('AnimeLetterbox', () {
    test('fits wide images with vertical padding', () {
      final fit = AnimeLetterbox.fit(
        sourceWidth: 400,
        sourceHeight: 300,
        modelSide: 512,
      );
      expect(fit.scaledWidth, 512);
      expect(fit.scaledHeight, 384);
      expect(fit.offsetX, 0);
      expect(fit.offsetY, 64);
      expect(fit.sourceX(256), closeTo(199.89, 0.01));
      expect(fit.sourceY(256), closeTo(149.89, 0.01));
      expect(fit.sourceY(0), 0);
      expect(fit.sourceY(511), 299);
    });

    test('fits tall images with horizontal padding', () {
      final fit = AnimeLetterbox.fit(
        sourceWidth: 300,
        sourceHeight: 400,
        modelSide: 512,
      );
      expect(fit.scaledWidth, 384);
      expect(fit.scaledHeight, 512);
      expect(fit.offsetX, 64);
      expect(fit.offsetY, 0);
      expect(fit.modelX(0, 384), 64);
      expect(fit.modelX(383, 384), 447);
    });

    test('rejects empty dimensions', () {
      expect(
        () => AnimeLetterbox.fit(
          sourceWidth: 0,
          sourceHeight: 10,
          modelSide: 512,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Anime preprocessing', () {
    test('writes normalized NCHW planes in RGB order', () {
      final image = _rgba(<List<int>>[
        <int>[255, 0, 0, 255],
        <int>[0, 0, 255, 255],
      ]);
      final model = AnimeModelLayout.fromShape(<int>[1, 3, 2, 2]);
      final tensor = buildAnimeInput(
        rgba: image,
        width: 2,
        height: 1,
        model: model,
      );

      expect(tensor.length, 12);
      // Top row: red then blue. The short image is padded with edge pixels.
      expect(tensor.sublist(0, 4), <double>[1, -1, 1, -1]);
      expect(tensor.sublist(4, 8), <double>[-1, -1, -1, -1]);
      expect(tensor.sublist(8, 12), <double>[-1, 1, -1, 1]);
    });

    test('writes normalized NHWC pixels in RGB order', () {
      final image = _rgba(<List<int>>[
        <int>[255, 0, 0, 255],
        <int>[0, 0, 255, 255],
      ]);
      final model = AnimeModelLayout.fromShape(<int>[1, 2, 2, 3]);
      final tensor = buildAnimeInput(
        rgba: image,
        width: 2,
        height: 1,
        model: model,
      );

      expect(tensor.length, 12);
      expect(tensor.sublist(0, 6), <double>[1, -1, -1, -1, -1, 1]);
      expect(tensor.sublist(6, 12), <double>[1, -1, -1, -1, -1, 1]);
    });

    test('flattens transparency onto white', () {
      final image = _rgba(<List<int>>[
        <int>[255, 0, 0, 0],
      ]);
      final model = AnimeModelLayout.fromShape(<int>[1, 1, 1, 3]);
      final tensor = buildAnimeInput(
        rgba: image,
        width: 1,
        height: 1,
        model: model,
      );
      expect(tensor.every((value) => value == 1.0), isTrue);
    });

    test('rejects short pixel buffers', () {
      expect(
        () => buildAnimeInput(
          rgba: Uint8List(3),
          width: 2,
          height: 2,
          model: AnimeModelLayout.fromShape(<int>[1, 2, 2, 3]),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Anime postprocessing', () {
    test('de-normalizes output and preserves RGB order', () {
      final values = Float32List(12);
      // NCHW 2x2. Top-left red, top-right blue.
      values[0] = 1;
      values[1] = -1;
      values[4] = -1;
      values[5] = -1;
      values[8] = -1;
      values[9] = 1;
      final output = _floatBytes(values);
      final model = AnimeModelLayout.fromShape(<int>[1, 3, 2, 2]);

      final rgba = animeOutputToRgba(
        output: output,
        model: model,
        sourceWidth: 2,
        sourceHeight: 1,
        destinationWidth: 2,
        destinationHeight: 1,
      );

      expect(rgba.length, 8);
      expect(rgba.sublist(0, 4), <int>[255, 0, 0, 255]);
      expect(rgba.sublist(4, 8), <int>[0, 0, 255, 255]);
    });

    test('maps a neutral tensor to mid grey', () {
      final values = Float32List(3);
      final output = _floatBytes(values);
      final model = AnimeModelLayout.fromShape(<int>[1, 1, 1, 3]);

      final rgba = animeOutputToRgba(
        output: output,
        model: model,
        sourceWidth: 1,
        sourceHeight: 1,
        destinationWidth: 1,
        destinationHeight: 1,
      );

      expect(rgba, <int>[128, 128, 128, 255]);
    });

    test('upsamples the generated area without letterbox padding', () {
      final values = Float32List(12);
      // A constant bright NCHW image; every output pixel should be white.
      for (var i = 0; i < values.length; i++) {
        values[i] = 1;
      }
      final model = AnimeModelLayout.fromShape(<int>[1, 3, 2, 2]);
      final rgba = animeOutputToRgba(
        output: _floatBytes(values),
        model: model,
        sourceWidth: 400,
        sourceHeight: 300,
        destinationWidth: 4,
        destinationHeight: 3,
      );

      expect(rgba.length, 4 * 3 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        expect(rgba.sublist(i, i + 4), <int>[255, 255, 255, 255]);
      }
    });

    test('rejects truncated or misaligned output', () {
      final model = AnimeModelLayout.fromShape(<int>[1, 1, 1, 3]);
      expect(
        () => animeOutputToRgba(
          output: Uint8List(8),
          model: model,
          sourceWidth: 1,
          sourceHeight: 1,
          destinationWidth: 1,
          destinationHeight: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
