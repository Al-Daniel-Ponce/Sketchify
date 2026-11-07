import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sketchify/services/anime/remote_anime_client.dart';

Uint8List _rgba({int width = 12, int height = 8}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      bytes[i] = 40 + (x * 11) % 180;
      bytes[i + 1] = 60 + (y * 17) % 160;
      bytes[i + 2] = 200 - (x * 7) % 140;
      bytes[i + 3] = 255;
    }
  }
  return bytes;
}

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, 30 + x * 5, 90 + y * 7, 180, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  test('posts an authenticated JPEG and accepts the matching reply', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        _jpeg(12, 8),
        200,
        headers: <String, String>{'content-type': 'image/jpeg'},
      );
    });
    final remote = RemoteAnimeClient(
      endpoint: Uri.parse('https://example.test/anime'),
      appToken: 'token-1234567890',
      client: client,
    );

    final result = await remote.stylize(rgba: _rgba(), width: 12, height: 8);

    expect(result.width, 12);
    expect(result.height, 8);
    expect(result.rgba.length, 12 * 8 * 4);
    expect(result.rgba[3], 255);
    expect(captured, isNotNull);
    expect(captured!.headers['authorization'], 'Bearer token-1234567890');
    expect(captured!.headers['content-type'], 'image/jpeg');
    expect(captured!.bodyBytes.length, greaterThan(100));
    expect(captured!.bodyBytes[0], 0xFF);
    expect(captured!.bodyBytes[1], 0xD8);
  });

  test('reports a rejected app token', () async {
    final remote = RemoteAnimeClient(
      endpoint: Uri.parse('https://example.test/anime'),
      appToken: 'token-1234567890',
      client: MockClient((_) async => http.Response('nope', 401)),
    );

    await expectLater(
      remote.stylize(rgba: _rgba(), width: 12, height: 8),
      throwsA(
        isA<RemoteAnimeException>().having(
          (error) => error.message,
          'message',
          contains('token'),
        ),
      ),
    );
  });

  test('rejects a result with the wrong dimensions', () async {
    final remote = RemoteAnimeClient(
      endpoint: Uri.parse('https://example.test/anime'),
      appToken: 'token-1234567890',
      client: MockClient(
        (_) async => http.Response.bytes(
          _jpeg(10, 8),
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        ),
      ),
    );

    await expectLater(
      remote.stylize(rgba: _rgba(), width: 12, height: 8),
      throwsA(
        isA<RemoteAnimeException>().having(
          (error) => error.message,
          'message',
          contains('wrong size'),
        ),
      ),
    );
  });

  test('rejects a non-image response', () async {
    final remote = RemoteAnimeClient(
      endpoint: Uri.parse('https://example.test/anime'),
      appToken: 'token-1234567890',
      client: MockClient(
        (_) async => http.Response(
          '{"error":"nope"}',
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      remote.stylize(rgba: _rgba(), width: 12, height: 8),
      throwsA(isA<RemoteAnimeException>()),
    );
  });

  test('times out a slow service', () async {
    final remote = RemoteAnimeClient(
      endpoint: Uri.parse('https://example.test/anime'),
      appToken: 'token-1234567890',
      timeout: const Duration(milliseconds: 20),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return http.Response.bytes(
          _jpeg(12, 8),
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        );
      }),
    );

    await expectLater(
      remote.stylize(rgba: _rgba(), width: 12, height: 8),
      throwsA(
        isA<RemoteAnimeException>().having(
          (error) => error.message,
          'message',
          contains('longer than'),
        ),
      ),
    );
  });

  test('refuses to call the service without an app token', () async {
    final remote = RemoteAnimeClient(
      endpoint: Uri.parse('https://example.test/anime'),
      appToken: '',
      client: MockClient((_) async => http.Response('', 200)),
    );

    expect(remote.isConfigured, isFalse);
    await expectLater(
      remote.stylize(rgba: _rgba(), width: 12, height: 8),
      throwsA(isA<RemoteAnimeException>()),
    );
  });
}
