import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/gallery_item.dart';
import 'storage_service.dart';

/// In-memory gallery backed by an atomically written JSON index.
class GalleryRepository extends ChangeNotifier {
  GalleryRepository({required this.storage});

  final StorageService storage;
  final List<GalleryItem> _items = <GalleryItem>[];
  bool _loaded = false;

  List<GalleryItem> get items => List<GalleryItem>.unmodifiable(_items);
  bool get isLoaded => _loaded;

  List<GalleryItem> get edited => _items
      .where((item) => item.type == GalleryItemType.edited)
      .toList(growable: false);

  List<GalleryItem> get references => _items
      .where((item) => item.type == GalleryItemType.reference)
      .toList(growable: false);

  List<GalleryItem> recent({int limit = 8}) =>
      _items.take(limit).toList(growable: false);

  GalleryItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final raw = await storage.readIndex();
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = <GalleryItem>[];
          for (final entry in decoded) {
            if (entry is Map) {
              final item = GalleryItem.fromJson(
                Map<String, dynamic>.from(entry),
              );
              if (item.id.isNotEmpty && File(item.imagePath).existsSync()) {
                loaded.add(item);
              }
            }
          }
          loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _items
            ..clear()
            ..addAll(loaded);
        }
      }
    } catch (_) {
      // A corrupt index should not prevent the app from starting. Orphaned
      // files, if any, can be cleaned from Settings.
      _items.clear();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> add(GalleryItem item) async {
    _items.removeWhere((existing) => existing.id == item.id);
    _items.insert(0, item);
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> remove(GalleryItem item) async {
    _items.removeWhere((existing) => existing.id == item.id);
    notifyListeners();
    await storage.deleteFile(item.imagePath);
    await storage.deleteFile(item.thumbPath);
    await _persist();
  }

  Future<void> deleteAll() async {
    _items.clear();
    notifyListeners();
    await storage.clearStoredImages();
    await storage.deleteFile(storage.indexFile.path);
    await _persist();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(
      _items.map((item) => item.toJson()).toList(growable: false),
    );
    await storage.writeIndex(encoded);
  }

  void _sort() {
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
