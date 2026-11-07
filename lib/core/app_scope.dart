import 'package:flutter/widgets.dart';

import '../services/gallery_repository.dart';
import '../services/image_picker_service.dart';
import '../services/image_processing_service.dart';
import '../services/library_service.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';

/// Provides long-lived services to the widget tree without a third-party
/// dependency-injection package.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.storage,
    required this.gallery,
    required this.processing,
    required this.picker,
    required this.library,
    required this.sensors,
    required super.child,
  });

  final SettingsService settings;
  final StorageService storage;
  final GalleryRepository gallery;
  final ImageProcessingService processing;
  final ImagePickerService picker;
  final LibraryService library;
  final SensorService sensors;

  static AppScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No AppScope found in the widget tree.');
    return scope!;
  }

  static AppScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>();
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
