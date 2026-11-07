import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'anime_styler.dart';
import 'anime_tensor.dart';

/// Runs AnimeGANv2 in a dedicated worker isolate.
///
/// The isolate is owned by this class instead of [IsolateInterpreter] so that
/// native failures and tensor-contract errors are reported back to the UI
/// instead of leaving a future pending forever.
class AnimeEngine implements AnimeStyler {
  AnimeEngine({
    this.assetPath = 'assets/models/anime_gan_v2.tflite',
    this.timeout = const Duration(seconds: 60),
    this.startupTimeout = const Duration(seconds: 30),
  });

  static const int _threads = 4;

  final String assetPath;
  final Duration timeout;
  final Duration startupTimeout;

  Uint8List? _modelBytes;
  bool _unavailable = false;
  bool _disposed = false;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Future<void>? _starting;
  int _generation = 0;
  int _nextRequest = 0;
  String _backend = 'CPU · 4 threads';

  final Map<int, Completer<AnimeStyledImage>> _pending =
      <int, Completer<AnimeStyledImage>>{};

  String get backend => _backend;

  @override
  Future<void> warmUp() async {
    try {
      await _ensureStarted();
    } catch (error) {
      debugPrint('Anime warm-up skipped: $error');
    }
  }

  @override
  Future<AnimeStyledImage> stylize({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    if (_disposed) {
      throw const AnimeException('The anime engine has been closed.');
    }
    if (_unavailable) {
      throw const AnimeException('The on-device anime model is unavailable.');
    }
    await _ensureStarted();

    final commands = _commands;
    if (commands == null) {
      throw const AnimeException('The anime engine is not ready yet.');
    }

    final id = ++_nextRequest;
    final completer = Completer<AnimeStyledImage>();
    _pending[id] = completer;
    commands.send(
      _AnimeRequest(
        id,
        TransferableTypedData.fromList(<Uint8List>[Uint8List.fromList(rgba)]),
        width,
        height,
      ),
    );

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      final error = AnimeException(
        'Anime rendering took longer than ${timeout.inSeconds} seconds.',
      );
      // Drop the timed-out request before tearing the worker down so its late
      // response cannot complete an abandoned future.
      _pending.remove(id);
      _teardownWorker(error);
      throw error;
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _ensureStarted() async {
    if (_commands != null) return;
    final inFlight = _starting;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _start();
    _starting = future;
    try {
      await future;
    } finally {
      if (identical(_starting, future)) {
        _starting = null;
      }
    }
  }

  Future<void> _start() async {
    final bytes = await _loadModelBytes();
    final ready = Completer<_AnimeReady>();
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final generation = ++_generation;

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<List<Object?>>(
        _animeWorkerMain,
        <Object?>[
          responses.sendPort,
          TransferableTypedData.fromList(<Uint8List>[bytes]),
          _threads,
        ],
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'anime-inference',
      );
    } catch (error) {
      responses.close();
      errors.close();
      exits.close();
      _generation++;
      throw AnimeException('The anime worker could not be started: $error');
    }

    _isolate = isolate;
    _responses = responses;
    _errors = errors;
    _exits = exits;

    responses.listen((message) {
      if (message is _AnimeReady) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is _AnimeResponse) {
        final completer = _pending.remove(message.id);
        if (completer == null || completer.isCompleted) return;
        if (message.error != null) {
          completer.completeError(AnimeException(message.error!));
          return;
        }
        final data = message.rgba!.materialize().asUint8List();
        completer.complete(
          AnimeStyledImage(
            rgba: data,
            width: message.width,
            height: message.height,
            backend: message.backend ?? _backend,
          ),
        );
        return;
      }
      if (message is _AnimeWorkerFailure && !ready.isCompleted) {
        ready.completeError(AnimeException(message.message));
      }
    });

    errors.listen((message) {
      final detail = message is List && message.isNotEmpty
          ? '${message.first}'
          : 'unknown error';
      final error = AnimeException('The anime worker crashed: $detail');
      debugPrint('Anime worker error: $detail');
      if (!ready.isCompleted) ready.completeError(error);
      _handleWorkerFailure(error, generation);
    });

    exits.listen((_) {
      final error = const AnimeException(
        'The anime worker stopped unexpectedly.',
      );
      if (!ready.isCompleted) ready.completeError(error);
      _handleWorkerFailure(error, generation);
    });

    try {
      final info = await ready.future.timeout(startupTimeout);
      if (generation != _generation) {
        throw const AnimeException('The anime engine was restarted.');
      }
      _commands = info.commandPort;
      _backend = info.backend;
    } catch (error) {
      final failure = error is AnimeException
          ? error
          : error is TimeoutException
          ? const AnimeException('The anime model did not start in time.')
          : AnimeException('The anime model could not start: $error');
      if (generation == _generation) {
        _teardownWorker(failure);
      }
      throw failure;
    }
  }

