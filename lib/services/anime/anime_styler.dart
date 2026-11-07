import 'dart:typed_data';

/// A fully rendered anime frame. Pixel data is opaque RGBA at the size that
/// was requested from [AnimeStyler.stylize].
class AnimeStyledImage {
  const AnimeStyledImage({
    required this.rgba,
    required this.width,
    required this.height,
    required this.backend,
  });

  final Uint8List rgba;
  final int width;
  final int height;

  /// Short description of the runtime that produced the frame, such as
  /// `CPU · 4 threads`.
  final String backend;
}

class AnimeException implements Exception {
  const AnimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pluggable anime renderer. The production implementation runs AnimeGANv2 in
/// a worker isolate; tests and the pure-Dart fallback can provide alternatives
/// without touching TFLite.
abstract interface class AnimeStyler {
  /// Loads the model in the background. Failures are reported on the first
  /// [stylize] call rather than here.
  Future<void> warmUp();

  Future<AnimeStyledImage> stylize({
    required Uint8List rgba,
    required int width,
    required int height,
  });

  Future<void> dispose();
}
