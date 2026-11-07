import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sketchify/models/face_transform.dart';
import 'package:sketchify/models/filter_type.dart';
import 'package:sketchify/services/anime/anime_styler.dart';
import 'package:sketchify/services/anime/remote_anime_client.dart';
import 'package:sketchify/services/face_transform/remote_face_transform_client.dart';
import 'package:sketchify/services/image_processing_service.dart';

/// Small opaque PNG with a gradient and a dark square, so filters have both
/// smooth areas and hard edges to work with.
Uint8List _samplePng({int width = 32, int height = 24}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inSquare =
          x >= width ~/ 3 &&
          x < width * 2 ~/ 3 &&
          y >= height ~/ 3 &&
          y < height * 2 ~/ 3;
      image.setPixelRgba(
        x,
        y,
        inSquare ? 24 : 90 + (x * 3) % 120,
        inSquare ? 26 : 110 + (y * 4) % 100,
        inSquare ? 30 : 200 - (x * 2) % 80,
        255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _FakeAnimeStyler implements AnimeStyler {
  _FakeAnimeStyler({this.error});
  final Object? error;
  int stylizeCalls = 0;
  int warmUpCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
  }

  @override
  Future<AnimeStyledImage> stylize({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    stylizeCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return AnimeStyledImage(
      rgba: Uint8List.fromList(rgba),
      width: width,
      height: height,
      backend: 'CPU · 4 threads',
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class _FakeRemoteAnime implements RemoteAnimeClient {
  _FakeRemoteAnime({this.error, this.configured = true});

  final Object? error;
  final bool configured;
  int stylizeCalls = 0;
  int disposeCalls = 0;

  @override
  Uri get endpoint => Uri.parse('https://example.test/anime');

  @override
  Duration get timeout => const Duration(seconds: 60);

  @override
  bool get isConfigured => configured;

  @override
  Future<RemoteAnimeResult> stylize({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    stylizeCalls++;
    final failure = error;
    if (failure != null) throw failure;
    final tinted = Uint8List.fromList(rgba);
    for (var i = 0; i < tinted.length; i += 4) {
      tinted[i] = 10;
      tinted[i + 1] = 200;
      tinted[i + 2] = 50;
    }
    return RemoteAnimeResult(rgba: tinted, width: width, height: height);
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}

class _FakeRemoteFaceTransform implements RemoteFaceTransformClient {
  _FakeRemoteFaceTransform({this.error});

  final Object? error;
  int transformCalls = 0;
  int disposeCalls = 0;
  FaceTransformDirection? lastDirection;

  @override
  Uri get endpoint => Uri.parse('https://example.test/face-transform');

  @override
  Duration get timeout => const Duration(seconds: 120);

  @override
  bool get isConfigured => true;

  @override
  Future<RemoteFaceTransformResult> transform({
    required Uint8List rgba,
    required int width,
    required int height,
    required FaceTransformDirection direction,
  }) async {
    transformCalls++;
    lastDirection = direction;
    final failure = error;
    if (failure != null) throw failure;
    final tinted = Uint8List.fromList(rgba);
    for (var i = 0; i < tinted.length; i += 4) {
      tinted[i] = 240;
      tinted[i + 1] = 100;
      tinted[i + 2] = 160;
    }
    return RemoteFaceTransformResult(
      rgba: tinted,
      width: width,
      height: height,
    );
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageProcessingService Anime', () {
    test('marks a successful AI render and skips the local filter', () async {
      final anime = _FakeAnimeStyler();
      final service = ImageProcessingService(anime: anime);

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedAi, isTrue);
      expect(result.fallbackReason, isNull);
      expect(anime.stylizeCalls, 1);
      expect(result.filter, FilterType.anime);
      expect(result.width, 32);
      expect(result.height, 24);
      expect(result.bytes.length, greaterThan(4));
      expect(result.bytes[0], 0xFF);
      expect(result.bytes[1], 0xD8);
    });

    test('falls back to pure Dart when the AI styler throws', () async {
      final anime = _FakeAnimeStyler(
        error: const AnimeException('The AI model returned a flat image.'),
      );
      final service = ImageProcessingService(anime: anime);

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedAi, isFalse);
      expect(result.fallbackReason, 'The AI model returned a flat image.');
      expect(anime.stylizeCalls, 1);
      expect(result.filter, FilterType.anime);
      expect(result.width, 32);
      expect(result.height, 24);
      expect(result.bytes.length, greaterThan(4));
      expect(result.bytes[0], 0xFF);
      expect(result.bytes[1], 0xD8);
    });

    test('wraps non-Anime failures into the fallback reason', () async {
      final anime = _FakeAnimeStyler(error: StateError('worker died'));
      final service = ImageProcessingService(anime: anime);

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedAi, isFalse);
      expect(result.fallbackReason, contains('worker died'));
    });

    test('never calls the AI styler for deterministic filters', () async {
      final anime = _FakeAnimeStyler(error: StateError('must not run'));
      final service = ImageProcessingService(anime: anime);

      final result = await service.process(_samplePng(), FilterType.sketch);

      expect(anime.stylizeCalls, 0);
      expect(result.usedAi, isFalse);
      expect(result.fallbackReason, isNull);
      expect(result.filter, FilterType.sketch);
    });

    test('previews skip Anime so the picker never blocks', () async {
      final anime = _FakeAnimeStyler(error: StateError('must not run'));
      final service = ImageProcessingService(anime: anime);

      final previews = await service.generatePreviews(_samplePng());

      expect(anime.stylizeCalls, 0);
      expect(previews.containsKey(FilterType.anime), isFalse);
      expect(previews.containsKey(FilterType.original), isTrue);
      expect(previews.containsKey(FilterType.sketch), isTrue);
      expect(previews.containsKey(FilterType.edges), isTrue);
    });

    test('uses online anime first when the user opted in', () async {
      final remote = _FakeRemoteAnime();
      final anime = _FakeAnimeStyler(error: StateError('must not run'));
      final service = ImageProcessingService(
        anime: anime,
        remoteAnime: remote,
        onlineAnimeEnabled: () => true,
      );

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedAi, isTrue);
      expect(result.usedOnline, isTrue);
      expect(result.remoteFailureReason, isNull);
      expect(remote.stylizeCalls, 1);
      expect(anime.stylizeCalls, 0);
      expect(service.onlineAnimeConfigured, isTrue);
      expect(service.onlineAnimeEnabled, isTrue);
    });

    test('falls back to the on-device model when the proxy fails', () async {
      final remote = _FakeRemoteAnime(
        error: const RemoteAnimeException('The proxy is down.'),
      );
      final anime = _FakeAnimeStyler();
      final service = ImageProcessingService(
        anime: anime,
        remoteAnime: remote,
        onlineAnimeEnabled: () => true,
      );

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedAi, isTrue);
      expect(result.usedOnline, isFalse);
      expect(result.remoteFailureReason, 'The proxy is down.');
      expect(result.fallbackReason, isNull);
      expect(remote.stylizeCalls, 1);
      expect(anime.stylizeCalls, 1);
    });

    test('stays on-device when online anime is switched off', () async {
      var enabled = false;
      final remote = _FakeRemoteAnime();
      final anime = _FakeAnimeStyler();
      final service = ImageProcessingService(
        anime: anime,
        remoteAnime: remote,
        onlineAnimeEnabled: () => enabled,
      );

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedOnline, isFalse);
      expect(result.usedAi, isTrue);
      expect(remote.stylizeCalls, 0);
      expect(anime.stylizeCalls, 1);

      enabled = true;
      final online = await service.process(_samplePng(), FilterType.anime);
      expect(online.usedOnline, isTrue);
      expect(remote.stylizeCalls, 1);
    });

    test('uses the pure-Dart fallback when both AI paths fail', () async {
      final remote = _FakeRemoteAnime(
        error: const RemoteAnimeException('The proxy is down.'),
      );
      final anime = _FakeAnimeStyler(
        error: const AnimeException('The model returned a flat image.'),
      );
      final service = ImageProcessingService(
        anime: anime,
        remoteAnime: remote,
        onlineAnimeEnabled: () => true,
      );

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedAi, isFalse);
      expect(result.usedOnline, isFalse);
      expect(result.remoteFailureReason, 'The proxy is down.');
      expect(result.fallbackReason, 'The model returned a flat image.');
      expect(result.bytes[0], 0xFF);
      expect(result.bytes[1], 0xD8);
    });

    test('a configured remote is still off until the user opts in', () async {
      final remote = _FakeRemoteAnime();
      final service = ImageProcessingService(
        anime: _FakeAnimeStyler(),
        remoteAnime: remote,
      );

      expect(service.onlineAnimeConfigured, isTrue);
      expect(service.onlineAnimeEnabled, isFalse);
    });

    test('ignores a remote without an app token', () async {
      final remote = _FakeRemoteAnime(configured: false);
      final anime = _FakeAnimeStyler();
      final service = ImageProcessingService(
        anime: anime,
        remoteAnime: remote,
        onlineAnimeEnabled: () => true,
      );

      expect(service.onlineAnimeConfigured, isFalse);
      expect(service.onlineAnimeEnabled, isFalse);

      final result = await service.process(_samplePng(), FilterType.anime);

      expect(result.usedOnline, isFalse);
      expect(result.usedAi, isTrue);
      expect(remote.stylizeCalls, 0);
      expect(anime.stylizeCalls, 1);
    });
  });

  group('ImageProcessingService face transform', () {
    test('uses the online service and reports an online AI result', () async {
      final remote = _FakeRemoteFaceTransform();
      final anime = _FakeAnimeStyler(error: StateError('must not run'));
      final service = ImageProcessingService(
        anime: anime,
        remoteAnime: _FakeRemoteAnime(),
        onlineAnimeEnabled: () => true,
        remoteFaceTransform: remote,
        faceTransformEnabled: () => true,
      );

      final result = await service.process(
        _samplePng(),
        FilterType.feminizeFace,
      );

      expect(remote.transformCalls, 1);
      expect(remote.lastDirection, FaceTransformDirection.feminize);
      expect(anime.stylizeCalls, 0);
      expect(result.filter, FilterType.feminizeFace);
      expect(result.usedAi, isTrue);
      expect(result.usedOnline, isTrue);
      expect(result.fallbackReason, isNull);
      expect(result.remoteFailureReason, isNull);
      expect(result.width, 32);
      expect(result.height, 24);
      expect(result.bytes[0], 0xFF);
      expect(result.bytes[1], 0xD8);
      expect(service.faceTransformConfigured, isTrue);
      expect(service.faceTransformEnabled, isTrue);
    });

    test('routes masculinize to the other direction', () async {
      final remote = _FakeRemoteFaceTransform();
      final service = ImageProcessingService(
        remoteFaceTransform: remote,
        faceTransformEnabled: () => true,
      );

      final result = await service.process(
        _samplePng(),
        FilterType.masculinizeFace,
      );

      expect(remote.lastDirection, FaceTransformDirection.masculinize);
      expect(result.filter, FilterType.masculinizeFace);
      expect(result.usedOnline, isTrue);
    });

    test('fails clearly when the build has no face service', () async {
      final service = ImageProcessingService(anime: _FakeAnimeStyler());

      expect(service.faceTransformConfigured, isFalse);
      expect(service.faceTransformEnabled, isFalse);
      await expectLater(
        service.process(_samplePng(), FilterType.feminizeFace),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test('fails clearly when the user has not enabled the feature', () async {
      final remote = _FakeRemoteFaceTransform();
      final service = ImageProcessingService(
        remoteFaceTransform: remote,
        faceTransformEnabled: () => false,
      );

      expect(service.faceTransformConfigured, isTrue);
      expect(service.faceTransformEnabled, isFalse);
      await expectLater(
        service.process(_samplePng(), FilterType.masculinizeFace),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.message,
            'message',
            contains('turned off'),
          ),
        ),
      );
      expect(remote.transformCalls, 0);
    });

    test('surfaces proxy failures with no local fallback', () async {
      final remote = _FakeRemoteFaceTransform(
        error: const RemoteFaceTransformException('The proxy is down.'),
      );
      final anime = _FakeAnimeStyler(error: StateError('must not run'));
      final service = ImageProcessingService(
        anime: anime,
        remoteFaceTransform: remote,
        faceTransformEnabled: () => true,
      );

      await expectLater(
        service.process(_samplePng(), FilterType.feminizeFace),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.message,
            'message',
            contains('proxy is down'),
          ),
        ),
      );
      expect(remote.transformCalls, 1);
      expect(anime.stylizeCalls, 0);
    });

    test('wraps unexpected face service errors', () async {
      final remote = _FakeRemoteFaceTransform(error: StateError('socket'));
      final service = ImageProcessingService(
        remoteFaceTransform: remote,
        faceTransformEnabled: () => true,
      );

      await expectLater(
        service.process(_samplePng(), FilterType.feminizeFace),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.message,
            'message',
            contains('could not be completed'),
          ),
        ),
      );
    });

    test('previews skip both face transform directions', () async {
      final remote = _FakeRemoteFaceTransform();
      final service = ImageProcessingService(
        remoteFaceTransform: remote,
        faceTransformEnabled: () => true,
      );

      final previews = await service.generatePreviews(_samplePng());

      expect(remote.transformCalls, 0);
      expect(previews.containsKey(FilterType.feminizeFace), isFalse);
      expect(previews.containsKey(FilterType.masculinizeFace), isFalse);
      expect(previews.containsKey(FilterType.feminine), isTrue);
      expect(previews.containsKey(FilterType.masculine), isTrue);
    });
  });
}
