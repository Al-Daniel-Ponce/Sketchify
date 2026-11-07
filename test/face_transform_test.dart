import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/models/face_transform.dart';
import 'package:sketchify/models/filter_type.dart';

void main() {
  group('face transform direction', () {
    test('uses stable wire names and labels', () {
      expect(FaceTransformDirection.feminize.wireName, 'feminize');
      expect(FaceTransformDirection.masculinize.wireName, 'masculinize');
      expect(FaceTransformDirection.feminize.label, 'Feminize');
      expect(FaceTransformDirection.masculinize.label, 'Masculinize');
    });
  });

  group('filter flags', () {
    test('maps each face filter to one explicit direction', () {
      expect(
        FilterType.feminizeFace.faceTransformDirection,
        FaceTransformDirection.feminize,
      );
      expect(
        FilterType.masculinizeFace.faceTransformDirection,
        FaceTransformDirection.masculinize,
      );
      for (final filter in FilterType.values) {
        if (filter.isFaceTransform) continue;
        expect(
          filter.faceTransformDirection,
          isNull,
          reason: '${filter.name} is not an AI face transform',
        );
      }
    });

    test('face filters are online-only AI and never portrait presets', () {
      for (final filter in <FilterType>[
        FilterType.feminizeFace,
        FilterType.masculinizeFace,
      ]) {
        expect(filter.isAi, isTrue);
        expect(filter.isFaceTransform, isTrue);
        expect(filter.requiresOnline, isTrue);
        expect(filter.isPortraitPreset, isFalse);
        expect(filter.isProcessed, isTrue);
        expect(filter.icon, isNotNull);
        expect(filter.description, contains('Online AI'));
      }
    });

    test('cosmetic portrait presets stay local and offline', () {
      for (final filter in <FilterType>[
        FilterType.feminine,
        FilterType.masculine,
      ]) {
        expect(filter.isPortraitPreset, isTrue);
        expect(filter.isFaceTransform, isFalse);
        expect(filter.requiresOnline, isFalse);
        expect(filter.isAi, isFalse);
      }
    });

    test('labels distinguish cosmetic looks from the AI transforms', () {
      expect(FilterType.feminine.label, 'Soft Portrait');
      expect(FilterType.masculine.label, 'Bold Portrait');
      expect(FilterType.feminizeFace.label, 'Feminize Face');
      expect(FilterType.masculinizeFace.label, 'Masculinize Face');
      expect(FilterType.feminizeFace.shortLabel, 'Feminize');
      expect(FilterType.masculinizeFace.shortLabel, 'Masculinize');
    });

    test('the camera strip stays offline and keeps Anime', () {
      expect(cameraFilterTypes, <FilterType>[
        FilterType.original,
        FilterType.sketch,
        FilterType.anime,
        FilterType.edges,
      ]);
      for (final filter in cameraFilterTypes) {
        expect(filter.isFaceTransform, isFalse);
        expect(filter.requiresOnline, isFalse);
      }
      expect(cameraFilterTypes.contains(FilterType.anime), isTrue);
    });
  });

  group('filterTypeFromName', () {
    test('reads both face directions and every other filter', () {
      for (final filter in FilterType.values) {
        expect(filterTypeFromName(filter.name), filter);
      }
    });

    test('keeps the legacy Cartoon alias and rejects unknown values', () {
      expect(filterTypeFromName('cartoon'), FilterType.anime);
      expect(filterTypeFromName('not-a-filter'), isNull);
      expect(filterTypeFromName(null), isNull);
    });
  });
}
