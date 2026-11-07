import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';

/// Shown under the face transform filters so the permission rule stays visible
/// after the first-use dialog has been accepted.
const String faceTransformReminder =
    'Only transform photos of yourself or people who have given you '
    'permission. AI face transform results are edited and may not preserve '
    'the person’s identity.';

/// Shows the first-use privacy and permission notice for face transform.
Future<bool> askForFaceTransformConsent(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const FaceTransformConsentDialog(),
  );
  return accepted ?? false;
}

/// Returns true when the user may run an online face transform.
///
/// Accepting the dialog enables the feature and stores consent. Declining
/// leaves it off. The caller should show an error when the build has no proxy.
Future<bool> ensureFaceTransformConsent(BuildContext context) async {
  final scope = AppScope.of(context);
  if (!scope.processing.faceTransformConfigured) return false;
  if (scope.processing.faceTransformEnabled &&
      scope.settings.faceTransformConsent) {
    return true;
  }

  final accepted = await askForFaceTransformConsent(context);
  if (accepted) {
    await scope.settings.setFaceTransformConsent(true);
    await scope.settings.setFaceTransformEnabled(true);
  } else {
    await scope.settings.setFaceTransformEnabled(false);
  }
  return accepted;
}

class FaceTransformConsentDialog extends StatefulWidget {
  const FaceTransformConsentDialog({super.key});

  @override
  State<FaceTransformConsentDialog> createState() =>
      _FaceTransformConsentDialogState();
}

class _FaceTransformConsentDialogState
    extends State<FaceTransformConsentDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Use online face transform?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This sends the photo to a hosted AI service that edits the '
              'person’s face. The result comes back to your phone.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 14),
            const _ConsentPoint(
              icon: Icons.cloud_upload_outlined,
              text:
                  'Only the photo you are transforming is uploaded. No account '
                  'or personal details are included.',
            ),
            const _ConsentPoint(
              icon: Icons.lock_outline_rounded,
              text:
                  'Sketchify’s proxy does not keep copies. The hosted model '
                  'provider’s policy applies to its processing.',
            ),
            const _ConsentPoint(
              icon: Icons.face_retouching_natural_outlined,
              text:
                  'AI results can look unrealistic and may not preserve the '
                  'person’s identity. This is not a real gender transition.',
            ),
            const _ConsentPoint(
              icon: Icons.wifi_off_rounded,
              text:
                  'Internet is required. If the service fails, the photo is '
                  'not transformed and no local substitute is used.',
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'I have permission from the person in this photo.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Agree & continue'),
        ),
      ],
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  const _ConsentPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