  Future<Uint8List> _loadModelBytes() async {
    final cached = _modelBytes;
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = Uint8List.fromList(
        Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
      );
      if (!hasTfliteMagic(bytes)) {
        _unavailable = true;
        throw const AnimeException(
          'The bundled anime model is damaged or incomplete.',
        );
      }
      _modelBytes = bytes;
      return bytes;
    } on AnimeException {
      rethrow;
    } catch (error) {
      _unavailable = true;
      throw AnimeException(
        'The bundled anime model could not be loaded: $error',
      );
    }
  }

  void _handleWorkerFailure(Object error, int generation) {
    if (generation != _generation || _disposed) return;
    _teardownWorker(error);
  }

  void _teardownWorker(Object error) {
    final isolate = _isolate;
    _isolate = null;
    _commands = null;
    _generation++;

    _responses?.close();
    _errors?.close();
    _exits?.close();
    _responses = null;
    _errors = null;
    _exits = null;

    isolate?.kill(priority: Isolate.immediate);
    _failPending(error);
  }

  void _failPending(Object error) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(
          error is AnimeException ? error : AnimeException('$error'),
        );
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _teardownWorker(const AnimeException('The anime engine has been closed.'));
  }
}

void _animeWorkerMain(List<Object?> args) {
  final mainPort = args[0] as SendPort;
  final modelData = args[1] as TransferableTypedData;
  final threads = args[2] as int;
  final commands = ReceivePort();

  late final _AnimeRuntime runtime;
  try {
    final modelBytes = modelData.materialize().asUint8List();
    runtime = _AnimeRuntime.create(modelBytes, threads);
    mainPort.send(
      _AnimeReady(
        commandPort: commands.sendPort,
        backend: _AnimeRuntime.backend,
      ),
    );
  } catch (error) {
    mainPort.send(_AnimeWorkerFailure('$error'));
    commands.close();
    return;
  }

  commands.listen((message) {
    if (message is! _AnimeRequest) return;
    try {
      final rgba = message.rgba.materialize().asUint8List();
      final result = runtime.stylize(rgba, message.width, message.height);
      mainPort.send(
        _AnimeResponse.success(
          message.id,
          TransferableTypedData.fromList(<Uint8List>[result.rgba]),
          result.backend,
          message.width,
          message.height,
        ),
      );
    } catch (error) {
      mainPort.send(_AnimeResponse.failure(message.id, '$error'));
    }
  });
}

class _AnimeRuntime {
  _AnimeRuntime._({
    required Interpreter interpreter,
    required this.layout,
    required Tensor inputTensor,
    required Tensor outputTensor,
  }) : _interpreter = interpreter,
       _inputTensor = inputTensor,
       _outputTensor = outputTensor;

  /// XNNPack is deliberately not used: it segfaulted inside
  /// `libtensorflowlite_jni.so` while loading the model on a real arm64
  /// device. The reference CPU kernels are slower but stable.
  static const String backend = 'CPU · 4 threads';

  final AnimeModelLayout layout;
  final Interpreter _interpreter;
  final Tensor _inputTensor;
  final Tensor _outputTensor;

