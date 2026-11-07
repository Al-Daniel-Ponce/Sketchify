import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/models/filter_type.dart';
import 'package:sketchify/models/gallery_item.dart';

void main() {
  group('GalleryItem JSON', () {
    test('round-trips every field', () {
      final createdAt = DateTime.utc(2026, 3, 4, 12, 30, 15);
      final item = GalleryItem(
        id: 'abc-123',
        imagePath: '/tmp/images/abc.jpg',
        thumbPath: '/tmp/thumbs/abc.jpg',
        type: GalleryItemType.edited,
        createdAt: createdAt,
        width: 1600,
        height: 1200,
        byteSize: 245000,
        filter: FilterType.anime,
        sourceId: 'parent-1',
      );

      final restored = GalleryItem.fromJson(item.toJson());

      expect(restored.id, item.id);
      expect(restored.imagePath, item.imagePath);
      expect(restored.thumbPath, item.thumbPath);
      expect(restored.type, GalleryItemType.edited);
      expect(restored.createdAt.isAtSameMomentAs(createdAt), isTrue);
      expect(restored.width, 1600);
      expect(restored.height, 1200);
      expect(restored.byteSize, 245000);
      expect(restored.filter, FilterType.anime);
      expect(restored.sourceId, 'parent-1');
    });

    test('handles a null thumbnail, filter and source', () {
      final item = GalleryItem(
        id: 'x',
        imagePath: '/tmp/x.jpg',
        thumbPath: null,
        type: GalleryItemType.original,
        createdAt: DateTime.utc(2026),
        width: 10,
        height: 20,
        byteSize: 100,
      );

      final restored = GalleryItem.fromJson(item.toJson());
      expect(restored.thumbPath, isNull);
      expect(restored.filter, isNull);
      expect(restored.sourceId, isNull);
    });

    test('falls back safely when fields are missing or unknown', () {
      final restored = GalleryItem.fromJson(<String, dynamic>{
        'id': 'only-id',
        'type': 'not-a-real-type',
        'filter': 'not-a-real-filter',
        'createdAt': 'not-a-date',
      });

      expect(restored.id, 'only-id');
      expect(restored.type, GalleryItemType.original);
      expect(restored.filter, isNull);
      expect(restored.imagePath, '');
      expect(restored.width, 0);
      expect(restored.height, 0);
      expect(restored.byteSize, 0);
      expect(restored.createdAt, isA<DateTime>());
    });

    test('describes items for the gallery UI', () {
      final reference = GalleryItem(
        id: 'r',
        imagePath: '/tmp/ref.png',
        thumbPath: null,
        type: GalleryItemType.reference,
        createdAt: DateTime.utc(2026),
        width: 100,
        height: 200,
        byteSize: 10,
      );
      expect(reference.title, 'Tracing reference');
      expect(reference.subtitle, 'Used for tracing');
      expect(reference.aspectRatio, 0.5);
      expect(reference.fileName, 'ref.png');

      final edited = reference.copyWith(
        type: GalleryItemType.edited,
        filter: FilterType.sketch,
      );
      expect(edited.title, 'Pencil Sketch');
      expect(edited.subtitle, 'Sketchify edit');
    });

    test('filter names map to the enum, including legacy cartoon', () {
      expect(filterTypeFromName('cartoon'), FilterType.anime);
      expect(filterTypeFromName('anime'), FilterType.anime);
      expect(filterTypeFromName('edges'), FilterType.edges);
      expect(filterTypeFromName('sketch'), FilterType.sketch);
      expect(filterTypeFromName('original'), FilterType.original);
      expect(filterTypeFromName('nope'), isNull);
      expect(filterTypeFromName(null), isNull);
    });
  });
}
