import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/error_utils.dart';
import '../../models/gallery_item.dart';
import '../../models/level_reading.dart';
import '../../models/overlay_controller.dart';
import '../../services/camera_service.dart';
import '../../services/sensor_service.dart';
import '../../services/settings_service.dart';
import '../../shared/utils/ui_feedback.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'widgets/camera_preview_cover.dart';
import 'widgets/level_badge.dart';

/// Live camera tracing: the rear camera shows the paper, a translucent
/// reference image sits on top, and the Smart Level reports how flat the
/// phone is. No photos are captured from this screen.
class TracingScreen extends StatefulWidget {
  const TracingScreen({super.key, this.initialReference});

  final GalleryItem? initialReference;

  @override
  State<TracingScreen> createState() => _TracingScreenState();
}

class _TracingScreenState extends State<TracingScreen>
    with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();

  late AppScope _scope;
  late OverlayController _overlay;

  GalleryItem? _reference;
  CameraStartResult? _cameraResult;
  bool _startingCamera = false;
  bool _importingReference = false;
  bool _focusMode = false;
  bool _bootstrapped = false;
  bool _cameraRestartQueued = false;
  int _cameraToken = 0;

  double _gestureStartScale = 1;
  double _gestureStartRotation = 0;

  bool get _cameraReady => _cameraService.isReady;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    _scope = AppScope.of(context);
    _reference = widget.initialReference;
    _overlay = OverlayController(opacity: _scope.settings.defaultOpacity);

    WidgetsBinding.instance.addObserver(this);
    _scope.settings.addListener(_handleSettingsChanged);
    unawaited(_scope.sensors.start());
    unawaited(_applyWakelock());
    unawaited(_initCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_bootstrapped) {
      _scope.settings.removeListener(_handleSettingsChanged);
      unawaited(_scope.sensors.stop());
      _overlay.dispose();
    }
    _cameraToken++;
    unawaited(_cameraService.dispose());
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_scope.sensors.start());
        unawaited(_applyWakelock());
        if (!_cameraReady) {
          unawaited(_initCamera());
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _cameraToken++;
        _cameraResult = null;
        unawaited(_cameraService.dispose());
        unawaited(_scope.sensors.stop());
        unawaited(WakelockPlus.disable());
        if (mounted) setState(() {});
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Camera & sensors
  // ---------------------------------------------------------------------------

  Future<void> _initCamera() async {
    if (_startingCamera) {
      _cameraRestartQueued = true;
      return;
    }
    final token = ++_cameraToken;
    _cameraRestartQueued = false;
    setState(() => _startingCamera = true);

    final result = await _cameraService.start();

    if (token != _cameraToken) {
      // The screen was paused or disposed while the camera was starting.
      await _cameraService.dispose();
      _startingCamera = false;
      if (!mounted) return;
      setState(() {});
      if (_cameraRestartQueued) {
        _cameraRestartQueued = false;
        await _initCamera();
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
    });
  }

  Future<void> _handleCameraAction() async {
    if (_startingCamera) return;
    if (_cameraResult?.status ==
        CameraStartStatus.permissionPermanentlyDenied) {
      await _cameraService.openSettings();
      if (mounted) {
        showAppSnackBar(
          context,
          'Allow camera access in system settings, then return to Sketchify.',
        );
      }
      return;
    }
    await _initCamera();
  }

  Future<void> _applyWakelock() async {
    try {
      if (_scope.settings.keepScreenAwake) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Some desktop/emulator targets do not support wakelocks.
    }
  }

  void _handleSettingsChanged() {
    unawaited(_applyWakelock());
  }

  // ---------------------------------------------------------------------------
  // Reference handling
  // ---------------------------------------------------------------------------

  Future<void> _chooseReference() async {
    if (_importingReference) return;
    final current = _reference;
    final references = _scope.gallery.references;

    final selection = await showModalBottomSheet<_ReferenceSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.layers_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tracing reference',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            'Choose the image that appears over the camera.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ReferenceActionTile(
                  icon: Icons.add_photo_alternate_outlined,
                  title: 'Choose from photos',
                  subtitle: 'Imported into your Sketchify gallery',
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(const _ReferenceSelection.pick()),
                ),
                if (references.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'SAVED REFERENCES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 112,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: references.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = references[index];
                        final selected = current?.id == item.id;
                        return _ReferenceThumb(
                          item: item,
                          selected: selected,
                          onTap: () => Navigator.of(
                            sheetContext,
                          ).pop(_ReferenceSelection.use(item)),
                        );
                      },
                    ),
                  ),
                ],
                if (current != null) ...[
                  const SizedBox(height: 14),
                  _ReferenceActionTile(
                    icon: Icons.layers_clear_outlined,
                    title: 'Remove reference',
                    subtitle: 'Take the overlay off the camera',
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(const _ReferenceSelection.remove()),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selection == null) return;
    switch (selection.action) {
      case _ReferenceAction.pick:
        await _importReference();
        break;
      case _ReferenceAction.use:
        final item = selection.item;
        if (item != null) _adoptReference(item);
        break;
      case _ReferenceAction.remove:
        setState(() => _reference = null);
        _overlay.reset();
        appHaptic(_scope.settings);
        break;
    }
  }

  Future<void> _importReference() async {
    if (_importingReference) return;
    setState(() => _importingReference = true);
    try {
      final item = await _scope.library.pickAndImport(
        type: GalleryItemType.reference,
      );
      if (!mounted) return;
      if (item != null) {
        _adoptReference(item);
        showAppSnackBar(context, 'Tracing reference added to your gallery.');
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _importingReference = false);
    }
  }

  void _adoptReference(GalleryItem item) {
    appHaptic(_scope.settings, medium: true);
    setState(() => _reference = item);
    _overlay.reset();
  }

  // ---------------------------------------------------------------------------
  // Overlay interaction
  // ---------------------------------------------------------------------------

  void _handleScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _overlay.scale;
    _gestureStartRotation = _overlay.rotation;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale != 1.0) {
      _overlay.setScale(_gestureStartScale * details.scale);
    }
    if (details.rotation != 0) {
      _overlay.setRotation(_gestureStartRotation + details.rotation);
    }
    if (details.focalPointDelta != Offset.zero) {
      _overlay.panBy(details.focalPointDelta);
    }
  }

  void _fitOverlay() {
    _overlay.setScale(1);
    _overlay.setRotation(0);
    _overlay.setOffset(Offset.zero);
    appHaptic(_scope.settings);
  }

  void _rotateOverlay() {
    _overlay.rotateBy(math.pi / 12);
    appHaptic(_scope.settings);
  }

  void _flipOverlay() {
    _overlay.toggleFlip();
    appHaptic(_scope.settings);
  }

  void _toggleLock() {
    _overlay.toggleLocked();
    appHaptic(_scope.settings, medium: true);
  }

  // ---------------------------------------------------------------------------
  // Chrome actions
  // ---------------------------------------------------------------------------

  void _toggleFocusMode() {
    appHaptic(_scope.settings);
    setState(() => _focusMode = !_focusMode);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _focusMode ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  void _openLevelSheet() {
    appHaptic(_scope.settings);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _LevelSheet(sensors: _scope.sensors, settings: _scope.settings),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final badgeTop = _focusMode ? topInset + 10 : topInset + 84;
    final chipTop = _focusMode ? topInset + 60 : topInset + 84;
    final reference = _reference;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: LoadingOverlay(
          visible: _importingReference,
          message: 'Adding your reference…',
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(),
              if (reference != null) _buildOverlay(reference),
              if (!_focusMode) _buildTopBar(),
              Positioned(
                top: badgeTop,
                right: 12,
                child: ValueListenableBuilder<LevelReading>(
                  valueListenable: _scope.sensors.reading,
                  builder: (context, reading, _) {
                    return LevelBadge(reading: reading, onTap: _openLevelSheet);
                  },
                ),
              ),
              if (reference != null)
                Positioned(top: chipTop, left: 12, child: _buildCameraChip()),
              if (reference == null && !_focusMode)
                Center(child: _buildReferenceCallToAction())
              else if (reference != null && !_focusMode)
                _buildControls(),
              if (_focusMode)
                Positioned(
                  top: topInset + 8,
                  left: 12,
                  child: _GlassIconButton(
                    icon: Icons.visibility_rounded,
                    tooltip: 'Show controls',
                    onTap: _toggleFocusMode,
                  ),
                ),
            ],
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
    if (_cameraResult?.status == CameraStartStatus.noCamera) {
      return const _PaperBackdrop();
    }
    return const ColoredBox(color: Colors.black);
  }

  Widget _buildOverlay(GalleryItem reference) {
    final decodeWidth = math.min(
      2400,
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round(),
    );

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _overlay,
        builder: (context, _) {
          final interactive = !_overlay.locked;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: interactive ? _handleScaleStart : null,
            onScaleUpdate: interactive ? _handleScaleUpdate : null,
            onDoubleTap: interactive ? _fitOverlay : null,
            child: Transform(
              transform: _overlay.matrix,
              alignment: Alignment.center,
              child: Opacity(
                opacity: _overlay.opacity,
                child: Image.file(
                  File(reference.imagePath),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  cacheWidth: decodeWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 34,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'This reference image could not be opened.',
                              style: TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    final reference = _reference;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
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
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Row(
              children: [
                _GlassIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close tracing',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Camera tracing',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reference?.title ?? 'Point at your paper and trace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11.5,
                          height: 1.2,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _GlassIconButton(
                  icon: Icons.fullscreen_rounded,
                  tooltip: 'Hide controls',
                  onTap: _toggleFocusMode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferenceCallToAction() {
    final theme = Theme.of(context);
    final issueTitle = _cameraIssueTitle;
    final issueMessage = _cameraIssueMessage;
    final actionLabel = _cameraIssueActionLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[AppColors.primary, AppColors.secondary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.layers_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Add a tracing reference',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a photo and it will float over the live camera. Adjust '
                'its opacity and position until the lines are easy to follow.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _chooseReference,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose reference'),
                ),
              ),
              if (issueTitle != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      if (_startingCamera)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      else
                        Icon(
                          Icons.videocam_off_outlined,
                          size: 19,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              issueTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (issueMessage != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                issueMessage,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 10.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (actionLabel != null)
                        TextButton(
                          onPressed: _handleCameraAction,
                          child: Text(
                            actionLabel,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraChip() {
    final label = _cameraStatusChipLabel;
    if (label == null) return const SizedBox.shrink();
    final canTap = !_startingCamera;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canTap ? _handleCameraAction : null,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_startingCamera)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white54,
                  ),
                )
              else
                Icon(
                  Icons.videocam_off_outlined,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (canTap) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 0,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: AnimatedBuilder(
          animation: _overlay,
          builder: (context, _) {
            final locked = _overlay.locked;
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.opacity_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Opacity',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.primary,
                            overlayColor: AppColors.primary.withValues(
                              alpha: 0.18,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 18,
                            ),
                          ),
                          child: Slider(
                            value: _overlay.opacity,
                            divisions: 20,
                            semanticFormatterCallback: (value) =>
                                '${(value * 100).round()} percent',
                            onChanged: (value) {
                              _overlay.setOpacity(value);
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${(_overlay.opacity * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: _OverlayToolButton(
                          icon: Icons.add_photo_alternate_outlined,
                          label: 'Change',
                          onTap: _chooseReference,
                        ),
                      ),
                      Expanded(
                        child: _OverlayToolButton(
                          icon: Icons.fit_screen_rounded,
                          label: 'Fit',
                          onTap: _fitOverlay,
                        ),
                      ),
                      Expanded(
                        child: _OverlayToolButton(
                          icon: Icons.rotate_right_rounded,
                          label: 'Rotate',
                          onTap: _rotateOverlay,
                        ),
                      ),
                      Expanded(
                        child: _OverlayToolButton(
                          icon: Icons.flip_rounded,
                          label: 'Flip',
                          active: _overlay.flipHorizontal,
                          onTap: _flipOverlay,
                        ),
                      ),
                      Expanded(
                        child: _OverlayToolButton(
                          icon: locked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          label: locked ? 'Locked' : 'Lock',
                          active: locked,
                          onTap: _toggleLock,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        locked
                            ? Icons.lock_outline_rounded
                            : Icons.gesture_rounded,
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          locked
                              ? 'Overlay locked. Unlock to move, zoom or rotate.'
                              : 'Drag to move · pinch to zoom · twist to rotate · double-tap to fit',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera status copy
  // ---------------------------------------------------------------------------

  CameraStartStatus? get _cameraStatus => _cameraResult?.status;

  String? get _cameraIssueTitle {
    if (_cameraReady) return null;
    if (_startingCamera) return 'Starting camera';
    return switch (_cameraStatus) {
      CameraStartStatus.permissionDenied => 'Camera access needed',
      CameraStartStatus.permissionPermanentlyDenied => 'Camera is blocked',
      CameraStartStatus.noCamera => 'No rear camera',
      CameraStartStatus.error => 'Camera unavailable',
      CameraStartStatus.ready => null,
      null => 'Starting camera',
    };
  }

  String? get _cameraIssueMessage {
    if (_cameraReady) return null;
    if (_startingCamera) return 'The live preview will appear in a moment.';
    return switch (_cameraStatus) {
      CameraStartStatus.permissionDenied =>
        'Allow camera access to see your paper behind the reference.',
      CameraStartStatus.permissionPermanentlyDenied =>
        'Enable camera permission in system settings to use the preview.',
      CameraStartStatus.noCamera =>
        'You can still arrange and trace the reference on a plain backdrop.',
      CameraStartStatus.error =>
        'The camera could not start. The reference overlay still works.',
      CameraStartStatus.ready => null,
      null => 'The live preview will appear in a moment.',
    };
  }

  String? get _cameraIssueActionLabel {
    if (_cameraReady || _startingCamera) return null;
    return switch (_cameraStatus) {
      CameraStartStatus.permissionPermanentlyDenied => 'Settings',
      CameraStartStatus.noCamera => 'Retry',
      _ => 'Try again',
    };
  }

  String? get _cameraStatusChipLabel {
    if (_cameraReady) return null;
    if (_startingCamera) return 'Starting camera…';
    return switch (_cameraStatus) {
      CameraStartStatus.permissionDenied => 'Camera off · tap to allow',
      CameraStartStatus.permissionPermanentlyDenied =>
        'Camera blocked · tap for settings',
      CameraStartStatus.noCamera => 'No camera · reference only',
      CameraStartStatus.error => 'Camera error · tap to retry',
      CameraStartStatus.ready => null,
      null => 'Starting camera…',
    };
  }
}

// -----------------------------------------------------------------------------
// Reference sheet pieces
// -----------------------------------------------------------------------------

enum _ReferenceAction { pick, use, remove }

class _ReferenceSelection {
  const _ReferenceSelection.pick()
    : action = _ReferenceAction.pick,
      item = null;

  const _ReferenceSelection.use(GalleryItem this.item)
    : action = _ReferenceAction.use;

  const _ReferenceSelection.remove()
    : action = _ReferenceAction.remove,
      item = null;

  final _ReferenceAction action;
  final GalleryItem? item;
}

class _ReferenceActionTile extends StatelessWidget {
  const _ReferenceActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 21, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceThumb extends StatelessWidget {
  const _ReferenceThumb({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GalleryItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 88,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Image.file(
                    File(item.thumbPath ?? item.imagePath),
                    fit: BoxFit.cover,
                    cacheWidth: 220,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.broken_image_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small chrome widgets
// -----------------------------------------------------------------------------

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _OverlayToolButton extends StatelessWidget {
  const _OverlayToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active
                        ? Colors.white.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: active ? const Color(0xFF2A1206) : Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.62),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Smart Level sheet
// -----------------------------------------------------------------------------

class _LevelSheet extends StatelessWidget {
  const _LevelSheet({required this.sensors, required this.settings});

  final SensorService sensors;
  final SettingsService settings;

  static Color _statusColor(LevelStatus status) => switch (status) {
    LevelStatus.good => AppColors.success,
    LevelStatus.warning => AppColors.warning,
    LevelStatus.tilted => AppColors.danger,
    LevelStatus.unavailable => AppColors.textSecondary,
  };

  Future<void> _calibrate(BuildContext context) async {
    final ok = await sensors.calibrate();
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Level calibrated to this angle.'
          : 'Hold the phone still for a moment, then calibrate.',
    );
  }

  Future<void> _resetCalibration(BuildContext context) async {
    await sensors.resetCalibration();
    if (!context.mounted) return;
    showAppSnackBar(context, 'Level calibration cleared.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final sensitivity = settings.levelSensitivity;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.square_foot_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Smart Level', style: theme.textTheme.titleMedium),
                        Text(
                          'Keep the phone flat for accurate tracing.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<LevelReading>(
                valueListenable: sensors.reading,
                builder: (context, reading, _) {
                  final color = _statusColor(reading.status);
                  return Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              reading.angleText,
                              style: TextStyle(
                                color: color,
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.6,
                                height: 1,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                reading.statusLabel.toUpperCase(),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (reading.status == LevelStatus.unavailable)
                          Text(
                            'This device is not reporting accelerometer data. '
                            'The camera and reference still work normally.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          )
                        else ...[
                          Text(
                            reading.calibrated
                                ? 'Angle relative to your calibrated position.'
                                : 'Angle relative to a perfectly flat phone.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          if (reading.hint.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.subdirectory_arrow_right_rounded,
                                  size: 16,
                                  color: color,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${reading.hint} a little',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _LegendDot(
                              color: AppColors.success,
                              label:
                                  '≤ ${sensitivity.thresholds.goodMax.toStringAsFixed(0)}°',
                            ),
                            const SizedBox(width: 14),
                            _LegendDot(
                              color: AppColors.warning,
                              label:
                                  '≤ ${sensitivity.thresholds.warningMax.toStringAsFixed(0)}°',
                            ),
                            const SizedBox(width: 14),
                            const _LegendDot(
                              color: AppColors.danger,
                              label: 'Tilted',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Text('Calibration', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Place the phone exactly how you want the level to read zero, '
                'keep it still, then calibrate.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<LevelReading>(
                valueListenable: sensors.reading,
                builder: (context, reading, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: reading.status == LevelStatus.unavailable
                              ? null
                              : () => _calibrate(context),
                          icon: const Icon(Icons.center_focus_strong_rounded),
                          label: const Text('Calibrate'),
                        ),
                      ),
                      if (reading.calibrated) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _resetCalibration(context),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset'),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              Text('Sensitivity', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<LevelSensitivity>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                segments: [
                  for (final value in LevelSensitivity.values)
                    ButtonSegment<LevelSensitivity>(
                      value: value,
                      label: Text(value.label),
                    ),
                ],
                selected: <LevelSensitivity>{sensitivity},
                onSelectionChanged: (selection) {
                  settings.setLevelSensitivity(selection.first);
                },
              ),
              const SizedBox(height: 8),
              Text(
                sensitivity.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Camera-less backdrop
// -----------------------------------------------------------------------------

class _PaperBackdrop extends StatelessWidget {
  const _PaperBackdrop();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _PaperPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFF5F0E7), Color(0xFFE1D9CC)],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final grid = Paint()
      ..color = const Color(0x0F000000)
      ..strokeWidth = 1;
    const step = 30.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        radius: 0.85,
        colors: <Color>[
          Colors.transparent,
          const Color(0xFF3A3226).withValues(alpha: 0.18),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) => false;
}
