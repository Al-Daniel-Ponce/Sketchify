import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/utils/error_utils.dart';
import '../../models/filter_type.dart';
import '../../models/gallery_item.dart';
import '../../services/image_processing_service.dart';
import '../../shared/utils/ui_feedback.dart';
import '../editor/widgets/before_after_preview.dart';
import '../gallery/image_detail_screen.dart';

/// Shows a captured photo next to its filtered result and saves it only when
/// the user asks.
class CameraResultScreen extends StatefulWidget {
  const CameraResultScreen({
    super.key,
    required this.capturedBytes,
    required this.processed,
  });

  final Uint8List capturedBytes;
  final ProcessedImage processed;

  @override
  State<CameraResultScreen> createState() => _CameraResultScreenState();
}

class _CameraResultScreenState extends State<CameraResultScreen> {
  bool _saving = false;
  GalleryItem? _saved;

  Future<void> _save() async {
    if (_saving || _saved != null) return;

    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final processed = widget.processed;

    setState(() => _saving = true);
    try {
      final saved = await scope.library.importBytes(
        processed.bytes,
        type: processed.filter == FilterType.original
            ? GalleryItemType.original
            : GalleryItemType.edited,
        filter: processed.filter,
      );
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _saving = false;
      });
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
      setState(() => _saving = false);
      showAppSnackBar(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processed = widget.processed;
    final filter = processed.filter;
    final isOriginal = filter == FilterType.original;
    final saved = _saved != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOriginal ? 'Your photo' : 'Your ${filter.shortLabel}'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: ColoredBox(
                    color: Colors.black,
                    child: BeforeAfterPreview(
                      active: !isOriginal,
                      before: Image.memory(
                        widget.capturedBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                      after: isOriginal
                          ? const SizedBox.shrink()
                          : Image.memory(
                              processed.bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
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
                          filter.icon,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filter.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              filter.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                            if (filter.isAi) ...[
                              const SizedBox(height: 4),
                              Text(
                                _animeSourceLabel(processed),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: processed.usedAi
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.error,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!isOriginal) ...[
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
                          'Drag across the preview to compare.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retake'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving || saved ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  saved
                                      ? Icons.check_rounded
                                      : Icons.download_done_rounded,
                                ),
                          label: Text(
                            _saving
                                ? 'Saving…'
                                : saved
                                ? 'Saved'
                                : 'Save',
                            maxLines: 1,
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _animeSourceLabel(ProcessedImage processed) {
    if (processed.usedOnline) {
      return 'Rendered by the online anime service'
          '${_elapsedLabel(processed.elapsed)}.';
    }
    if (processed.usedAi) {
      final prefix = processed.remoteFailureReason == null
          ? 'Rendered by AnimeGANv2 on this device'
          : 'Online unavailable — rendered on this device';
      return '$prefix${_elapsedLabel(processed.elapsed)}.';
    }
    return 'Local fallback used — the AI model could not run.';
  }

  String _elapsedLabel(Duration elapsed) {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds < 0.1) return '';
    return ' · ${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
  }
}
