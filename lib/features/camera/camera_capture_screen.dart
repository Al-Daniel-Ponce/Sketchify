import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/error_utils.dart';
import '../../models/filter_type.dart';
import '../../services/camera_service.dart';
import '../../services/image_processing_service.dart';
import '../../shared/utils/ui_feedback.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../settings/widgets/online_anime_consent.dart';
import '../tracing/widgets/camera_preview_cover.dart';
import 'camera_result_screen.dart';
import 'widgets/camera_filter_strip.dart';
import 'widgets/camera_shutter_button.dart';

/// Full-screen camera that applies the selected filter as soon as a photo is
/// taken. The viewfinder itself stays unfiltered.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  /// Filter selection survives leaving and reopening the camera during the
  /// current app session.
  static FilterType _rememberedFilter = FilterType.sketch;

  final CameraService _cameraService = CameraService(
    defaultResolution: ResolutionPreset.veryHigh,
  );

  late AppScope _scope;
  bool _bootstrapped = false;

  FilterType _filter = _rememberedFilter;
  FlashMode _flashMode = FlashMode.off;
  CameraLensDirection _lens = CameraLensDirection.back;
  CameraStartResult? _cameraResult;
  bool _startingCamera = false;
  bool _cameraRestartQueued = false;
  int _cameraToken = 0;

  bool _busy = false;
  bool _resultOpen = false;
  Uint8List? _frozenFrame;
  String _busyMessage = '';
  String? _busyDetail;

  bool get _cameraReady => _cameraService.isReady;

  bool get _canCapture => _cameraReady && !_busy && !_startingCamera;

  bool get _isFrontCamera =>
      _lens == CameraLensDirection.front ||
      _cameraService.lensDirection == CameraLensDirection.front;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _scope = AppScope.of(context);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraToken++;
    unawaited(_cameraService.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_busy && !_resultOpen && !_cameraReady && !_startingCamera) {
          unawaited(_startCamera());
        }
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_busy) return;
        _cameraToken++;
        _cameraResult = null;
        unawaited(_cameraService.dispose());
        if (mounted) setState(() {});
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Camera lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _startCamera() async {
    if (_startingCamera) {
      _cameraRestartQueued = true;
      return;
    }
    final token = ++_cameraToken;
    _cameraRestartQueued = false;
    setState(() {
      _startingCamera = true;
      _cameraResult = null;
    });

    final result = await _cameraService.start(
      lens: _lens,
      resolution: ResolutionPreset.veryHigh,
    );

    if (token != _cameraToken) {
      // The screen was paused or disposed while the camera was starting.
      await _cameraService.dispose();
      _startingCamera = false;
      if (!mounted) return;
      setState(() {});
      if (_cameraRestartQueued) {
        _cameraRestartQueued = false;
        await _startCamera();
      }
      return;
    }

    if (!mounted) {
      await _cameraService.dispose();
      return;
    }

    _cameraRestartQueued = false;
    setState(() {
      _startingCamera = false;
      _cameraResult = result;
      _lens = _cameraService.lensDirection;
    });

    if (result.isReady && !_isFrontCamera) {
      await _cameraService.setFlashMode(_flashMode);
    }
  }

  Future<void> _handleCameraAction() async {
    if (_startingCamera) return;
    final status = _cameraResult?.status;
    if (status == CameraStartStatus.permissionPermanentlyDenied) {
      await _cameraService.openSettings();
      if (mounted) {
        showAppSnackBar(
          context,
          'Allow camera access in system settings, then return to Sketchify.',
        );
      }
      return;
    }
    await _startCamera();
  }

  Future<void> _flipCamera() async {
    if (_busy || _startingCamera || !_cameraReady) return;
    final target = _isFrontCamera
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    if (target == CameraLensDirection.front && !_cameraService.hasFrontCamera) {
      showAppSnackBar(context, 'This device has no front camera available.');
      return;
    }
    await appHaptic(_scope.settings);
    if (!mounted) return;
    setState(() => _lens = target);
    await _startCamera();
  }

  Future<void> _cycleFlash() async {
    if (!_cameraReady || _busy || _isFrontCamera) return;
    final previous = _flashMode;
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.off,
      _ => FlashMode.off,
    };
    await appHaptic(_scope.settings);
    if (!mounted) return;
    setState(() => _flashMode = next);
    final applied = await _cameraService.setFlashMode(next);
    if (!applied && mounted) {
      setState(() => _flashMode = previous);
      showAppSnackBar(context, 'Flash is not available on this camera.');
    }
  }

  // ---------------------------------------------------------------------------
  // Capture and conversion
  // ---------------------------------------------------------------------------

  void _selectFilter(FilterType filter) {
    if (_busy || filter == _filter) return;
    _rememberedFilter = filter;
    setState(() => _filter = filter);
    unawaited(appHaptic(_scope.settings));
  }

  Future<void> _capture() async {
    if (!_canCapture) return;

    final filter = _filter;
    final quality = _scope.settings.processingQuality.maxDimension;

    if (filter.isAi) {
      // Declining the notice turns online anime off; the capture then uses the
      // on-device model.
      await ensureOnlineAnimeConsent(context);
      if (!mounted || !_canCapture) return;
    }
    final onlineAnime = filter.isAi && _scope.processing.onlineAnimeEnabled;

    await appHaptic(_scope.settings, medium: true);
    if (!mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'Capturing photo…';
      _busyDetail = null;
    });

    Uint8List capture;
    try {
      capture = await _cameraService.takePicture();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnackBar(context, _captureError(error));
      unawaited(_startCamera());
      return;
    }

    if (!mounted) return;
    setState(() {
      _frozenFrame = capture;
      _busyMessage = filter.isAi
          ? (onlineAnime
                ? 'Sending your photo to online anime…'
                : 'Painting the anime scene…')
          : filter == FilterType.original
          ? 'Preparing your photo…'
          : 'Applying ${filter.label}…';
      _busyDetail = filter.isAi
          ? (onlineAnime
                ? 'Online anime is on. If the service is unavailable, '
                      'AnimeGANv2 finishes on this device.'
                : 'AnimeGANv2 runs fully on this device. '
                      'The first pass can take up to a minute.')
          : null;
    });

    // The preview is no longer needed while the image is processed, and
    // releasing it keeps memory available for the model and the photo.
    await _cameraService.dispose();
    if (!mounted) return;

    try {
      final processed = filter == FilterType.original
          ? await _prepareOriginal(capture)
          : await _scope.processing.process(
              capture,
              filter,
              maxDimension: quality,
            );
      if (!mounted) return;

      setState(() => _busy = false);
      _resultOpen = true;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CameraResultScreen(capturedBytes: capture, processed: processed),
        ),
      );
      _resultOpen = false;
      if (!mounted) return;
      setState(() {
        _frozenFrame = null;
        _cameraResult = null;
      });
      unawaited(_startCamera());
    } catch (error) {
      if (!mounted) return;
      _resultOpen = false;
      setState(() {
        _busy = false;
        _frozenFrame = null;
      });
      showAppSnackBar(context, friendlyError(error));
      unawaited(_startCamera());
    }
  }

  Future<ProcessedImage> _prepareOriginal(Uint8List bytes) async {
    final dimensions = await _scope.processing.probe(bytes);
    return ProcessedImage(
      bytes: bytes,
      width: dimensions.width,
      height: dimensions.height,
      filter: FilterType.original,
      elapsed: Duration.zero,
    );
  }

  String _captureError(Object error) {
    if (error is CameraException) {
      switch (error.code) {
        case 'CameraAccessDenied':
        case 'CameraAccessDeniedWithoutPrompt':
        case 'CameraAccessRestricted':
          return 'Camera access is needed to take a photo.';
        case 'CameraNotReady':
          return 'The camera is still getting ready. Please try again.';
      }
      return error.description ?? 'The photo could not be taken. Try again.';
    }
    return 'The photo could not be taken. Please try again.';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope<void>(
        canPop: !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !mounted) return;
          showAppSnackBar(
            context,
            'Hang tight — your photo is still being processed.',
          );
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
          body: LoadingOverlay(
            visible: _busy,
            message: _busyMessage,
            detail: _busyDetail,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackground(),
                if (_frozenFrame != null)
                  Image.memory(
                    _frozenFrame!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                _buildTopScrim(),
                _buildBottomScrim(),
                _buildTopBar(),
                _buildBottomPanel(),
                _buildStatusOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (_cameraReady) {
      final controller = _cameraService.controller;
      if (controller != null && controller.value.isInitialized) {
        return CameraPreviewCover(controller: controller);
      }
    }
    return const ColoredBox(color: Colors.black);
  }

  Widget _buildTopScrim() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 190,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomScrim() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 360,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final lensLabel = _isFrontCamera ? 'Front camera' : 'Rear camera';
    final flashActive = _flashMode != FlashMode.off;
    final flashIcon = switch (_flashMode) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always => Icons.flash_on_rounded,
      _ => Icons.flash_off_rounded,
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: Row(
            children: [
              _CircleIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close camera',
                onTap: () {
                  if (_busy) {
                    showAppSnackBar(
                      context,
                      'Hang tight — your photo is still being processed.',
                    );
                    return;
                  }
                  Navigator.of(context).maybePop();
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Snap & stylize',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$lensLabel · ${_filter.shortLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 11.5,
                        height: 1.2,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CircleIconButton(
                icon: flashIcon,
                tooltip: _isFrontCamera
                    ? 'Flash is only available on the rear camera'
                    : 'Flash: ${_flashMode.name}',
                active: flashActive && !_isFrontCamera,
                onTap: _cycleFlash,
                enabled: _cameraReady && !_busy && !_isFrontCamera,
              ),
              const SizedBox(width: 8),
              _CircleIconButton(
                icon: _isFrontCamera
                    ? Icons.camera_rear_rounded
                    : Icons.camera_front_rounded,
                tooltip: _isFrontCamera
                    ? 'Switch to rear camera'
                    : 'Switch to front camera',
                onTap: _flipCamera,
                enabled: _cameraReady && !_busy && !_startingCamera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Filters apply automatically after you take the photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CameraFilterStrip(
                selected: _filter,
                onSelected: _selectFilter,
                enabled: !_busy,
              ),
              const SizedBox(height: 8),
              CameraShutterButton(
                enabled: _canCapture,
                busy: _busy,
                onPressed: _capture,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOverlay() {
    if (_busy || _frozenFrame != null) return const SizedBox.shrink();
    if (_startingCamera || _cameraResult == null) {
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white70,
          ),
        ),
      );
    }
    final result = _cameraResult!;
    if (result.isReady) return const SizedBox.shrink();

    final issue = _issueFor(result);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 80, 28, 300),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(issue.icon, color: Colors.white, size: 34),
              const SizedBox(height: 14),
              Text(
                issue.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                issue.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              if (issue.actionLabel != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _handleCameraAction,
                    child: Text(issue.actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _CameraIssue _issueFor(CameraStartResult result) {
    switch (result.status) {
      case CameraStartStatus.permissionDenied:
        return const _CameraIssue(
          icon: Icons.no_photography_outlined,
          title: 'Camera access needed',
          message:
              'Allow camera access to take a photo. Your photos stay on this '
              'device.',
          actionLabel: 'Try again',
        );
      case CameraStartStatus.permissionPermanentlyDenied:
        return const _CameraIssue(
          icon: Icons.lock_outline_rounded,
          title: 'Camera access blocked',
          message:
              'Enable camera access for Sketchify in system settings, then '
              'return here.',
          actionLabel: 'Open settings',
        );
      case CameraStartStatus.noCamera:
        return const _CameraIssue(
          icon: Icons.videocam_off_outlined,
          title: 'No camera found',
          message: 'This device does not have a camera available.',
        );
      case CameraStartStatus.error:
        return _CameraIssue(
          icon: Icons.error_outline_rounded,
          title: 'Camera unavailable',
          message:
              result.message ??
              'The camera could not start. Close other camera apps and try '
                  'again.',
          actionLabel: 'Try again',
        );
      case CameraStartStatus.ready:
        return const _CameraIssue(
          icon: Icons.camera_alt_outlined,
          title: 'Camera ready',
          message: '',
        );
    }
  }
}

class _CameraIssue {
  const _CameraIssue({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.primary.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.42),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 21,
              color: enabled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
