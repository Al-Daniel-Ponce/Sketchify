import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/models/filter_type.dart';
import 'package:sketchify/models/quick_style.dart';

void main() {
  test('quick styles are the nine fixed prompt chips', () {
    expect(QuickStyle.values.map((style) => style.label), <String>[
      'Cartoon character',
      'Black & white',
      'Comic book',
      'Pencil drawing',
      'Clean outline',
      'Old photo',
      'Dramatic noir',
      'Soft portrait',
      'Bold portrait',
    ]);
  });

  test('every quick style maps to a real filter', () {
    for (final style in QuickStyle.values) {
      expect(FilterType.values, contains(style.filter));
    }
    expect(QuickStyle.cartoonCharacter.filter, FilterType.anime);
    expect(QuickStyle.blackAndWhite.filter, FilterType.mono);
    expect(QuickStyle.comicBook.filter, FilterType.comic);
    expect(QuickStyle.pencilDrawing.filter, FilterType.sketch);
    expect(QuickStyle.cleanOutline.filter, FilterType.edges);
    expect(QuickStyle.oldPhoto.filter, FilterType.vintage);
    expect(QuickStyle.dramaticNoir.filter, FilterType.noir);
    expect(QuickStyle.softPortrait.filter, FilterType.feminine);
    expect(QuickStyle.boldPortrait.filter, FilterType.masculine);
  });

  test('portrait presets are labelled cosmetic', () {
    expect(FilterType.feminine.isPortraitPreset, isTrue);
    expect(FilterType.masculine.isPortraitPreset, isTrue);
    expect(FilterType.anime.isPortraitPreset, isFalse);
    expect(portraitPresetDisclaimer, contains('cosmetic'));
    expect(portraitPresetDisclaimer, contains('do not change'));
  });

  test('quick styles stay cosmetic and exclude the online face transforms', () {
    for (final style in QuickStyle.values) {
      expect(
        style.filter.isFaceTransform,
        isFalse,
        reason: '${style.label} must stay offline',
      );
      expect(style.filter.requiresOnline, isFalse);
    }
    expect(QuickStyle.softPortrait.filter, FilterType.feminine);
    expect(QuickStyle.boldPortrait.filter, FilterType.masculine);
  });
}
