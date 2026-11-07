import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings_service.dart';

void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
}

Future<void> appHaptic(SettingsService settings, {bool medium = false}) async {
  if (!settings.haptics) return;
  if (medium) {
    await HapticFeedback.mediumImpact();
  } else {
    await HapticFeedback.selectionClick();
  }
}
