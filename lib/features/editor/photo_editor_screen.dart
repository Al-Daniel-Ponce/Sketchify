import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/utils/error_utils.dart';
import '../../shared/utils/ui_feedback.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../models/filter_type.dart';
import '../../models/gallery_item.dart';
import '../../services/image_processing_service.dart';
import '../filters/filter_selection_screen.dart';
import '../gallery/image_detail_screen.dart';
import '../settings/widgets/face_transform_consent.dart';
import '../settings/widgets/online_anime_consent.dart';
import 'widgets/before_after_preview.dart';
import 'widgets/quick_styles_sheet.dart';

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.item});

  final GalleryItem item;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  Uint8List? _sourceBytes;
  final Map<FilterType, ProcessedImage> _cache = <FilterType, ProcessedImage>{};
  FilterType _selected = FilterType.original;
  ProcessedImage? _processed;

  bool _loadingSource = true;
  bool _processing = false;
  bool _saving = false;
  String _processingLabel = 'Applying filter…';
  String? _loadError;
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  Future<void> _loadSource() async {
    setState(() {
      _loadingSource = true;
      _loadError = null;
    });
    try {
      final bytes = await File(widget.item.imagePath).readAsBytes();
      if (!mounted) return;
      setState(() {
        _sourceBytes = bytes;
        _loadingSource = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(error);
        _loadingSource = false;
      });
    }
  }

  Future<void> _openFilterPicker() async {
    final source = _sourceBytes;
    if (source == null) return;
    final choice = await Navigator.of(context).push<FilterType>(
      MaterialPageRoute<FilterType>(
        builder: (_) =>
            FilterSelectionScreen(sourceBytes: source, selected: _selected),
      ),
    );
    if (!mounted || choice == null || choice == _selected) return;
    await _applyFilter(choice);
  }

  Future<void> _openQuickStyles() async {
    final source = _sourceBytes;
    if (source == null || _processing) return;
    final choice = await showQuickStylesSheet(context, selected: _selected);
    if (!mounted || choice == null || choice.filter == _selected) return;
    await appHaptic(AppScope.of(context).settings);
    if (!mounted) return;
    await _applyFilter(choice.filter);
  }

  Future<void> _applyFilter(FilterType filter) async {
    final source = _sourceBytes;
    if (source == null || _processing) return;

    if (filter == FilterType.original) {
      setState(() {
        _selected = filter;
        _processed = null;
      });
      return;
    }

    final cached = _cache[filter];
    if (cached != null) {
      setState(() {
        _selected = filter;
        _processed = cached;
      });
      return;
    }

    final scope = AppScope.of(context);
    if (filter.isFaceTransform) {
      if (!scope.processing.faceTransformConfigured) {
        showAppSnackBar(
          context,
          'Online face transform is not configured in this build.',
        );
        return;
      }
      final allowed = await ensureFaceTransformConsent(context);
      if (!allowed || !mounted) return;
    } else if (filter.isAi) {
      // Declining the notice disables online anime, so processing simply
      // continues with the on-device model.
      await ensureOnlineAnimeConsent(context);
      if (!mounted) return;
    }

    final previousFilter = _selected;
    final previousProcessed = _processed;
    final token = ++_requestToken;
    final onlineAnime =
        filter.isAi &&
        !filter.isFaceTransform &&
        scope.processing.onlineAnimeEnabled;

    setState(() {
      _selected = filter;
      _processing = true;
      _processingLabel = filter.isFaceTransform
          ? 'Transforming the face…'
          : filter.isAi
          ? (onlineAnime
                ? 'Sending your photo to online anime…'
                : 'Painting the anime scene…')
          : 'Applying ${filter.label}…';
    });

    try {
      final result = await scope.processing.process(
        source,
        filter,
        maxDimension: scope.settings.processingQuality.maxDimension,
      );
      if (!mounted || token != _requestToken) return;
      _cache[filter] = result;
      setState(() {
        _processed = result;
        _processing = false;
      });
      if (filter.isAi && !filter.isFaceTransform) {
        if (!result.usedAi) {
          showAppSnackBar(
            context,
            'The AI model could not run, so a local anime fallback was used.',
          );
        } else if (result.remoteFailureReason != null) {
          showAppSnackBar(
            context,
            'Online anime was unavailable — rendered on this device.',
          );
        }
      }
    } catch (error) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _selected = previousFilter;
        _processed = previousProcessed;
        _processing = false;
      });
      showAppSnackBar(context, friendlyError(error));
    }
  }

  Future<void> _save() async {
    final processed = _processed;
    if (processed == null || _saving || _processing) return;

    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _saving = true);
    try {
      final saved = await scope.library.importBytes(
        processed.bytes,
        type: GalleryItemType.edited,
        filter: processed.filter,
        sourceId: widget.item.id,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Saved to your gallery.'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImageDetailScreen(item: saved),
                  ),
                );
              },
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _animeSourceLabel(ProcessedImage processed) {
    if (processed.usedOnline) {
      return 'Rendered by the online anime service.';
    }
    if (processed.usedAi) {
      return processed.remoteFailureReason == null
          ? 'Rendered by AnimeGANv2 on this device.'
          : 'Online unavailable — rendered on this device.';
    }
    return 'Local fallback — AI unavailable.';
  }

  String _faceTransformSourceLabel() =>
      'Rendered by the online face transform service.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onlineAnime = AppScope.of(context).processing.onlineAnimeEnabled;
    final canSave = _processed != null && !_processing && !_saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Editor'),
        actions: [
          IconButton(
            onPressed: canSave ? _save : null,
            tooltip: 'Save to gallery',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loadingSource
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? ErrorView(
              title: 'Could not open this photo',
              message: _loadError!,
              onRetry: _loadSource,
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: LoadingOverlay(
                        visible: _processing,
                        message: _processingLabel,
                        detail: _selected.isFaceTransform
                            ? 'The online AI model is editing the face. '
                                  'This can take up to a minute.'
                            : _selected.isAi
                            ? (onlineAnime
                                  ? 'Online anime sends this photo to a hosted '
                                        'service. If it fails, the on-device '
                                        'model takes over.'
                                  : 'AnimeGANv2 runs fully on this device. '
                                        'The first pass can take up to a minute.')
                            : null,
                        child: BeforeAfterPreview(
                          active: _processed != null,
                          before: Image.file(
                            File(widget.item.imagePath),
                            fit: BoxFit.contain,
                            cacheWidth: 1800,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          after: _processed == null
                              ? const SizedBox.shrink()
                              : Image.memory(
                                  _processed!.bytes,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.medium,
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
                      top: Radius.circular(26),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    14 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              _selected.icon,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selected.label,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selected.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                                if (_selected.isPortraitPreset) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Cosmetic tone preset — not a gender '
                                    'transformation.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                if (_selected.isFaceTransform) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    faceTransformReminder,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                if (_selected.isAi &&
                                    !_selected.isFaceTransform &&
                                    _processed != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    _animeSourceLabel(_processed!),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _processed!.usedAi
                                          ? theme.colorScheme.onSurfaceVariant
                                          : theme.colorScheme.error,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                if (_selected.isFaceTransform &&
                                    _processed != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    _faceTransformSourceLabel(),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_processed != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.swipe_rounded,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Drag across the preview to compare with the original.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _processing ? null : _openQuickStyles,
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                              ),
                              label: const Text('Quick styles'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _processing ? null : _openFilterPicker,
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: const Text('All filters'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: canSave ? _save : null,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_done_rounded),
                          label: Text(
                            _saving
                                ? 'Saving…'
                                : canSave
                                ? 'Save to gallery'
                                : _selected == FilterType.original
                                ? 'Choose a filter to save'
                                : 'Preparing filter…',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
