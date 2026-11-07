abstract final class AppConstants {
  static const String appName = 'Sketchify';
  static const String tagline = 'AI anime, sketch & camera tracing';
  static const String version = '1.0.0';

  /// Longest edge used when running a filter. Keeps memory bounded on
  /// high-resolution phone photos.
  static const int maxProcessingDimension = 2048;

  /// Longest edge for the small filter previews shown in the picker.
  static const int previewDimension = 220;

  /// Longest edge for gallery thumbnails.
  static const int thumbnailDimension = 520;

  static const int homeRecentLimit = 8;
  static const int maxCachedFilters = 4;
}
