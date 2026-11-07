import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../models/filter_type.dart';
import '../../models/gallery_item.dart';
import '../../shared/utils/ui_feedback.dart';
import '../editor/photo_editor_screen.dart';
import '../tracing/tracing_screen.dart';
import 'delete_confirmation.dart';

class ImageDetailScreen extends StatefulWidget {
  const ImageDetailScreen({super.key, required this.item});

  final GalleryItem item;

  @override
  State<ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<ImageDetailScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await confirmDeleteImage(context, widget.item);
    if (!confirmed || !mounted) return;

    final scope = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _deleting = true);
    try {
      await scope.library.delete(widget.item);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Image deleted.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAppSnackBar(context, friendlyError(error));
    }
  }

  void _edit() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoEditorScreen(item: widget.item),
      ),
    );
  }

  void _trace() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TracingScreen(initialReference: widget.item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final imageFile = File(item.imagePath);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          item.title,
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        actions: [
          if (_deleting)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _delete,
              tooltip: 'Delete image',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: 'gallery-image-${item.id}',
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.contain,
                    cacheWidth: 1800,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'This image file is no longer available.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.type.label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: Icons.aspect_ratio_rounded,
                      label: '${item.width} × ${item.height}',
                    ),
                    _MetaChip(
                      icon: Icons.sd_storage_outlined,
                      label: formatBytes(item.byteSize),
                    ),
                    _MetaChip(
                      icon: Icons.calendar_today_outlined,
                      label: formatDate(item.createdAt),
                    ),
                    if (item.filter != null)
                      _MetaChip(
                        icon: item.filter!.icon,
                        label: item.filter!.label,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Edit photo'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _trace,
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('Trace'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
