import 'dart:math' as math;
import 'dart:typed_data';

/// Layout used by the anime model's single-image input tensor.
enum AnimeTensorLayout { nchw, nhwc }

/// The fixed square tensor contract of the bundled anime model.
class AnimeModelLayout {
  const AnimeModelLayout._(this.layout, this.side);

  factory AnimeModelLayout.fromShape(List<int> shape) {
    if (shape.length != 4 || shape[0] != 1) {
      throw FormatException(
        'The anime model must expose one 4-D image tensor, got $shape.',
      );
    }
    if (shape[1] == 3 && shape[2] > 0 && shape[2] == shape[3]) {
      return AnimeModelLayout._(AnimeTensorLayout.nchw, shape[2]);
    }
    if (shape[3] == 3 && shape[1] > 0 && shape[1] == shape[2]) {
      return AnimeModelLayout._(AnimeTensorLayout.nhwc, shape[1]);
    }
    throw FormatException(
      'The anime model must use a square 3-channel tensor, got $shape.',
    );
  }

  final AnimeTensorLayout layout;
  final int side;

  int get channels => 3;
  bool get isNchw => layout == AnimeTensorLayout.nchw;
  int get elementCount => channels * side * side;

  List<int> get shape =>
      isNchw ? <int>[1, channels, side, side] : <int>[1, side, side, channels];
}

/// Offset 4 is the flatbuffer file identifier used by every `.tflite` file.
bool hasTfliteMagic(Uint8List bytes) {
  return bytes.length >= 8 &&
      bytes[4] == 0x54 &&
      bytes[5] == 0x46 &&
      bytes[6] == 0x4C &&
      bytes[7] == 0x33;
}

/// Keeps the whole source image inside the model's square input without
/// stretching it. Padding replicates the nearest edge pixel instead of using
/// black bars, which keeps the generator from drawing hard borders into the
/// result.
class AnimeLetterbox {
  const AnimeLetterbox._({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.modelSide,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.offsetX,
    required this.offsetY,
  });

  factory AnimeLetterbox.fit({
    required int sourceWidth,
    required int sourceHeight,
    required int modelSide,
  }) {
    if (sourceWidth < 1 || sourceHeight < 1 || modelSide < 1) {
      throw ArgumentError('Image and model dimensions must be positive.');
    }
    final scale = modelSide / math.max(sourceWidth, sourceHeight);
    final scaledWidth = math.min(
      modelSide,
      math.max(1, (sourceWidth * scale).round()),
    );
    final scaledHeight = math.min(
      modelSide,
      math.max(1, (sourceHeight * scale).round()),
    );
    return AnimeLetterbox._(
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      modelSide: modelSide,
      scaledWidth: scaledWidth,
      scaledHeight: scaledHeight,
      offsetX: (modelSide - scaledWidth) ~/ 2,
      offsetY: (modelSide - scaledHeight) ~/ 2,
    );
  }

  final int sourceWidth;
  final int sourceHeight;
  final int modelSide;
  final int scaledWidth;
  final int scaledHeight;
  final int offsetX;
  final int offsetY;

  /// Maps a pixel centre in the model square back to the source image.
  double sourceX(double modelX) {
    final value = (modelX - offsetX + 0.5) * sourceWidth / scaledWidth - 0.5;
    return value.clamp(0.0, sourceWidth - 1.0).toDouble();
  }

  double sourceY(double modelY) {
    final value = (modelY - offsetY + 0.5) * sourceHeight / scaledHeight - 0.5;
    return value.clamp(0.0, sourceHeight - 1.0).toDouble();
  }

  /// Maps a destination pixel centre back into the model square, staying
  /// inside the letterboxed image and avoiding the padding.
  double modelX(double destinationX, int destinationWidth) {
    final value =
        offsetX + (destinationX + 0.5) * scaledWidth / destinationWidth - 0.5;
    return value
        .clamp(offsetX.toDouble(), (offsetX + scaledWidth - 1).toDouble())
        .toDouble();
  }

