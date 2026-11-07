import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// A hosted anime render returned by [RemoteAnimeClient].
class RemoteAnimeResult {
  const RemoteAnimeResult({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class RemoteAnimeException implements Exception {
  const RemoteAnimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends one photo to the Sketchify anime proxy and validates the result.
///
/// The proxy returns a JPEG with exactly the uploaded dimensions, so the app
/// can reject malformed replies and fall back to the on-device model.
class RemoteAnimeClient {
  RemoteAnimeClient({
    required this.endpoint,
    required String appToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _appToken = appToken,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const int maxUploadBytes = 8 * 1024 * 1024;
  static const int maxResponseBytes = 16 * 1024 * 1024;

  final Uri endpoint;
  final Duration timeout;
  final String _appToken;
  final http.Client _client;
  final bool _ownsClient;

  bool get isConfigured => _appToken.isNotEmpty;

  Future<RemoteAnimeResult> stylize({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    if (!isConfigured) {
      throw const RemoteAnimeException(
        'Online anime is not configured in this build.',
      );
    }

    final upload = await Isolate.run(() => _encodeUpload(rgba, width, height));

    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: <String, String>{
              'Authorization': 'Bearer $_appToken',
              'Content-Type': 'image/jpeg',
              'Accept': 'image/jpeg',
              'User-Agent': 'Sketchify-Android/1.0',
            },
            body: upload,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw RemoteAnimeException(
        'Online anime took longer than ${timeout.inSeconds} seconds.',
      );
    } catch (error) {
      throw const RemoteAnimeException(
        'The online anime service could not be reached.',
      );
    }

    if (response.statusCode != 200) {
      throw RemoteAnimeException(_messageForStatus(response.statusCode));
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
      throw const RemoteAnimeException(
        'The online anime service returned an unexpected response.',
      );
    }

    final body = response.bodyBytes;
    if (body.isEmpty) {
      throw const RemoteAnimeException(
        'The online anime service returned an empty image.',
      );
    }
    if (body.length > maxResponseBytes) {
      throw const RemoteAnimeException(
        'The online anime result was too large to use.',
      );
    }

    return Isolate.run(() => _decodeReply(body, width, height));
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static String _messageForStatus(int status) => switch (status) {
    401 || 403 => 'The online anime access token was rejected.',
    413 => 'This photo is too large for the online anime service.',
    415 => 'The online anime service does not accept this image format.',
    429 => 'The online anime service is busy. Try again shortly.',
    >= 500 => 'The online anime service is unavailable right now.',
    _ => 'Online anime failed (HTTP $status).',
  };
}

Uint8List _encodeUpload(Uint8List rgba, int width, int height) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    order: img.ChannelOrder.rgba,
    numChannels: 4,
  );

  for (final quality in <int>[92, 84, 76]) {
    final encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (encoded.length <= RemoteAnimeClient.maxUploadBytes || quality == 76) {
      if (encoded.length > RemoteAnimeClient.maxUploadBytes) {
        throw const RemoteAnimeException(
          'This photo is too large to send for online anime.',
        );
      }
      return encoded;
    }
  }
  throw const RemoteAnimeException(
    'This photo is too large to send for online anime.',
  );
}

RemoteAnimeResult _decodeReply(
  Uint8List body,
  int expectedWidth,
  int expectedHeight,
) {
  final decoded = img.decodeImage(body);
  if (decoded == null) {
    throw const RemoteAnimeException(
      'The online anime result was not a readable image.',
    );
  }
  if (decoded.width != expectedWidth || decoded.height != expectedHeight) {
    throw RemoteAnimeException(
      'The online anime result had the wrong size '
      '(${decoded.width}×${decoded.height} instead of '
      '$expectedWidth×$expectedHeight).',
    );
  }

  final rgba = decoded
      .convert(numChannels: 4, alpha: 255)
      .getBytes(order: img.ChannelOrder.rgba);
  return RemoteAnimeResult(
    rgba: Uint8List.fromList(rgba),
    width: decoded.width,
    height: decoded.height,
  );
}
