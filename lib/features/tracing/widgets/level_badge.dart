import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/level_reading.dart';

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.reading, this.onTap});

  final LevelReading reading;
  final VoidCallback? onTap;

  Color get _color => switch (reading.status) {
    LevelStatus.good => AppColors.success,
    LevelStatus.warning => AppColors.warning,
    LevelStatus.tilted => AppColors.danger,
    LevelStatus.unavailable => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Semantics(
      label: reading.semanticsLabel,
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withValues(alpha: 0.7),
                width: 1.4,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: color.withValues(alpha: 0.7),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      reading.angleText,
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reading.statusLabel.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
