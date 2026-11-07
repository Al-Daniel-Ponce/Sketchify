import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sketchify/models/face_transform.dart';
import 'package:sketchify/services/face_transform/remote_face_transform_client.dart';

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

Future<RemoteFaceTransformResult> _transform(
  RemoteFaceTransformClient client, {
  FaceTransformDirection direction = FaceTransformDirection.feminize,
}) {
  return client.transform(
    rgba: _rgba(),
    width: 12,
    height: 8,
    direction: direction,
  );
}

void main() {
  test('posts an authenticated JPEG with the direction query', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        _jpeg(12, 8),
        200,
        headers: <String, String>{'content-type': 'image/jpeg'},
      );
    });
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform?key=1'),
      appToken: 'token-1234567890',
      client: client,
    );

    final result = await _transform(remote);

    expect(result.width, 12);
    expect(result.height, 8);
    expect(result.rgba.length, 12 * 8 * 4);
    expect(result.rgba[3], 255);
    expect(captured, isNotNull);
    expect(captured!.url.path, '/face-transform');
    expect(captured!.url.queryParameters['direction'], 'feminize');
    expect(captured!.url.queryParameters['key'], '1');
    expect(captured!.headers['authorization'], 'Bearer token-1234567890');
    expect(captured!.headers['content-type'], 'image/jpeg');
    expect(captured!.headers['accept'], 'image/jpeg');
    expect(captured!.bodyBytes.length, greaterThan(100));
    expect(captured!.bodyBytes[0], 0xFF);
    expect(captured!.bodyBytes[1], 0xD8);
  });

  test('sends the masculinize direction when asked', () async {
    http.Request? captured;
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
      appToken: 'token-1234567890',
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          _jpeg(12, 8),
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        );
      }),
    );

    await _transform(remote, direction: FaceTransformDirection.masculinize);

    expect(captured!.url.queryParameters['direction'], 'masculinize');
  });

  test('reports a rejected app token', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
      appToken: 'token-1234567890',
      client: MockClient((_) async => http.Response('nope', 401)),
    );

    await expectLater(
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('token'),
        ),
      ),
    );
  });

  test('reports a busy face transform service', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
      appToken: 'token-1234567890',
      client: MockClient((_) async => http.Response('busy', 429)),
    );

    await expectLater(
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('busy'),
        ),
      ),
    );
  });

  test('reports a server without a face model', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
      appToken: 'token-1234567890',
      client: MockClient((_) async => http.Response('disabled', 503)),
    );

    await expectLater(
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
  });

  test('rejects a result with the wrong dimensions', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
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
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('wrong size'),
        ),
      ),
    );
  });

  test('rejects a non-image response', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
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
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('unexpected response'),
        ),
      ),
    );
  });

  test('times out a slow face transform', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
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
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('longer than'),
        ),
      ),
    );
  });

  test('refuses to call the service without an app token', () async {
    final remote = RemoteFaceTransformClient(
      endpoint: Uri.parse('https://example.test/face-transform'),
      appToken: '',
      client: MockClient((_) async => http.Response('', 200)),
    );

    expect(remote.isConfigured, isFalse);
    await expectLater(
      _transform(remote),
      throwsA(
        isA<RemoteFaceTransformException>().having(
          (error) => error.message,
          'message',
          contains('not configured'),
        ),
      ),
    );
  });
}
