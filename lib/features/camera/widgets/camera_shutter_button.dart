import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Large circular shutter used by the snap camera.
class CameraShutterButton extends StatelessWidget {
  const CameraShutterButton({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !busy;
    return Semantics(
      button: true,
      enabled: active,
      label: busy ? 'Processing photo' : 'Take photo',
      child: SizedBox(
        width: 86,
        height: 86,
        child: Material(
          color: Colors.transparent,
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: active ? 0.95 : 0.4),
              width: 4,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: active ? onPressed : null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: active ? 64 : 58,
                height: active ? 64 : 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: active
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            AppColors.primarySoft,
                            AppColors.primaryDeep,
                          ],
                        )
                      : null,
                  color: active ? null : Colors.white.withValues(alpha: 0.32),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
