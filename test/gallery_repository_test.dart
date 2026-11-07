import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/models/filter_type.dart';
import 'package:sketchify/models/gallery_item.dart';
import 'package:sketchify/services/gallery_repository.dart';
import 'package:sketchify/services/storage_service.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sketchify_gallery_');
    storage = await StorageService.createAt(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<GalleryItem> createItem(
    String id, {
    GalleryItemType type = GalleryItemType.original,
    DateTime? createdAt,
  }) async {
    final imagePath = await storage.writeBytes(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      bucket: StorageBucket.images,
      id: id,
      extension: 'jpg',
    );
    final thumbPath = await storage.writeBytes(
      Uint8List.fromList(<int>[5, 6, 7]),
      bucket: StorageBucket.thumbnails,
      id: id,
      extension: 'jpg',
    );
    return GalleryItem(
      id: id,
      imagePath: imagePath,
      thumbPath: thumbPath,
      type: type,
      createdAt: createdAt ?? DateTime.now(),
      width: 40,
      height: 30,
      byteSize: 4,
      filter: type == GalleryItemType.edited ? FilterType.anime : null,
    );
  }

  test('starts empty and marks itself loaded', () async {
    final repository = GalleryRepository(storage: storage);
    expect(repository.isLoaded, isFalse);
    await repository.load();
    expect(repository.isLoaded, isTrue);
    expect(repository.items, isEmpty);
  });

  test('persists items, sorts newest first and reloads them', () async {
    final repository = GalleryRepository(storage: storage);
    await repository.load();

    final older = await createItem(
      'older',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final newer = await createItem(
      'newer',
      type: GalleryItemType.edited,
      createdAt: DateTime.utc(2026, 2, 1),
    );

    await repository.add(older);
    await repository.add(newer);

    expect(repository.items.map((item) => item.id), <String>['newer', 'older']);
    expect(repository.edited.single.id, 'newer');
    expect(repository.references, isEmpty);
    expect(repository.byId('older')?.id, 'older');

    final reloaded = GalleryRepository(storage: storage);
    await reloaded.load();
    expect(reloaded.items.length, 2);
    expect(reloaded.items.first.id, 'newer');
    expect(reloaded.items.first.filter, FilterType.anime);
  });

  test('reference items are grouped separately', () async {
    final repository = GalleryRepository(storage: storage);
    await repository.load();
    await repository.add(
      await createItem('ref', type: GalleryItemType.reference),
    );
    await repository.add(await createItem('orig'));

    expect(repository.references.single.id, 'ref');
    expect(repository.edited, isEmpty);
    expect(repository.items.length, 2);
  });

  test('remove deletes the image, thumbnail and index entry', () async {
    final repository = GalleryRepository(storage: storage);
    await repository.load();
    final item = await createItem('delete-me');
    await repository.add(item);

    await repository.remove(item);

    expect(repository.items, isEmpty);
    expect(File(item.imagePath).existsSync(), isFalse);
    expect(File(item.thumbPath!).existsSync(), isFalse);

    final reloaded = GalleryRepository(storage: storage);
    await reloaded.load();
    expect(reloaded.items, isEmpty);
  });

  test('deleteAll clears files and the index', () async {
    final repository = GalleryRepository(storage: storage);
    await repository.load();
    final item = await createItem('one');
    await repository.add(item);

    await repository.deleteAll();

    expect(repository.items, isEmpty);
    expect(File(item.imagePath).existsSync(), isFalse);
    expect(await storage.imagesDirectory.list().toList(), isEmpty);
    // The index is rewritten empty so a restart starts clean.
    expect(await storage.indexFile.exists(), isTrue);
  });

  test('a corrupt index does not prevent loading', () async {
    await storage.indexFile.writeAsString('{not valid json');
    final repository = GalleryRepository(storage: storage);

    await repository.load();

    expect(repository.isLoaded, isTrue);
    expect(repository.items, isEmpty);
  });

  test('missing image files are dropped on load', () async {
    final repository = GalleryRepository(storage: storage);
    await repository.load();
    final item = await createItem('ghost');
    await repository.add(item);
    await File(item.imagePath).delete();

    final reloaded = GalleryRepository(storage: storage);
    await reloaded.load();

    expect(reloaded.items, isEmpty);
  });

  test('calculates storage usage', () async {
    await storage.writeBytes(
      Uint8List.fromList(List<int>.filled(128, 0)),
      bucket: StorageBucket.images,
      id: 'usage',
      extension: 'jpg',
    );
    expect(await storage.calculateUsage(), 128);
  });
}
