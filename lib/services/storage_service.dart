import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum StorageBucket { images, thumbnails, references }

/// Owns the app's private folder layout and the gallery index file.
class StorageService {
  StorageService._({
    required this.rootDirectory,
    required this.imagesDirectory,
    required this.thumbnailsDirectory,
    required this.referencesDirectory,
    required this.indexFile,
  });

  final Directory rootDirectory;
  final Directory imagesDirectory;
  final Directory thumbnailsDirectory;
  final Directory referencesDirectory;
  final File indexFile;

  static Future<StorageService> create() async {
    final base = await getApplicationDocumentsDirectory();
    return createAt(Directory(p.join(base.path, 'sketchify')));
  }

  /// Builds the storage layout under an explicit directory. Used by tests.
  static Future<StorageService> createAt(Directory root) async {
    final images = Directory(p.join(root.path, 'images'));
    final thumbnails = Directory(p.join(root.path, 'thumbnails'));
    final references = Directory(p.join(root.path, 'references'));

    for (final directory in <Directory>[root, images, thumbnails, references]) {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }

    return StorageService._(
      rootDirectory: root,
      imagesDirectory: images,
      thumbnailsDirectory: thumbnails,
      referencesDirectory: references,
      indexFile: File(p.join(root.path, 'gallery_index.json')),
    );
  }

  Directory directoryFor(StorageBucket bucket) => switch (bucket) {
    StorageBucket.images => imagesDirectory,
    StorageBucket.thumbnails => thumbnailsDirectory,
    StorageBucket.references => referencesDirectory,
  };

  Future<String> writeBytes(
    Uint8List bytes, {
    required StorageBucket bucket,
    required String id,
    required String extension,
  }) async {
    final directory = directoryFor(bucket);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File(p.join(directory.path, '$id.$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> calculateUsage() async {
    var total = 0;
    if (!await rootDirectory.exists()) return total;
    await for (final entity in rootDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clearStoredImages() async {
    for (final directory in <Directory>[
      imagesDirectory,
      thumbnailsDirectory,
      referencesDirectory,
    ]) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await directory.create(recursive: true);
    }
  }

  Future<String?> readIndex() async {
    if (!await indexFile.exists()) return null;
    return indexFile.readAsString();
  }

  Future<void> writeIndex(String contents) async {
    final temp = File('${indexFile.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    try {
      // POSIX rename replaces the destination atomically.
      await temp.rename(indexFile.path);
    } on FileSystemException {
      // Windows does not allow overwriting an existing file with rename.
      if (await indexFile.exists()) {
        await indexFile.delete();
      }
      await temp.rename(indexFile.path);
    }
  }
}
