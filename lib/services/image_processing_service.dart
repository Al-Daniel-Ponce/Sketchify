import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../models/filter_type.dart';
import 'anime/anime_styler.dart';
import 'anime/remote_anime_client.dart';
import 'face_transform/remote_face_transform_client.dart';
import 'filters/filter_engine.dart';

class ImageProcessingException implements Exception {
  ImageProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;
}

class ProcessedImage {
  const ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.filter,
    required this.elapsed,
    this.usedAi = false,
    this.usedOnline = false,
    this.fallbackReason,
    this.remoteFailureReason,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final FilterType filter;
  final Duration elapsed;

  /// True when the anime result came from a neural model, on-device or online.
  final bool usedAi;

  /// True when [usedAi] came from an optional online AI service.
  final bool usedOnline;

  /// Why the pure-Dart fallback ran, when [usedAi] is false for Anime.
  final String? fallbackReason;

  /// Why the online attempt was skipped in favour of the on-device model.
  final String? remoteFailureReason;
}

/// Decodes images at a bounded resolution, runs filters in a background
/// isolate, and encodes the result as JPEG.
class ImageProcessingService {
  ImageProcessingService({
    AnimeStyler? anime,
    RemoteAnimeClient? remoteAnime,
    bool Function()? onlineAnimeEnabled,
    RemoteFaceTransformClient? remoteFaceTransform,
    bool Function()? faceTransformEnabled,
  }) : _anime = anime,
       _remoteAnime = remoteAnime,
       _onlineAnimeEnabled = onlineAnimeEnabled,
       _remoteFaceTransform = remoteFaceTransform,
       _faceTransformEnabled = faceTransformEnabled;

  final AnimeStyler? _anime;
  final RemoteAnimeClient? _remoteAnime;
  final bool Function()? _onlineAnimeEnabled;
  final RemoteFaceTransformClient? _remoteFaceTransform;
  final bool Function()? _faceTransformEnabled;

  /// Whether this build has a proxy URL and app token configured.
  bool get onlineAnimeConfigured => _remoteAnime?.isConfigured ?? false;

  /// Whether the user opted in and this build can reach the proxy.
  bool get onlineAnimeEnabled =>
      onlineAnimeConfigured && (_onlineAnimeEnabled?.call() ?? false);

  /// Whether this build has a face-transform proxy URL and app token.
  bool get faceTransformConfigured =>
      _remoteFaceTransform?.isConfigured ?? false;

  /// Whether the user opted in and this build can reach the face proxy.
  bool get faceTransformEnabled =>
      faceTransformConfigured && (_faceTransformEnabled?.call() ?? false);

