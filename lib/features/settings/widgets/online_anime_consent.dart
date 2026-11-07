import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';

/// Shows the first-use privacy notice for the hosted anime service.
Future<bool> askForOnlineAnimeConsent(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Use online anime?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Online anime can render faces more accurately than the '
                'on-device model. When you choose Anime, the photo is sent to '
                'a hosted AI service and the result comes back to your phone.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 14),
              const _ConsentPoint(
                icon: Icons.cloud_upload_outlined,
                text:
                    'Only the photo you are styling is uploaded. No account '
                    'or personal details are included.',
              ),
              const _ConsentPoint(
                icon: Icons.lock_outline_rounded,
                text:
                    'The service processes the image to create the result. '
                    'Sketchify does not keep copies on the server.',
              ),
              const _ConsentPoint(
                icon: Icons.wifi_off_rounded,
                text:
                    'Internet is required. If the service fails or is '
                    'offline, Sketchify falls back to the on-device model.',
              ),
              const _ConsentPoint(
                icon: Icons.tune_rounded,
                text: 'You can turn online anime off at any time in Settings.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Agree & continue'),
          ),
        ],
      );
    },
  );
  return accepted ?? false;
}

/// Returns true when processing may use the online service. Declining the
/// first-use notice disables online anime for this and future sessions.
Future<bool> ensureOnlineAnimeConsent(BuildContext context) async {
  final scope = AppScope.of(context);
  if (!scope.processing.onlineAnimeEnabled) return true;
  if (scope.settings.onlineAnimeConsent) return true;

  final accepted = await askForOnlineAnimeConsent(context);
  if (accepted) {
    await scope.settings.setOnlineAnimeConsent(true);
  } else {
    await scope.settings.setOnlineAnimeEnabled(false);
  }
  return accepted;
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