  double modelY(double destinationY, int destinationHeight) {
    final value =
        offsetY + (destinationY + 0.5) * scaledHeight / destinationHeight - 0.5;
    return value
        .clamp(offsetY.toDouble(), (offsetY + scaledHeight - 1).toDouble())
        .toDouble();
  }
}

/// Converts opaque RGBA into the normalized planar/interleaved float tensor
/// expected by AnimeGANv2. Input and output values use the range [-1, 1].
Float32List buildAnimeInput({
  required Uint8List rgba,
  required int width,
  required int height,
  required AnimeModelLayout model,
}) {
  if (width < 1 || height < 1) {
    throw ArgumentError('Image dimensions must be positive.');
  }
  if (rgba.length < width * height * 4) {
    throw ArgumentError(
      'Expected ${width * height * 4} RGBA bytes, received ${rgba.length}.',
    );
  }

  final side = model.side;
  final fit = AnimeLetterbox.fit(
    sourceWidth: width,
    sourceHeight: height,
    modelSide: side,
  );
  final x0 = Int32List(side);
  final x1 = Int32List(side);
  final tx = Float32List(side);
  for (var x = 0; x < side; x++) {
    final source = fit.sourceX(x.toDouble());
    final left = source.floor();
    x0[x] = left;
    x1[x] = math.min(left + 1, width - 1);
    tx[x] = source - left;
  }
  final y0 = Int32List(side);
  final y1 = Int32List(side);
  final ty = Float32List(side);
  for (var y = 0; y < side; y++) {
    final source = fit.sourceY(y.toDouble());
    final top = source.floor();
    y0[y] = top;
    y1[y] = math.min(top + 1, height - 1);
    ty[y] = source - top;
  }

  final plane = side * side;
  final output = Float32List(model.elementCount);
  var pixel = 0;
  for (var y = 0; y < side; y++) {
    final row0 = y0[y] * width;
    final row1 = y1[y] * width;
    final fy = ty[y];
    for (var x = 0; x < side; x++) {
      final left = x0[x];
      final right = x1[x];
      final fx = tx[x];

      final i00 = (row0 + left) * 4;
      final i10 = (row0 + right) * 4;
      final i01 = (row1 + left) * 4;
      final i11 = (row1 + right) * 4;

      final r = _sampleChannel(rgba, i00, i10, i01, i11, 0, fx, fy);
      final g = _sampleChannel(rgba, i00, i10, i01, i11, 1, fx, fy);
      final b = _sampleChannel(rgba, i00, i10, i01, i11, 2, fx, fy);

      if (model.isNchw) {
        output[pixel] = r / 127.5 - 1.0;
        output[plane + pixel] = g / 127.5 - 1.0;
        output[plane * 2 + pixel] = b / 127.5 - 1.0;
      } else {
        output[pixel * 3] = r / 127.5 - 1.0;
        output[pixel * 3 + 1] = g / 127.5 - 1.0;
        output[pixel * 3 + 2] = b / 127.5 - 1.0;
      }
      pixel++;
    }
  }
  return output;
}

double _sampleChannel(
  Uint8List rgba,
  int i00,
  int i10,
  int i01,
  int i11,
  int channel,
  double fx,
  double fy,
) {
  final p00 = _opaqueChannel(rgba, i00, channel);
  final p10 = _opaqueChannel(rgba, i10, channel);
  final p01 = _opaqueChannel(rgba, i01, channel);
  final p11 = _opaqueChannel(rgba, i11, channel);
  final top = p00 + (p10 - p00) * fx;
  final bottom = p01 + (p11 - p01) * fx;
  return top + (bottom - top) * fy;
}

double _opaqueChannel(Uint8List rgba, int offset, int channel) {
  final alpha = rgba[offset + 3];
  final value = rgba[offset + channel];
  if (alpha == 255) return value.toDouble();
  return (value * alpha + 255 * (255 - alpha)) / 255.0;
}

