import 'package:flutter/material.dart';

import '../../../models/gallery_item.dart';

Future<bool> confirmDeleteImage(BuildContext context, GalleryItem item) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Delete image?'),
        content: Text(
          '“${item.title}” will be permanently removed from your device. '
          'This cannot be undone.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
