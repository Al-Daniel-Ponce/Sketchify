import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/filter_type.dart';

/// Horizontal filter picker shown over the camera viewfinder.
class CameraFilterStrip extends StatelessWidget {
  const CameraFilterStrip({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final FilterType selected;
  final ValueChanged<FilterType> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cameraFilterTypes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = cameraFilterTypes[index];
          return _FilterChip(
            filter: filter,
            selected: filter == selected,
            enabled: enabled,
            onTap: () => onSelected(filter),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FilterType filter;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.ink : Colors.white;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: filter.isAi
          ? '${filter.label} filter, AI powered'
          : '${filter.label} filter',
      child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled ? 1 : 0.45,
            child: Container(
              width: 76,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(filter.icon, size: 21, color: foreground),
                  const SizedBox(height: 5),
                  Text(
                    filter.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (filter.isAi) ...[
                    const SizedBox(height: 2),
                    Text(
                      'AI',
                      style: TextStyle(
                        color: selected
                            ? AppColors.secondary
                            : AppColors.accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ] else
                    const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
