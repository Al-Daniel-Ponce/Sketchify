import 'package:flutter/material.dart';

import 'filter_type.dart';

/// The fixed prompt chips shown in the editor's Quick styles sheet.
enum QuickStyle {
  cartoonCharacter(
    'Cartoon character',
    FilterType.anime,
    Icons.auto_awesome_rounded,
  ),
  blackAndWhite('Black & white', FilterType.mono, Icons.contrast_rounded),
  comicBook('Comic book', FilterType.comic, Icons.auto_stories_outlined),
  pencilDrawing('Pencil drawing', FilterType.sketch, Icons.edit_outlined),
  cleanOutline('Clean outline', FilterType.edges, Icons.gesture_outlined),
  oldPhoto('Old photo', FilterType.vintage, Icons.camera_roll_outlined),
  dramaticNoir('Dramatic noir', FilterType.noir, Icons.dark_mode_outlined),
  softPortrait(
    'Soft portrait',
    FilterType.feminine,
    Icons.face_retouching_natural_outlined,
  ),
  boldPortrait('Bold portrait', FilterType.masculine, Icons.face_6_outlined);

  const QuickStyle(this.label, this.filter, this.icon);

  final String label;
  final FilterType filter;
  final IconData icon;

  bool get isAi => filter.isAi;
}

/// Shown wherever the portrait presets are offered.
const String portraitPresetDisclaimer =
    'Soft portrait and Bold portrait are cosmetic tone and soft-focus '
    'presets. They do not change who is in the photo.';