  static _AnimeRuntime create(Uint8List modelBytes, int threads) {
    final options = InterpreterOptions()..threads = threads;
    Interpreter? interpreter;
    try {
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      if (input.type != TensorType.float32 ||
          output.type != TensorType.float32) {
        throw AnimeException(
          'Expected float32 tensors, got ${input.type} → ${output.type}.',
        );
      }
      final layout = AnimeModelLayout.fromShape(input.shape);
      final outputLayout = AnimeModelLayout.fromShape(output.shape);
      if (outputLayout.layout != layout.layout ||
          outputLayout.side != layout.side) {
        throw AnimeException(
          'Input and output tensor layouts do not match: '
          '${input.shape} → ${output.shape}.',
        );
      }
      return _AnimeRuntime._(
        interpreter: interpreter,
        layout: layout,
        inputTensor: input,
        outputTensor: output,
      );
    } catch (error) {
      interpreter?.close();
      if (error is AnimeException) rethrow;
      throw AnimeException('The anime model could not be loaded: $error');
    } finally {
      options.delete();
    }
  }

  _AnimeRunResult stylize(Uint8List rgba, int width, int height) {
    try {
      return _AnimeRunResult(_invoke(rgba, width, height), backend);
    } on AnimeException {
      rethrow;
    } catch (error) {
      throw AnimeException('Anime inference failed: $error');
    }
  }

  Uint8List _invoke(Uint8List rgba, int width, int height) {
    final input = buildAnimeInput(
      rgba: rgba,
      width: width,
      height: height,
      model: layout,
    );
    _inputTensor.data = input.buffer.asUint8List(
      input.offsetInBytes,
      input.lengthInBytes,
    );
    _interpreter.invoke();

    final rawOutput = _outputTensor.data;
    final output = rawOutput.offsetInBytes % 4 == 0
        ? rawOutput
        : Uint8List.fromList(rawOutput);
    final result = animeOutputToRgba(
      output: output,
      model: layout,
      sourceWidth: width,
      sourceHeight: height,
      destinationWidth: width,
      destinationHeight: height,
    );
    if (_stdOfRgb(rgba) > 8.0 && _stdOfRgb(result) < 2.0) {
      throw const AnimeException('The AI model returned a flat image.');
    }
    return result;
  }

  static double _stdOfRgb(Uint8List rgba) {
    final pixels = rgba.length ~/ 4;
    if (pixels == 0) return 0;
    final step = math.max(1, pixels ~/ 4096);
    var count = 0;
    var sum = 0.0;
    var sumSquares = 0.0;
    for (var pixel = 0; pixel < pixels; pixel += step) {
      final offset = pixel * 4;
      final luminance =
          0.299 * rgba[offset] +
          0.587 * rgba[offset + 1] +
          0.114 * rgba[offset + 2];
      sum += luminance;
      sumSquares += luminance * luminance;
      count++;
    }
    final mean = sum / count;
    final variance = sumSquares / count - mean * mean;
    return variance <= 0 ? 0 : math.sqrt(variance);
  }
}

class _AnimeRunResult {
  const _AnimeRunResult(this.rgba, this.backend);

  final Uint8List rgba;
  final String backend;
}

class _AnimeRequest {
  const _AnimeRequest(this.id, this.rgba, this.width, this.height);

  final int id;
  final TransferableTypedData rgba;
  final int width;
  final int height;
}

class _AnimeReady {
  const _AnimeReady({required this.commandPort, required this.backend});

  final SendPort commandPort;
  final String backend;
}

class _AnimeWorkerFailure {
  const _AnimeWorkerFailure(this.message);

  final String message;
}

class _AnimeResponse {
  const _AnimeResponse.success(
    this.id,
    this.rgba,
    this.backend,
    this.width,
    this.height,
  ) : error = null;

  const _AnimeResponse.failure(this.id, this.error)
    : rgba = null,
      backend = null,
      width = 0,
      height = 0;

  final int id;
  final TransferableTypedData? rgba;
  final String? backend;
  final int width;
  final int height;
  final String? error;
}
