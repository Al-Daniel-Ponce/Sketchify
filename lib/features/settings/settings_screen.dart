import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/format_utils.dart';
import '../../models/level_reading.dart';
import '../../services/settings_service.dart';
import '../../shared/utils/ui_feedback.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'widgets/face_transform_consent.dart';
import 'widgets/online_anime_consent.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _usage;
  bool _busy = false;
  bool _usageRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_usageRequested) {
      _usageRequested = true;
      _refreshUsage();
    }
  }

  Future<void> _refreshUsage() async {
    final usage = await AppScope.of(context).storage.calculateUsage();
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  )
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteAllImages() async {
    final confirmed = await _confirm(
      title: 'Delete all saved images?',
      message:
          'Every original, edit and tracing reference stored by Sketchify '
          'will be removed from this device.',
      action: 'Delete all',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await scope.gallery.deleteAll();
      await _refreshUsage();
      if (!mounted) return;
      showAppSnackBar(context, 'All saved images were deleted.');
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, 'Could not delete the images. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetSettings() async {
    final confirmed = await _confirm(
      title: 'Reset preferences?',
      message:
          'Theme, default opacity, level sensitivity, processing quality, '
          'online anime and online face transform will return to their '
          'defaults. Saved images are not affected.',
      action: 'Reset',
    );
    if (!confirmed || !mounted) return;
    await AppScope.of(context).settings.reset();
    if (!mounted) return;
    showAppSnackBar(context, 'Preferences reset.');
  }

  Future<void> _resetCalibration() async {
    await AppScope.of(context).sensors.resetCalibration();
    if (!mounted) return;
    showAppSnackBar(context, 'Level calibration cleared.');
  }

  Future<void> _setOnlineAnime(bool value) async {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    await appHaptic(settings);
    if (!mounted) return;

    if (!value) {
      await settings.setOnlineAnimeEnabled(false);
      return;
    }

    final accepted = await askForOnlineAnimeConsent(context);
    if (!accepted || !mounted) return;
    await settings.setOnlineAnimeConsent(true);
    await settings.setOnlineAnimeEnabled(true);
    if (!mounted) return;
    showAppSnackBar(
      context,
      'Online anime is on. Anime will try the hosted service first.',
    );
  }

  Future<void> _clearCalibrationAndShowInfo() async {
    await _resetCalibration();
  }

  Future<void> _setFaceTransform(bool value) async {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    await appHaptic(settings);
    if (!mounted) return;

    if (!value) {
      await settings.setFaceTransformEnabled(false);
      return;
    }

    final accepted = await askForFaceTransformConsent(context);
    if (!accepted || !mounted) return;
    await settings.setFaceTransformConsent(true);
    await settings.setFaceTransformEnabled(true);
    if (!mounted) return;
    showAppSnackBar(
      context,
      'Online face transform is on. Only use photos you have permission to '
      'edit.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: LoadingOverlay(
        visible: _busy,
        message: 'Updating your studio…',
        child: AnimatedBuilder(
          animation: scope.settings,
          builder: (context, _) {
            final settings = scope.settings;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
              children: [
                _SettingsSection(
                  title: 'Appearance',
                  subtitle: 'Choose how the studio looks.',
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        expandedInsets: EdgeInsets.zero,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                          ),
                        ],
                        selected: <ThemeMode>{settings.themeMode},
                        onSelectionChanged: (selection) {
                          appHaptic(settings);
                          settings.setThemeMode(selection.first);
                        },
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Tracing',
                  subtitle: 'Defaults for the camera tracing screen.',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Default overlay opacity',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${(settings.defaultOpacity * 100).round()}%',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: settings.defaultOpacity,
                      divisions: 20,
                      label: '${(settings.defaultOpacity * 100).round()}%',
                      onChanged: (value) => settings.setDefaultOpacity(value),
                    ),
                    _SwitchRow(
                      icon: Icons.brightness_high_outlined,
                      title: 'Keep screen awake',
                      subtitle: 'Stops the display dimming while you trace.',
                      value: settings.keepScreenAwake,
                      onChanged: settings.setKeepScreenAwake,
                    ),
                    const Divider(),
                    Text(
                      'Smart level sensitivity',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Green within ${settings.levelSensitivity.thresholds.goodMax.toStringAsFixed(0)}°, '
                      'red above ${settings.levelSensitivity.thresholds.warningMax.toStringAsFixed(0)}°.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final sensitivity in LevelSensitivity.values)
                      _ChoiceTile(
                        title: sensitivity.label,
                        subtitle: sensitivity.description,
                        selected: settings.levelSensitivity == sensitivity,
                        onTap: () {
                          appHaptic(settings);
                          settings.setLevelSensitivity(sensitivity);
                        },
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearCalibrationAndShowInfo,
                        icon: const Icon(Icons.center_focus_weak_rounded),
                        label: const Text('Reset level calibration'),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Image processing',
                  subtitle: 'Higher detail takes a little longer.',
                  children: [
                    for (final quality in ProcessingQuality.values)
                      _ChoiceTile(
                        title: quality.label,
                        subtitle: quality.detail,
                        selected: settings.processingQuality == quality,
                        onTap: () {
                          appHaptic(settings);
                          settings.setProcessingQuality(quality);
                        },
                      ),
                    const Divider(),
                    _SwitchRow(
                      icon: Icons.cloud_outlined,
                      title: 'Online anime (optional)',
                      subtitle: scope.processing.onlineAnimeConfigured
                          ? 'Send Anime photos to a hosted AI service. Falls '
                                'back to the on-device model.'
                          : 'Not configured in this build. Anime stays '
                                'on-device.',
                      value:
                          settings.onlineAnimeEnabled &&
                          scope.processing.onlineAnimeConfigured,
                      enabled: scope.processing.onlineAnimeConfigured,
                      onChanged: _setOnlineAnime,
                    ),
                    const SizedBox(height: 4),
                    _SwitchRow(
                      icon: Icons.face_retouching_natural_outlined,
                      title: 'Online face transform (optional)',
                      subtitle: scope.processing.faceTransformConfigured
                          ? 'Feminize or masculinize the person with a hosted '
                                'AI model. No on-device fallback.'
                          : 'Not configured in this build. Face transform '
                                'stays unavailable.',
                      value:
                          settings.faceTransformEnabled &&
                          scope.processing.faceTransformConfigured,
                      enabled: scope.processing.faceTransformConfigured,
                      onChanged: _setFaceTransform,
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Storage',
                  subtitle:
                      'Everything stays inside Sketchify’s private app folder.',
                  children: [
                    _InfoRow(
                      icon: Icons.folder_outlined,
                      label: 'Saved images and references',
                      value: _usage == null
                          ? 'Calculating…'
                          : formatBytes(_usage!),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _deleteAllImages,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Delete all saved images'),
                      ),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'About',
                  children: [
                    _InfoRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Version',
                      value: AppConstants.version,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.shield_outlined,
                      label: 'Privacy',
                      value: 'On-device by default',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Sketchify processes photos locally by default, including '
                      'the anime AI model. If you turn on online anime, only '
                      'the photo you are styling is sent to the configured '
                      'hosted service. If you turn on online face transform, '
                      'the photo is sent to the same service for face editing '
                      'after you confirm you have permission. No account is '
                      'required and Sketchify does not keep server copies. '
                      'The hosted provider’s policy applies.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: AppConstants.appName,
                          applicationVersion: AppConstants.version,
                          applicationLegalese:
                              'Offline by default. Optional online AI features '
                              'upload only the selected photo.',
                        ),
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('Open source licenses'),
                      ),
                    ),
                  ],
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: _resetSettings,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset preferences'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: enabled
                ? theme.colorScheme.onSurfaceVariant
                : theme.disabledColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled ? null : theme.disabledColor,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 19,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 11),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
