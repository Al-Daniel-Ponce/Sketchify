import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../models/gallery_item.dart';
import '../../shared/utils/ui_feedback.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'delete_confirmation.dart';
import 'image_detail_screen.dart';
import 'widgets/gallery_tile.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _importPhoto() async {
    if (_busy) return;
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final item = await scope.library.pickAndImport(
        type: GalleryItemType.original,
      );
      if (!mounted) return;
      if (item != null) {
        showAppSnackBar(context, 'Photo added to your gallery.');
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(GalleryItem item) async {
    final confirmed = await confirmDeleteImage(context, item);
    if (!confirmed || !mounted) return;

    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await scope.library.delete(item);
      if (!mounted) return;
      showAppSnackBar(context, 'Image deleted.');
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDetail(GalleryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ImageDetailScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _importPhoto,
            tooltip: 'Import photo',
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: LoadingOverlay(
        visible: _busy,
        message: 'Working on your gallery…',
        child: AnimatedBuilder(
          animation: scope.gallery,
          builder: (context, _) {
            final all = scope.gallery.items;
            final edited = scope.gallery.edited;
            final references = scope.gallery.references;
            final totalBytes = all.fold<int>(
              0,
              (sum, item) => sum + item.byteSize,
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Row(
                    children: [
                      _StatChip(
                        icon: Icons.collections_outlined,
                        label: formatCount(all.length, 'image'),
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.auto_fix_high_outlined,
                        label: '${edited.length} edited',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.layers_outlined,
                        label: '${references.length} refs',
                      ),
                      const Spacer(),
                      Text(
                        formatBytes(totalBytes),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: theme.colorScheme.onPrimary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    labelStyle: theme.textTheme.labelLarge,
                    indicator: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    splashBorderRadius: BorderRadius.circular(14),
                    overlayColor: WidgetStatePropertyAll(
                      theme.colorScheme.primary.withValues(alpha: 0.08),
                    ),
                    tabs: const [
                      Tab(height: 40, text: 'All'),
                      Tab(height: 40, text: 'Edited'),
                      Tab(height: 40, text: 'References'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _GalleryGrid(
                        items: all,
                        emptyTitle: 'No images yet',
                        emptyMessage:
                            'Import a photo or save a filter result to see it here.',
                        emptyIcon: Icons.photo_library_outlined,
                        onTap: _openDetail,
                        onDelete: _delete,
                        onImport: _importPhoto,
                      ),
                      _GalleryGrid(
                        items: edited,
                        emptyTitle: 'No edits yet',
                        emptyMessage:
                            'Open the photo editor, choose a filter and save your result.',
                        emptyIcon: Icons.auto_fix_high_outlined,
                        onTap: _openDetail,
                        onDelete: _delete,
                      ),
                      _GalleryGrid(
                        items: references,
                        emptyTitle: 'No references yet',
                        emptyMessage:
                            'Pick a tracing reference in Camera Tracing and it will be kept here.',
                        emptyIcon: Icons.layers_outlined,
                        onTap: _openDetail,
                        onDelete: _delete,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({
    required this.items,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onTap,
    required this.onDelete,
    this.onImport,
  });

  final List<GalleryItem> items;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final ValueChanged<GalleryItem> onTap;
  final ValueChanged<GalleryItem> onDelete;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
            action: onImport == null
                ? null
                : FilledButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Import photo'),
                  ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 5
            : constraints.maxWidth >= 520
            ? 4
            : 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return GalleryTile(
              item: item,
              onTap: () => onTap(item),
              onLongPress: () => onDelete(item),
            );
          },
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
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
