import 'dart:io';
import 'dart:typed_data';

import '../core/utils/id_utils.dart';
import '../models/filter_type.dart';
import '../models/gallery_item.dart';
import 'gallery_repository.dart';
import 'image_picker_service.dart';
import 'image_processing_service.dart';
import 'storage_service.dart';

/// Coordinates picking, copying, thumbnailing and indexing imported images.
class LibraryService {
  LibraryService({
    required this.picker,
    required this.processing,
    required this.gallery,
    required this.storage,
  });

  final ImagePickerService picker;
  final ImageProcessingService processing;
  final GalleryRepository gallery;
  final StorageService storage;

  Future<GalleryItem?> pickAndImport({required GalleryItemType type}) async {
    final picked = await picker.pickFromGallery();
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return importBytes(bytes, type: type);
  }

  Future<GalleryItem> importBytes(
    Uint8List bytes, {
    required GalleryItemType type,
    FilterType? filter,
    String? sourceId,
    Uint8List? thumbnail,
  }) async {
    if (bytes.isEmpty) {
      throw ImageProcessingException('The selected file is empty.');
    }

    final dimensions = await processing.probe(bytes);
    final thumbBytes = thumbnail ?? await processing.makeThumbnail(bytes);
    final id = newId();
    final extension = _extensionFor(bytes);
    final bucket = type == GalleryItemType.reference
        ? StorageBucket.references
        : StorageBucket.images;

    String? imagePath;
    String? thumbPath;
    try {
      imagePath = await storage.writeBytes(
        bytes,
        bucket: bucket,
        id: id,
        extension: extension,
      );
      thumbPath = await storage.writeBytes(
        thumbBytes,
        bucket: StorageBucket.thumbnails,
        id: id,
        extension: 'jpg',
      );

      final item = GalleryItem(
        id: id,
        imagePath: imagePath,
        thumbPath: thumbPath,
        type: type,
        createdAt: DateTime.now(),
        width: dimensions.width,
        height: dimensions.height,
        byteSize: bytes.length,
        filter: filter,
        sourceId: sourceId,
      );
      await gallery.add(item);
      return item;
    } catch (_) {
      await storage.deleteFile(imagePath);
      await storage.deleteFile(thumbPath);
      rethrow;
    }
  }

  Future<void> delete(GalleryItem item) => gallery.remove(item);

  static String _extensionFor(Uint8List bytes) {
    if (bytes.length < 12) return 'jpg';
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    final boxType = String.fromCharCodes(bytes.sublist(4, 12));
    if (boxType.contains('ftyp')) return 'heic';
    return 'jpg';
  }
}

/// Convenience used by the gallery detail screen.
Future<int> fileSizeOf(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return file.length();
}
