import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Fills the available space with the camera preview while preserving its
/// aspect ratio (cover, not letterboxed).
class CameraPreviewCover extends StatelessWidget {
  const CameraPreviewCover({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const ColoredBox(color: Colors.black);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }
}
