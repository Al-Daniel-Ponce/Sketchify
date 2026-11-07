import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../models/face_transform.dart';

/// A hosted face transform returned by [RemoteFaceTransformClient].
class RemoteFaceTransformResult {
  const RemoteFaceTransformResult({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class RemoteFaceTransformException implements Exception {
  const RemoteFaceTransformException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends one photo to the Sketchify face-transform proxy.
///
/// The proxy returns a JPEG with exactly the uploaded dimensions, so the app
/// can reject malformed replies. Unlike Anime, there is no local fallback:
/// if the proxy cannot transform the photo, the user sees an error.
class RemoteFaceTransformClient {
  RemoteFaceTransformClient({
    required this.endpoint,
    required String appToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 120),
  }) : _appToken = appToken,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const int maxUploadBytes = 8 * 1024 * 1024;
  static const int maxResponseBytes = 20 * 1024 * 1024;

  final Uri endpoint;
  final Duration timeout;
  final String _appToken;
  final http.Client _client;
  final bool _ownsClient;

  bool get isConfigured => _appToken.isNotEmpty;

  Future<RemoteFaceTransformResult> transform({
    required Uint8List rgba,
    required int width,
    required int height,
    required FaceTransformDirection direction,
  }) async {
    if (!isConfigured) {
      throw const RemoteFaceTransformException(
        'Online face transform is not configured in this build.',
      );
    }

    final target = endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'direction': direction.wireName,
      },
    );

    final upload = await Isolate.run(() => _encodeUpload(rgba, width, height));

    http.Response response;
    try {
      response = await _client
          .post(
            target,
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
      throw RemoteFaceTransformException(
        'The face transform took longer than ${timeout.inSeconds} seconds.',
      );
    } catch (error) {
      throw const RemoteFaceTransformException(
        'The face transform service could not be reached.',
      );
    }

    if (response.statusCode != 200) {
      throw RemoteFaceTransformException(
        _messageForStatus(response.statusCode),
      );
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
      throw const RemoteFaceTransformException(
        'The face transform service returned an unexpected response.',
      );
    }

    final body = response.bodyBytes;
    if (body.isEmpty) {
      throw const RemoteFaceTransformException(
        'The face transform service returned an empty image.',
      );
    }
    if (body.length > maxResponseBytes) {
      throw const RemoteFaceTransformException(
        'The face transform result was too large to use.',
      );
    }

    return Isolate.run(() => _decodeReply(body, width, height));
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static String _messageForStatus(int status) => switch (status) {
    400 => 'The face transform request was rejected.',
    401 || 403 => 'The face transform access token was rejected.',
    413 => 'This photo is too large for the face transform service.',
    415 => 'The face transform service does not accept this image format.',
    422 => 'The face transform service could not process this photo.',
    429 => 'The face transform service is busy. Try again shortly.',
    503 => 'Online face transform is not configured on the server.',
    >= 500 => 'The face transform service is unavailable right now.',
    _ => 'Face transform failed (HTTP $status).',
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
    if (encoded.length <= RemoteFaceTransformClient.maxUploadBytes ||
        quality == 76) {
      if (encoded.length > RemoteFaceTransformClient.maxUploadBytes) {
        throw const RemoteFaceTransformException(
          'This photo is too large to send for face transform.',
        );
      }
      return encoded;
    }
  }
  throw const RemoteFaceTransformException(
    'This photo is too large to send for face transform.',
  );
}

RemoteFaceTransformResult _decodeReply(
  Uint8List body,
  int expectedWidth,
  int expectedHeight,
) {
  final decoded = img.decodeImage(body);
  if (decoded == null) {
    throw const RemoteFaceTransformException(
      'The face transform result was not a readable image.',
    );
  }
  if (decoded.width != expectedWidth || decoded.height != expectedHeight) {
    throw RemoteFaceTransformException(
      'The face transform result had the wrong size '
      '(${decoded.width}×${decoded.height} instead of '
      '$expectedWidth×$expectedHeight).',
    );
  }

  final rgba = decoded
      .convert(numChannels: 4, alpha: 255)
      .getBytes(order: img.ChannelOrder.rgba);
  return RemoteFaceTransformResult(
    rgba: Uint8List.fromList(rgba),
    width: decoded.width,
    height: decoded.height,
  );
}
