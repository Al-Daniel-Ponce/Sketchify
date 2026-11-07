import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'filter_type.dart';

enum GalleryItemType { original, edited, reference }

extension GalleryItemTypeX on GalleryItemType {
  String get label => switch (this) {
    GalleryItemType.original => 'Original',
    GalleryItemType.edited => 'Edited',
    GalleryItemType.reference => 'Reference',
  };

  IconData get icon => switch (this) {
    GalleryItemType.original => Icons.photo_outlined,
    GalleryItemType.edited => Icons.auto_fix_high_outlined,
    GalleryItemType.reference => Icons.layers_outlined,
  };
}

/// A locally stored image tracked in the Sketchify gallery index.
class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.imagePath,
    required this.thumbPath,
    required this.type,
    required this.createdAt,
    required this.width,
    required this.height,
    required this.byteSize,
    this.filter,
    this.sourceId,
  });

  final String id;
  final String imagePath;
  final String? thumbPath;
  final GalleryItemType type;
  final DateTime createdAt;
  final int width;
  final int height;
  final int byteSize;
  final FilterType? filter;

  /// Id of the image this item was created from, when applicable.
  final String? sourceId;

  String get fileName => p.basename(imagePath);

  String get title => switch (type) {
    GalleryItemType.reference => 'Tracing reference',
    GalleryItemType.edited => filter?.label ?? 'Edited photo',
    GalleryItemType.original => 'Original photo',
  };

  String get subtitle => switch (type) {
    GalleryItemType.reference => 'Used for tracing',
    GalleryItemType.edited => 'Sketchify edit',
    GalleryItemType.original => 'Imported photo',
  };

  double get aspectRatio => height == 0 ? 1 : width / height;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'imagePath': imagePath,
    'thumbPath': thumbPath,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
    'width': width,
    'height': height,
    'byteSize': byteSize,
    'filter': filter?.name,
    'sourceId': sourceId,
  };

  factory GalleryItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final type = GalleryItemType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => GalleryItemType.original,
    );
    return GalleryItem(
      id: json['id'] as String? ?? '',
      imagePath: json['imagePath'] as String? ?? '',
      thumbPath: json['thumbPath'] as String?,
      type: type,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
      filter: filterTypeFromName(json['filter'] as String?),
      sourceId: json['sourceId'] as String?,
    );
  }

  GalleryItem copyWith({
    String? imagePath,
    String? thumbPath,
    GalleryItemType? type,
    DateTime? createdAt,
    int? width,
    int? height,
    int? byteSize,
    FilterType? filter,
    String? sourceId,
  }) {
    return GalleryItem(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      thumbPath: thumbPath ?? this.thumbPath,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      width: width ?? this.width,
      height: height ?? this.height,
      byteSize: byteSize ?? this.byteSize,
      filter: filter ?? this.filter,
      sourceId: sourceId ?? this.sourceId,
    );
  }
}
