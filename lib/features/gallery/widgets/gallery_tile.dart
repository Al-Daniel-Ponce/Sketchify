import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/filter_type.dart';
import '../../../models/gallery_item.dart';

class GalleryTile extends StatelessWidget {
  const GalleryTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final GalleryItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (item.type) {
      GalleryItemType.reference => 'REFERENCE',
      GalleryItemType.edited =>
        (item.filter?.shortLabel ?? 'EDITED').toUpperCase(),
      GalleryItemType.original => 'ORIGINAL',
    };
    final imagePath = item.thumbPath ?? item.imagePath;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'gallery-image-${item.id}',
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                cacheWidth: 640,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, Color(0xB3000000)],
                  stops: <double>[0.55, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  Flexible(child: _TileBadge(text: label)),
                  const SizedBox(width: 6),
                  if (item.type == GalleryItemType.reference)
                    const _TileBadge(icon: Icons.layers_rounded, text: 'TRACE'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
