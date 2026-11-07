import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/format_utils.dart';
import '../../models/filter_type.dart';
import '../../models/gallery_item.dart';
import '../../shared/utils/ui_feedback.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/section_header.dart';
import '../camera/camera_capture_screen.dart';
import '../editor/photo_editor_screen.dart';
import '../gallery/gallery_screen.dart';
import '../gallery/image_detail_screen.dart';
import '../settings/settings_screen.dart';
import '../tracing/tracing_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  String _busyLabel = '';

  Future<void> _openEditor() async {
    if (_busy) return;
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _busy = true;
      _busyLabel = 'Opening your photo…';
    });

    try {
      final item = await scope.library.pickAndImport(
        type: GalleryItemType.original,
      );
      if (!mounted) return;
      if (item != null) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoEditorScreen(item: item),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openTracing() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TracingScreen()));
  }

  void _openCamera() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CameraCaptureScreen()),
    );
  }

  void _openGallery() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen()));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.of(context);

    return Scaffold(
      body: LoadingOverlay(
        visible: _busy,
        message: _busyLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                theme.colorScheme.surface,
                theme.colorScheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: AnimatedBuilder(
              animation: scope.gallery,
              builder: (context, _) {
                final recent = scope.gallery.recent(
                  limit: AppConstants.homeRecentLimit,
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                  children: [
                    _Header(onSettings: _openSettings),
                    const SizedBox(height: 24),
                    _TracingHero(onTap: _openTracing),
                    const SizedBox(height: 14),
                    _SnapCameraCard(onTap: _openCamera),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 158,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _FeatureCard(
                              icon: Icons.auto_fix_high_rounded,
                              accent: AppColors.primary,
                              title: 'Photo editor',
                              subtitle: 'AI anime, pencil sketch and outlines',
                              onTap: _openEditor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FeatureCard(
                              icon: Icons.photo_library_rounded,
                              accent: AppColors.secondary,
                              title: 'My gallery',
                              subtitle: scope.gallery.items.isEmpty
                                  ? 'Your saved images live here'
                                  : formatCount(
                                      scope.gallery.items.length,
                                      'saved image',
                                    ),
                              onTap: _openGallery,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    SectionHeader(
                      title: 'Recent',
                      subtitle: recent.isEmpty
                          ? 'Your latest work will appear here'
                          : 'Tap an image to open it',
                      trailing: recent.isEmpty
                          ? null
                          : TextButton(
                              onPressed: _openGallery,
                              child: const Text('See all'),
                            ),
                    ),
                    const SizedBox(height: 14),
                    if (recent.isEmpty)
                      const _RecentPlaceholder()
                    else
                      SizedBox(
                        height: 142,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recent.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final item = recent[index];
                            return _RecentTile(
                              item: item,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        ImageDetailScreen(item: item),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 28),
                    const _TracingTip(),
                    const SizedBox(height: 26),
                    Center(
                      child: Text(
                        'Made for paper, pencils and steady hands',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SketchifyMark(size: 44, showGlow: false),
        const SizedBox(width: 12),
        const Expanded(
          child: SketchifyWordmark(fontSize: 24, showTagline: true),
        ),
        IconButton(
          onPressed: onSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }
}

class _TracingHero extends StatelessWidget {
  const _TracingHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.primaryDeep,
              AppColors.primary,
              Color(0xFFB08CFF),
            ],
            stops: <double>[0.0, 0.55, 1.0],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 208,
            child: Stack(
              children: [
                Positioned(
                  right: -36,
                  top: -46,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 112,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'CAMERA TRACING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Turn any reference\ninto a tracing guide',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: onTap,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primaryDeep,
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                            ),
                            icon: const Icon(Icons.videocam_rounded, size: 20),
                            label: const Text('Start tracing'),
                          ),
                          const SizedBox(width: 12),
                          const Flexible(
                            child: Text(
                              'Live camera + opacity overlay',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.25,
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
        ),
      ),
    );
  }
}

class _SnapCameraCard extends StatelessWidget {
  const _SnapCameraCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AppColors.primary.withValues(alpha: 0.16),
                AppColors.secondary.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[AppColors.primary, AppColors.secondary],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snap & stylize',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Take a photo. Get sketch, anime, or clean edges.',
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
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 21, color: accent),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
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
      ),
    );
  }
}

class _RecentPlaceholder extends StatelessWidget {
  const _RecentPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.brush_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nothing here yet', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Import a photo or save a filter result to start your gallery.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item, required this.onTap});

  final GalleryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageFile = item.thumbPath ?? item.imagePath;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
                    Image.file(
                      File(imageFile),
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.type == GalleryItemType.reference
                              ? 'REF'
                              : (item.filter?.shortLabel.toUpperCase() ??
                                    'ORIGINAL'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TracingTip extends StatelessWidget {
  const _TracingTip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              size: 20,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tracing tip', style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  'Place your phone on a stand, dim the room and watch the '
                  'Smart Level turn green before you start drawing.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
