import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/utils/error_utils.dart';
import '../../models/filter_type.dart';
import '../../shared/utils/ui_feedback.dart';
import 'widgets/filter_card.dart';

class FilterSelectionScreen extends StatefulWidget {
  const FilterSelectionScreen({
    super.key,
    required this.sourceBytes,
    required this.selected,
  });

  final Uint8List sourceBytes;
  final FilterType selected;

  @override
  State<FilterSelectionScreen> createState() => _FilterSelectionScreenState();
}

class _FilterSelectionScreenState extends State<FilterSelectionScreen> {
  Map<FilterType, Uint8List>? _previews;
  bool _loading = true;
  bool _started = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _generatePreviews();
    }
  }

  Future<void> _generatePreviews() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final previews = await AppScope.of(
        context,
      ).processing.generatePreviews(widget.sourceBytes);
      if (!mounted) return;
      setState(() {
        _previews = previews;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(error);
      });
    }
  }

  void _select(FilterType filter) {
    appHaptic(AppScope.of(context).settings);
    Navigator.of(context).pop(filter);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processing = AppScope.of(context).processing;
    final onlineAnime = processing.onlineAnimeEnabled;
    final faceTransform = processing.faceTransformConfigured;
    final note = faceTransform
        ? (onlineAnime
              ? 'Previews are generated on your device. Anime may use the '
                    'online service; Feminize and Masculinize Face always run '
                    'online.'
              : 'Previews are generated on your device. Anime runs on this '
                    'device; Feminize and Masculinize Face always run online.')
        : (onlineAnime
              ? 'Previews are generated on your device. Anime may use the '
                    'online service; face transform is not configured in this '
                    'build.'
              : 'Previews are generated on your device. Anime runs on this '
                    'device; face transform is not configured in this build.');
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a filter')),
      body: _loading
          ? const _PreparingPreviews()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 17,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Previews could not be generated, but the filters '
                            'will still work.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _generatePreviews,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 720 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.74,
                        ),
                        itemCount: FilterType.values.length,
                        itemBuilder: (context, index) {
                          final filter = FilterType.values[index];
                          return FilterCard(
                            filter: filter,
                            preview: _previews?[filter],
                            fallbackSource: widget.sourceBytes,
                            selected: filter == widget.selected,
                            onTap: () => _select(filter),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _PreparingPreviews extends StatelessWidget {
  const _PreparingPreviews();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              'Preparing live previews…',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Each quick filter is rendered once at a small size. '
              'Anime and face transform run in the editor.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
