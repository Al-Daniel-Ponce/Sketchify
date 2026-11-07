import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/models/overlay_controller.dart';

void main() {
  group('OverlayController', () {
    test('starts centred with the configured opacity', () {
      final controller = OverlayController(opacity: 0.5);
      addTearDown(controller.dispose);

      expect(controller.opacity, 0.5);
      expect(controller.scale, 1);
      expect(controller.rotation, 0);
      expect(controller.offset, Offset.zero);
      expect(controller.flipHorizontal, isFalse);
      expect(controller.locked, isFalse);
    });

    test('opacity is clamped to 0..1', () {
      final controller = OverlayController(opacity: 0.5);
      addTearDown(controller.dispose);

      controller.setOpacity(-0.4);
      expect(controller.opacity, 0);
      controller.setOpacity(1.7);
      expect(controller.opacity, 1);
      controller.opacity = 0.25;
      expect(controller.opacity, 0.25);
    });

    test('scale is clamped and zoomBy multiplies', () {
      final controller = OverlayController();
      addTearDown(controller.dispose);

      controller.setScale(0.01);
      expect(controller.scale, OverlayController.minScale);
      controller.setScale(99);
      expect(controller.scale, OverlayController.maxScale);

      controller.setScale(2);
      controller.zoomBy(1.5);
      expect(controller.scale, closeTo(3, 0.0001));
    });

    test('pan and transform are ignored while locked', () {
      final controller = OverlayController();
      addTearDown(controller.dispose);

      controller.panBy(const Offset(12, -8));
      expect(controller.offset, const Offset(12, -8));

      controller.setLocked(true);
      controller.panBy(const Offset(40, 40));
      controller.setOffset(const Offset(100, 100));
      expect(controller.offset, const Offset(12, -8));

      controller.toggleLocked();
      expect(controller.locked, isFalse);
      controller.panBy(const Offset(1, 1));
      expect(controller.offset, const Offset(13, -7));
    });

    test('rotation wraps into a single turn', () {
      final controller = OverlayController();
      addTearDown(controller.dispose);

      controller.rotateBy(math.pi * 2.5);
      expect(controller.rotation, lessThanOrEqualTo(math.pi));
      expect(controller.rotation, greaterThan(-math.pi));
      expect(controller.rotation, closeTo(math.pi * 0.5, 0.0001));

      controller.setRotation(-math.pi * 3);
      expect(controller.rotation, closeTo(-math.pi, 0.0001));
    });

    test('reset restores the transform but keeps opacity and lock', () {
      final controller = OverlayController(opacity: 0.8);
      addTearDown(controller.dispose);

      controller
        ..setScale(2.4)
        ..setRotation(1.2)
        ..panBy(const Offset(30, 20))
        ..toggleFlip()
        ..setLocked(true)
        ..reset();

      expect(controller.scale, 1);
      expect(controller.rotation, 0);
      expect(controller.offset, Offset.zero);
      expect(controller.flipHorizontal, isFalse);
      expect(controller.opacity, 0.8);
      expect(controller.locked, isTrue);
    });

    test('matrix applies translation, scale and flips', () {
      final controller = OverlayController();
      addTearDown(controller.dispose);

      controller.panBy(const Offset(15, -5));
      var matrix = controller.matrix;
      expect(matrix.getTranslation().x, closeTo(15, 0.0001));
      expect(matrix.getTranslation().y, closeTo(-5, 0.0001));

      controller.setScale(2);
      matrix = controller.matrix;
      expect(matrix.entry(0, 0), closeTo(2, 0.0001));
      expect(matrix.entry(1, 1), closeTo(2, 0.0001));

      controller.toggleFlip();
      matrix = controller.matrix;
      expect(matrix.entry(0, 0), closeTo(-2, 0.0001));
    });

    test('listeners are notified only for real changes', () {
      final controller = OverlayController();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setOpacity(0.6);
      controller.setOpacity(0.6);
      controller.panBy(Offset.zero);
      controller.setScale(1);
      expect(notifications, 1);

      controller.panBy(const Offset(2, 2));
      expect(notifications, 2);
    });
  });
}
