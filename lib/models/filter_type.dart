import 'package:flutter/material.dart';

import 'face_transform.dart';

/// The filters available in the photo editor.
enum FilterType {
  original,
  anime,
  sketch,
  edges,
  mono,
  noir,
  comic,
  vintage,
  poster,
  feminine,
  masculine,
  feminizeFace,
  masculinizeFace,
}

/// The subset offered on the camera screen. Editor-only looks deliberately
/// stay out of the viewfinder so the camera remains focused and quick.
const List<FilterType> cameraFilterTypes = <FilterType>[
  FilterType.original,
  FilterType.sketch,
  FilterType.anime,
  FilterType.edges,
];

extension FilterTypeX on FilterType {
  String get label => switch (this) {
    FilterType.original => 'Original',
    FilterType.anime => 'Anime',
    FilterType.sketch => 'Pencil Sketch',
    FilterType.edges => 'Edge Detection',
    FilterType.mono => 'Black & White',
    FilterType.noir => 'Noir',
    FilterType.comic => 'Comic Book',
    FilterType.vintage => 'Vintage',
    FilterType.poster => 'Poster',
    FilterType.feminine => 'Soft Portrait',
    FilterType.masculine => 'Bold Portrait',
    FilterType.feminizeFace => 'Feminize Face',
    FilterType.masculinizeFace => 'Masculinize Face',
  };

  String get shortLabel => switch (this) {
    FilterType.original => 'Original',
    FilterType.anime => 'Anime',
    FilterType.sketch => 'Sketch',
    FilterType.edges => 'Edges',
    FilterType.mono => 'Mono',
    FilterType.noir => 'Noir',
    FilterType.comic => 'Comic',
    FilterType.vintage => 'Vintage',
    FilterType.poster => 'Poster',
    FilterType.feminine => 'Soft',
    FilterType.masculine => 'Bold',
    FilterType.feminizeFace => 'Feminize',
    FilterType.masculinizeFace => 'Masculinize',
  };

  String get description => switch (this) {
    FilterType.original => 'The untouched photo.',
    FilterType.anime => 'AI restyles faces and scenery.',
    FilterType.sketch => 'Soft graphite shading on paper.',
    FilterType.edges => 'Clean outlines for tracing.',
    FilterType.mono => 'Clean black and white with crisp contrast.',
    FilterType.noir => 'Deep shadows and silver highlights.',
    FilterType.comic => 'Bold ink outlines and punchy colour.',
    FilterType.vintage => 'Warm, faded film tones.',
    FilterType.poster => 'Flat colour bands with strong contrast.',
    FilterType.feminine => 'Cosmetic soft-focus glow with warm rose tones.',
    FilterType.masculine =>
      'Cosmetic cool tones, deeper shadows and crisp detail.',
    FilterType.feminizeFace =>
      'Online AI edits the person with a more feminine presentation.',
    FilterType.masculinizeFace =>
      'Online AI edits the person with a more masculine presentation.',
  };

  IconData get icon => switch (this) {
    FilterType.original => Icons.photo_outlined,
    FilterType.anime => Icons.auto_awesome_outlined,
    FilterType.sketch => Icons.edit_outlined,
    FilterType.edges => Icons.gesture_outlined,
    FilterType.mono => Icons.contrast_rounded,
    FilterType.noir => Icons.dark_mode_outlined,
    FilterType.comic => Icons.auto_stories_outlined,
    FilterType.vintage => Icons.camera_roll_outlined,
    FilterType.poster => Icons.palette_outlined,
    FilterType.feminine => Icons.face_retouching_natural_outlined,
    FilterType.masculine => Icons.face_6_outlined,
    FilterType.feminizeFace => Icons.auto_fix_high_rounded,
    FilterType.masculinizeFace => Icons.auto_fix_normal_rounded,
  };

  /// The online face-transform direction, or null for every other filter.
  FaceTransformDirection? get faceTransformDirection => switch (this) {
    FilterType.feminizeFace => FaceTransformDirection.feminize,
    FilterType.masculinizeFace => FaceTransformDirection.masculinize,
    _ => null,
  };

  /// Anime is rendered by a neural network rather than by the pure-Dart pixel
  /// engine. Face transform is also AI, but it only runs through the proxy.
  bool get isAi => this == FilterType.anime || isFaceTransform;

  /// True for the two online-only face transform filters.
  bool get isFaceTransform => faceTransformDirection != null;

  /// Face transform has no local fallback, so it always needs the proxy.
  bool get requiresOnline => isFaceTransform;

  /// Cosmetic tone presets. These are not gender transformations.
  bool get isPortraitPreset =>
      this == FilterType.feminine || this == FilterType.masculine;

  bool get isProcessed => this != FilterType.original;
}

FilterType? filterTypeFromName(String? name) {
  if (name == null) return null;
  // Gallery indexes written by earlier builds stored the old Cartoon name.
  if (name == 'cartoon') return FilterType.anime;
  for (final filter in FilterType.values) {
    if (filter.name == name) return filter;
  }
  return null;
}