  Future<ImageDimensions> probe(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) {
        throw ImageProcessingException('The image has no pixel data.');
      }
      return ImageDimensions(descriptor.width, descriptor.height);
    } on ImageProcessingException {
      rethrow;
    } catch (_) {
      throw ImageProcessingException(
        'This file is not a supported image. Try a JPG or PNG.',
      );
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<ProcessedImage> process(
    Uint8List sourceBytes,
    FilterType filter, {
    int maxDimension = AppConstants.maxProcessingDimension,
  }) async {
    final stopwatch = Stopwatch()..start();
    final decoded = await _decode(sourceBytes, maxDimension);
    final quality = filter == FilterType.edges ? 95 : 93;

    if (filter.isFaceTransform) {
      return _processFaceTransform(decoded, filter, quality, stopwatch);
    }

    Uint8List? encoded;
    var usedAi = false;
    var usedOnline = false;
    String? fallbackReason;
    String? remoteFailureReason;

    if (filter.isAi) {
      final remote = _remoteAnime;
      final tryOnline =
          remote != null &&
          remote.isConfigured &&
          (_onlineAnimeEnabled?.call() ?? false);

      if (tryOnline) {
        try {
          final styled = await remote.stylize(
            rgba: decoded.bytes,
            width: decoded.width,
            height: decoded.height,
          );
          encoded = await Isolate.run(
            () =>
                _encodeJpeg(styled.rgba, styled.width, styled.height, quality),
          );
          usedAi = true;
          usedOnline = true;
        } catch (error) {
          remoteFailureReason = error is RemoteAnimeException
              ? error.message
              : '$error';
          debugPrint('Online anime unavailable, trying on-device: $error');
        }
      }

      if (encoded == null && _anime != null) {
        try {
          final styled = await _anime.stylize(
            rgba: decoded.bytes,
            width: decoded.width,
            height: decoded.height,
          );
          encoded = await Isolate.run(
            () =>
                _encodeJpeg(styled.rgba, styled.width, styled.height, quality),
          );
          usedAi = true;
        } catch (error) {
          fallbackReason = error is AnimeException ? error.message : '$error';
          debugPrint('Anime AI unavailable, using local fallback: $error');
        }
      }

      encoded ??= await _runFilter(decoded, filter, quality);
    } else {
      encoded = await _runFilter(decoded, filter, quality);
    }

    stopwatch.stop();
    return ProcessedImage(
      bytes: encoded,
      width: decoded.width,
      height: decoded.height,
      filter: filter,
      elapsed: stopwatch.elapsed,
      usedAi: usedAi,
      usedOnline: usedOnline,
      fallbackReason: fallbackReason,
      remoteFailureReason: remoteFailureReason,
    );
  }

  /// Face transform is online-only. Failures are surfaced to the UI instead of
  /// falling back to a local filter that would not actually transform anyone.
  Future<ProcessedImage> _processFaceTransform(
    _DecodedImage decoded,
    FilterType filter,
    int quality,
    Stopwatch stopwatch,
  ) async {
    final remote = _remoteFaceTransform;
    if (remote == null || !remote.isConfigured) {
      throw ImageProcessingException(
        'Online face transform is not configured in this build.',
      );
    }
    if (!(_faceTransformEnabled?.call() ?? false)) {
      throw ImageProcessingException(
        'Online face transform is turned off. Enable it in Settings.',
      );
    }

    final direction = filter.faceTransformDirection;
    if (direction == null) {
      throw ImageProcessingException(
        'This face transform direction is not supported.',
      );
    }

    try {
      final transformed = await remote.transform(
        rgba: decoded.bytes,
        width: decoded.width,
        height: decoded.height,
        direction: direction,
      );
      final encoded = await Isolate.run(
        () => _encodeJpeg(
          transformed.rgba,
          transformed.width,
          transformed.height,
          quality,
        ),
      );
      stopwatch.stop();
      return ProcessedImage(
        bytes: encoded,
        width: decoded.width,
        height: decoded.height,
        filter: filter,
        elapsed: stopwatch.elapsed,
        usedAi: true,
        usedOnline: true,
      );
    } on RemoteFaceTransformException catch (error) {
      throw ImageProcessingException(error.message);
    } catch (error) {
      debugPrint('Face transform failed: $error');
      throw ImageProcessingException(
        'The face transform could not be completed. Please try again.',
      );
    }
  }

  Future<Uint8List> _runFilter(
    _DecodedImage decoded,
    FilterType filter,
    int quality,
  ) async {
    final job = _FilterJob(
      rgba: TransferableTypedData.fromList(<Uint8List>[decoded.bytes]),
      width: decoded.width,
      height: decoded.height,
      filter: filter,
      quality: quality,
    );
    try {
      return await Isolate.run(() => _runFilterJob(job));
    } catch (_) {
      throw ImageProcessingException(
        'The filter could not be applied. Please try again.',
      );
    }
  }

  /// Runs the fast filters once at preview resolution. Anime and face
  /// transform are intentionally skipped: their AI passes belong in the
  /// editor, after the user chooses them.
  Future<Map<FilterType, Uint8List>> generatePreviews(
    Uint8List sourceBytes, {
    int maxDimension = AppConstants.previewDimension,
  }) async {
    final decoded = await _decode(sourceBytes, maxDimension);
    final previews = <FilterType, Uint8List>{};

    for (final filter in FilterType.values) {
      if (filter.isAi) continue;
      final copy = Uint8List.fromList(decoded.bytes);
      final job = _FilterJob(
        rgba: TransferableTypedData.fromList([copy]),
        width: decoded.width,
        height: decoded.height,
        filter: filter,
        quality: 82,
      );
      try {
        previews[filter] = await Isolate.run(() => _runFilterJob(job));
      } catch (_) {
        // A single preview failing should not block the rest.
      }
    }
    return previews;
  }

  Future<Uint8List> makeThumbnail(
    Uint8List sourceBytes, {
    int maxDimension = AppConstants.thumbnailDimension,
  }) async {
    final decoded = await _decode(sourceBytes, maxDimension);
    final pixels = decoded.bytes;
    final width = decoded.width;
    final height = decoded.height;
    return Isolate.run(() => _encodeJpeg(pixels, width, height, 86));
  }

  Future<_DecodedImage> _decode(Uint8List bytes, int maxDimension) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;

    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        throw ImageProcessingException('The image has no pixel data.');
      }

      final longestEdge = math.max(sourceWidth, sourceHeight);
      final scale = longestEdge > maxDimension
          ? maxDimension / longestEdge
          : 1.0;
      final targetWidth = math.max(1, (sourceWidth * scale).round());
      final targetHeight = math.max(1, (sourceHeight * scale).round());

      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) {
        throw ImageProcessingException('Could not read the image pixels.');
      }
      final pixels = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return _DecodedImage(
        bytes: pixels,
        width: image.width,
        height: image.height,
      );
    } on ImageProcessingException {
      rethrow;
    } catch (_) {
      throw ImageProcessingException(
        'This image could not be opened. Try a different photo.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class _DecodedImage {
  const _DecodedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

class _FilterJob {
  const _FilterJob({
    required this.rgba,
    required this.width,
    required this.height,
    required this.filter,
    required this.quality,
  });

  final TransferableTypedData rgba;
  final int width;
  final int height;
  final FilterType filter;
  final int quality;
}

Uint8List _runFilterJob(_FilterJob job) {
  final rgba = job.rgba.materialize().asUint8List();
  final filtered = FilterEngine.apply(
    rgba: rgba,
    width: job.width,
    height: job.height,
    filter: job.filter,
  );
  return _encodeJpeg(filtered, job.width, job.height, job.quality);
}

Uint8List _encodeJpeg(Uint8List rgba, int width, int height, int quality) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    order: img.ChannelOrder.rgba,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
