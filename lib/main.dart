import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_scope.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'services/anime/anime_engine.dart';
import 'services/anime/remote_anime_client.dart';
import 'services/face_transform/remote_face_transform_client.dart';
import 'services/gallery_repository.dart';
import 'services/image_picker_service.dart';
import 'services/image_processing_service.dart';
import 'services/library_service.dart';
import 'services/sensor_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';

const String _animeProxyUrl = String.fromEnvironment('ANIME_PROXY_URL');
const String _animeAppToken = String.fromEnvironment('ANIME_APP_TOKEN');
const String _faceProxyUrl = String.fromEnvironment('FACE_PROXY_URL');
const String _faceAppToken = String.fromEnvironment('FACE_APP_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerThirdPartyLicenses();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  try {
    final settings = await SettingsService.create();
    final storage = await StorageService.create();
    final gallery = GalleryRepository(storage: storage);
    await gallery.load();

    final anime = AnimeEngine();
    unawaited(anime.warmUp());
    final processing = ImageProcessingService(
      anime: anime,
      remoteAnime: _buildRemoteAnimeClient(),
      onlineAnimeEnabled: () => settings.onlineAnimeEnabled,
      remoteFaceTransform: _buildRemoteFaceTransformClient(),
      faceTransformEnabled: () => settings.faceTransformEnabled,
    );
    final picker = ImagePickerService();
    final library = LibraryService(
      picker: picker,
      processing: processing,
      gallery: gallery,
      storage: storage,
    );
    final sensors = SensorService(settings);

    runApp(
      AppScope(
        settings: settings,
        storage: storage,
        gallery: gallery,
        processing: processing,
        picker: picker,
        library: library,
        sensors: sensors,
        child: const SketchifyApp(),
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('Sketchify failed to start: $error\n$stackTrace');
    runApp(StartupFailureApp(message: error.toString()));
  }
}

RemoteAnimeClient? _buildRemoteAnimeClient() {
  final url = _animeProxyUrl.trim();
  final token = _animeAppToken.trim();
  if (url.isEmpty || token.isEmpty) return null;
  final endpoint = Uri.tryParse(url);
  if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
    debugPrint('Ignoring invalid ANIME_PROXY_URL.');
    return null;
  }
  return RemoteAnimeClient(endpoint: endpoint, appToken: token);
}

RemoteFaceTransformClient? _buildRemoteFaceTransformClient() {
  final token = _faceAppToken.trim().isNotEmpty
      ? _faceAppToken.trim()
      : _animeAppToken.trim();
  if (token.isEmpty) return null;

  final explicitUrl = _faceProxyUrl.trim();
  final endpoint = explicitUrl.isNotEmpty
      ? _parseProxyUrl(explicitUrl, 'FACE_PROXY_URL')
      : _deriveFaceEndpoint(_animeProxyUrl.trim());
  if (endpoint == null) return null;
  return RemoteFaceTransformClient(endpoint: endpoint, appToken: token);
}

Uri? _parseProxyUrl(String raw, String name) {
  final endpoint = Uri.tryParse(raw);
  if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
    debugPrint('Ignoring invalid $name.');
    return null;
  }
  return endpoint;
}

/// Uses the anime proxy URL when FACE_PROXY_URL is omitted, because both
/// routes live on the same service.
Uri? _deriveFaceEndpoint(String animeUrl) {
  if (animeUrl.isEmpty) return null;
  final anime = _parseProxyUrl(animeUrl, 'ANIME_PROXY_URL');
  if (anime == null) return null;

  final base = anime.path.replaceFirst(RegExp(r'/+$'), '');
  final path = base.endsWith('/anime')
      ? '${base.substring(0, base.length - '/anime'.length)}/face-transform'
      : '$base/face-transform';
  return anime.replace(path: path);
}

void _registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      <String>['AnimeGANv2 portrait model'],
      'AnimeGANv2 is by Xin Chen and is made available for non-commercial '
      'use such as research, teaching and personal projects.\n\n'
      'https://github.com/TachibanaYoshino/AnimeGANv2\n\n'
      'Commercial use requires written permission from the author. The '
      'bundled weights are used here on a personal, non-commercial basis.',
    );
    yield const LicenseEntryWithLineBreaks(
      <String>['LingDong-Image model packaging'],
      'MIT License\n\n'
      'Copyright (c) 2026 qjngbac\n\n'
      'Permission is hereby granted, free of charge, to any person obtaining '
      'a copy of this software and associated documentation files (the '
      '"Software"), to deal in the Software without restriction, including '
      'without limitation the rights to use, copy, modify, merge, publish, '
      'distribute, sublicense, and/or sell copies of the Software, and to '
      'permit persons to whom the Software is furnished to do so, subject to '
      'the following conditions:\n\n'
      'The above copyright notice and this permission notice shall be '
      'included in all copies or substantial portions of the Software.\n\n'
      'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, '
      'EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
      'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND '
      'NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS '
      'BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN '
      'ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN '
      'CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE '
      'SOFTWARE.',
    );
  });
}

class SketchifyApp extends StatelessWidget {
  const SketchifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return AnimatedBuilder(
      animation: scope.settings,
      builder: (context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: scope.settings.themeMode,
          home: const SplashScreen(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: media.textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.3,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Sketchify could not start',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Local storage could not be prepared.\n$message',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
