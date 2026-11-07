import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/filter_type.dart';

class FilterCard extends StatelessWidget {
  const FilterCard({
    super.key,
    required this.filter,
    required this.preview,
    required this.fallbackSource,
    required this.selected,
    required this.onTap,
  });

  final FilterType filter;
  final Uint8List? preview;
  final Uint8List fallbackSource;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentFor(filter);
    final isAi = filter.isAi;
    final isFaceTransform = filter.isFaceTransform;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
                    if (preview != null)
                      Image.memory(
                        preview!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      )
                    else
                      Opacity(
                        opacity: 0.32,
                        child: Image.memory(
                          fallbackSource,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                    if (preview == null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            filter.icon,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.transparent,
                              accent.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    if (isAi)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Semantics(
                          label: isFaceTransform
                              ? 'Online AI filter'
                              : 'AI filter',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isFaceTransform
                                      ? Icons.cloud_outlined
                                      : Icons.auto_awesome_rounded,
                                  size: 12,
                                  color: accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isFaceTransform ? 'ONLINE AI' : 'AI',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(filter.icon, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            filter.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      filter.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentFor(FilterType type) => switch (type) {
    FilterType.original => AppColors.textSecondary,
    FilterType.anime => AppColors.primary,
    FilterType.sketch => const Color(0xFFB8C4D9),
    FilterType.edges => AppColors.secondary,
    FilterType.mono => const Color(0xFFD7DEE8),
    FilterType.noir => const Color(0xFF8E9AAB),
    FilterType.comic => const Color(0xFFFFB74D),
    FilterType.vintage => const Color(0xFFD2A679),
    FilterType.poster => const Color(0xFF7ED6C4),
    FilterType.feminine => const Color(0xFFE8A7B8),
    FilterType.masculine => const Color(0xFF7FA7D9),
    FilterType.feminizeFace => const Color(0xFFF2A7C3),
    FilterType.masculinizeFace => const Color(0xFF7FB3E8),
  };
}
