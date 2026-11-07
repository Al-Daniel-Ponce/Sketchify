import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraStartStatus {
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  noCamera,
  error,
}

class CameraStartResult {
  const CameraStartResult(this.status, {this.message});

  final CameraStartStatus status;
  final String? message;

  bool get isReady => status == CameraStartStatus.ready;
}

/// Owns the camera controller used by tracing and photo capture.
class CameraService {
  CameraService({this.defaultResolution = ResolutionPreset.high});

  final ResolutionPreset defaultResolution;

  CameraController? _controller;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  FlashMode _flashMode = FlashMode.auto;

  CameraController? get controller => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  CameraLensDirection get lensDirection => _lensDirection;

  FlashMode get flashMode => _flashMode;

  bool get hasFrontCamera => _cameras.any(
    (camera) => camera.lensDirection == CameraLensDirection.front,
  );

  bool get hasRearCamera => _cameras.any(
    (camera) => camera.lensDirection == CameraLensDirection.back,
  );

  Future<CameraStartResult> start({
    CameraLensDirection lens = CameraLensDirection.back,
    ResolutionPreset? resolution,
  }) async {
    await dispose();
    _lensDirection = lens;

    var permission = await Permission.camera.status;
    if (!permission.isGranted) {
      if (permission.isPermanentlyDenied || permission.isRestricted) {
        return const CameraStartResult(
          CameraStartStatus.permissionPermanentlyDenied,
        );
      }
      permission = await Permission.camera.request();
    }

    if (!permission.isGranted) {
      return CameraStartResult(
        permission.isPermanentlyDenied
            ? CameraStartStatus.permissionPermanentlyDenied
            : CameraStartStatus.permissionDenied,
      );
    }

    try {
      final cameras = await availableCameras();
      _cameras = cameras;
      if (cameras.isEmpty) {
        return const CameraStartResult(CameraStartStatus.noCamera);
      }

      CameraDescription? preferred;
      for (final camera in cameras) {
        if (camera.lensDirection == lens) {
          preferred = camera;
          break;
        }
      }
      if (preferred == null && lens == CameraLensDirection.back) {
        for (final camera in cameras) {
          if (camera.lensDirection == CameraLensDirection.back) {
            preferred = camera;
            break;
          }
        }
      }

      final controller = CameraController(
        preferred ?? cameras.first,
        resolution ?? defaultResolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _controller = controller;
      _lensDirection = controller.description.lensDirection;
      await _applyFlashMode();
      return const CameraStartResult(CameraStartStatus.ready);
    } on CameraException catch (error) {
      await dispose();
      switch (error.code) {
        case 'CameraAccessDenied':
        case 'CameraAccessDeniedWithoutPrompt':
        case 'CameraAccessRestricted':
          return const CameraStartResult(CameraStartStatus.permissionDenied);
        case 'NoCamera':
          return const CameraStartResult(CameraStartStatus.noCamera);
        default:
          return CameraStartResult(
            CameraStartStatus.error,
            message: error.description ?? error.code,
          );
      }
    } catch (error) {
      await dispose();
      return CameraStartResult(
        CameraStartStatus.error,
        message: error.toString(),
      );
    }
  }

  /// Applies the stored flash mode, ignoring devices that do not expose one.
  /// The front camera always stays off, but the requested mode is kept so it
  /// applies again after switching back.
  Future<void> _applyFlashMode() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final mode = _lensDirection == CameraLensDirection.front
        ? FlashMode.off
        : _flashMode;
    try {
      await controller.setFlashMode(mode);
    } on CameraException {
      // Front cameras and some rear cameras do not support a flash mode.
    }
  }

  Future<bool> setFlashMode(FlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;
    try {
      await controller.setFlashMode(mode);
      _flashMode = mode;
      return true;
    } on CameraException {
      return false;
    }
  }

  /// Captures a full-resolution JPEG and removes the temporary platform file.
  Future<Uint8List> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraException(
        'CameraNotReady',
        'The camera is not ready yet. Please try again.',
      );
    }

    final file = await controller.takePicture();
    try {
      return await file.readAsBytes();
    } finally {
      try {
        await File(file.path).delete();
      } catch (_) {
        // The platform may have already cleaned up its temporary file.
      }
    }
  }

  Future<bool> openSettings() => openAppSettings();

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // The platform view may already be gone.
    }
  }
}