/// Converts model output back to opaque RGBA at the original image size,
/// cropping the letterbox padding and upsampling only the generated image area.
Uint8List animeOutputToRgba({
  required Uint8List output,
  required AnimeModelLayout model,
  required int sourceWidth,
  required int sourceHeight,
  required int destinationWidth,
  required int destinationHeight,
}) {
  if (sourceWidth < 1 ||
      sourceHeight < 1 ||
      destinationWidth < 1 ||
      destinationHeight < 1) {
    throw ArgumentError('Image dimensions must be positive.');
  }
  final expectedBytes = model.elementCount * 4;
  if (output.length < expectedBytes) {
    throw ArgumentError(
      'Expected $expectedBytes float output bytes, received ${output.length}.',
    );
  }
  if (output.offsetInBytes % 4 != 0) {
    throw ArgumentError('The model output buffer is not float-aligned.');
  }

  final values = output.buffer.asFloat32List(
    output.offsetInBytes,
    model.elementCount,
  );
  final side = model.side;
  final fit = AnimeLetterbox.fit(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    modelSide: side,
  );

  final x0 = Int32List(destinationWidth);
  final x1 = Int32List(destinationWidth);
  final tx = Float32List(destinationWidth);
  for (var x = 0; x < destinationWidth; x++) {
    final source = fit.modelX(x.toDouble(), destinationWidth);
    final left = source.floor();
    x0[x] = left;
    x1[x] = math.min(left + 1, fit.offsetX + fit.scaledWidth - 1);
    tx[x] = source - left;
  }
  final y0 = Int32List(destinationHeight);
  final y1 = Int32List(destinationHeight);
  final ty = Float32List(destinationHeight);
  for (var y = 0; y < destinationHeight; y++) {
    final source = fit.modelY(y.toDouble(), destinationHeight);
    final top = source.floor();
    y0[y] = top;
    y1[y] = math.min(top + 1, fit.offsetY + fit.scaledHeight - 1);
    ty[y] = source - top;
  }

  final rgba = Uint8List(destinationWidth * destinationHeight * 4);
  final plane = side * side;
  var destination = 0;
  for (var y = 0; y < destinationHeight; y++) {
    final row0 = y0[y] * side;
    final row1 = y1[y] * side;
    final fy = ty[y];
    for (var x = 0; x < destinationWidth; x++) {
      final i00 = row0 + x0[x];
      final i10 = row0 + x1[x];
      final i01 = row1 + x0[x];
      final i11 = row1 + x1[x];
      final fx = tx[x];

      if (model.isNchw) {
        for (var channel = 0; channel < 3; channel++) {
          final base = channel * plane;
          final value = _sampleFloat(
            values,
            base + i00,
            base + i10,
            base + i01,
            base + i11,
            fx,
            fy,
          );
          rgba[destination + channel] = _toByte(value);
        }
      } else {
        for (var channel = 0; channel < 3; channel++) {
          final value = _sampleFloat(
            values,
            i00 * 3 + channel,
            i10 * 3 + channel,
            i01 * 3 + channel,
            i11 * 3 + channel,
            fx,
            fy,
          );
          rgba[destination + channel] = _toByte(value);
        }
      }
      rgba[destination + 3] = 255;
      destination += 4;
    }
  }
  return rgba;
}

double _sampleFloat(
  Float32List values,
  int i00,
  int i10,
  int i01,
  int i11,
  double fx,
  double fy,
) {
  final top = values[i00] + (values[i10] - values[i00]) * fx;
  final bottom = values[i01] + (values[i11] - values[i01]) * fx;
  return top + (bottom - top) * fy;
}

int _toByte(double value) {
  if (!value.isFinite) return 0;
  final scaled = ((value + 1.0) * 127.5).round();
  if (scaled <= 0) return 0;
  if (scaled >= 255) return 255;
  return scaled;
}
