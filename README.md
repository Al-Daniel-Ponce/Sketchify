# Sketchify

**An offline-first Flutter studio for on-device AI anime, quick photo styles, a
snap-and-stylize camera, live camera tracing, and a sensor-powered Smart Level.**

Sketchify turns photos into anime scenes, pencil sketches, comic panels, and
other looks, then lets you trace them against a live camera feed. The Anime
filter runs a real AnimeGANv2 neural network on the device through LiteRT
(TensorFlow Lite). There are no accounts or ads, and no photo leaves the phone
unless you explicitly turn on one of the optional online AI services (Anime or
face transform).

| | |
|---|---|
| **Platform** | Android (portrait), iOS project included |
| **Current build** | `1.0.0+1` |
| **Package** | `com.sketchify.app` |
| **Flutter / Dart** | 3.38.8 / 3.10.7 |
| **Min / target SDK** | 24 / 36 |
| **Anime model** | AnimeGANv2 `face_paint_512_v2`, 8.64 MB, bundled |
| **Face transform** | Optional online model through the same proxy; no bundled model |
| **Inference** | LiteRT via `tflite_flutter` 0.12.1, CPU (4 threads) |
| **Storage** | App-private only |
| **Network** | Off by default. `INTERNET` exists only for opt-in online Anime and face transform. |

---

## Features

### Snap & stylize camera

- A **Snap & stylize** card on Home opens a full-screen portrait camera.
- Flash modes, front/rear switching, and a shutter button sized for one-handed
  shooting.
- Four camera filters: **Original**, **Sketch**, **Anime** (with its AI badge),
  and **Edges**. Sketch is the default and the last choice is remembered for the
  rest of the app session.
- Filters are applied after capture rather than to the viewfinder, because the
  on-device Anime pass takes roughly 20 seconds per frame.
- Shutter → freeze frame → release the camera preview → process at the selected
  quality → result screen. The result screen has a before/after slider,
  **Retake**, and an explicit **Save**.
- Nothing is written to the gallery until Save is tapped. Only the styled
  result is saved; the unfiltered capture stays temporary.
- Camera Tracing is unchanged and still uses its own rear-camera service path.

### Photo editor, quick styles & filters

- Pick any photo with the Android photo picker; Sketchify keeps its own copy.
- Fast filter previews at 220 px, then a full render at up to 2048 px.
- Press and hold the preview to compare the original with the result.
- Save the edit into the in-app gallery; jump straight to the saved image.
- **Quick styles** opens a sheet of fixed prompt chips:
  **Cartoon character**, **Black & white**, **Comic book**, **Pencil drawing**,
  **Clean outline**, **Old photo**, **Dramatic noir**, **Soft portrait**, and
  **Bold portrait**.
- The full **All filters** picker still exposes every look with previews.
- The local filters run offline:

| Filter | What it does |
|---|---|
| **Original** | Flattens transparency onto white and keeps the source colours |
| **Anime** | AnimeGANv2 neural style transfer, on-device by default; optional hosted service when opted in. Falls back to a pure-Dart stylisation if both AI paths fail. |
| **Pencil Sketch** | Grayscale colour-dodge against a blurred inversion, for graphite-like shading |
| **Edge Detection** | Sobel gradient magnitude with an adaptive threshold, rendered as ink on paper |
| **Black & White** | Luminance conversion with a gentle contrast curve |
| **Noir** | High-contrast silver tones with a soft vignette |
| **Comic Book** | Flat, saturated colour bands with bold ink outlines |
| **Vintage** | Faded sepia, lifted shadows, a vignette, and deterministic grain |
| **Poster** | Flat five-level colour bands with boosted saturation |
| **Soft Portrait** | Cosmetic soft-focus blend with warm rose tones |
| **Bold Portrait** | Cosmetic cool tones, deeper shadows, and unsharp detail |
| **Feminize Face** | Online AI that edits the person with a more feminine presentation |
| **Masculinize Face** | Online AI that edits the person with a more masculine presentation |

**Soft Portrait** and **Bold Portrait** are tone and soft-focus presets. They
are cosmetic looks and do not change who is in the photo or a person's gender.
That disclaimer appears in the Quick styles sheet and when either preset is
selected.

**Feminize Face** and **Masculinize Face** are separate, editor-only online AI
filters. They are intentionally not automatic: Sketchify never detects or
guesses someone's gender. The user picks the direction, confirms they have
permission from the person in the photo, and the photo is sent to the proxy for
editing. There is no local fallback.

#### How Anime runs

1. The image is decoded at the selected processing quality.
2. **Online first, when enabled.** If online Anime is on, the decoded frame is
   JPEG-encoded, sent to the Sketchify proxy with a bearer app token, and the
   returned JPEG is validated for content type, size, and exact dimensions.
   The proxy holds the Replicate provider key; it never ships in the APK.
3. **On-device fallback.** If online Anime is off, not configured, offline,
   too slow, or returns an invalid result, the frame goes to the bundled model:
   it is letterboxed into the model's 512×512 input with edge-replicated
   padding, run in a dedicated worker isolate on the reference CPU backend with
   4 threads, cropped back to the source aspect ratio, and upsampled.
4. **Pure-Dart fallback.** If both neural paths fail, a deterministic
   stylisation is used and the UI labels it as a local fallback.
5. A failed worker is restarted on the next request. XNNPack is deliberately not
   enabled: it segfaulted inside `libtensorflowlite_jni.so` while loading this
   model on a real arm64 phone.

The first local pass on a mid-range phone can take several seconds to tens of
seconds; later passes reuse the loaded model. Online Anime has a 60-second app
timeout and a 55-second proxy timeout.

#### How face transform runs

1. The photo is decoded at the selected processing quality and JPEG-encoded.
2. The user must first accept the face-transform notice and tick **I have
   permission from the person in this photo.** The choice is stored, but the
   filters remain opt-in and can be switched off in Settings.
3. The app posts the JPEG to `POST /face-transform?direction=feminize` or
   `?direction=masculinize` with the app token. The direction is always chosen
   explicitly by the user.
4. The proxy calls the configured Replicate model, downloads the result, rotates
   it by EXIF, and crops it with an attention-biased cover resize to the exact
   uploaded dimensions.
5. The app validates the reply and shows the result with an **ONLINE AI** source
   label. Face transform has a 120-second app timeout and a 110-second proxy
   timeout.
6. If the build has no face proxy, the switch is off, the network is unavailable,
   or the model fails, the editor shows an error and keeps the previous result.
   It never substitutes a cosmetic tone filter for a real face transform.

The face model is configured entirely on the server (`FACE_MODEL` or
`FACE_MODEL_VERSION`, optional per-direction overrides, and optional input
fields). See [`server/anime-proxy`](server/anime-proxy) for the contract and
environment variables. Face transform appears in **All filters**; Quick styles
stays the nine cosmetic chips.

### Camera tracing

- Rear-camera preview as the drawing surface; tracing never captures a frame.
- Gallery photo or saved reference overlaid at 0–100 % opacity (50 % default).
- Drag to pan, pinch to zoom, twist to rotate, double-tap to fit.
- Fit, rotate, flip, and lock controls; locks stop accidental pan/zoom.
- Choose or change the reference from the device or the saved References tab.
- Focus mode hides the chrome, with the level badge still visible.
- Optional keep-screen-awake while tracing.
- If the camera is unavailable, tracing still works on a paper backdrop and the
  UI explains how to retry or open system settings.

### Smart Level

- Accelerometer gravity vector, exponentially smoothed (faster response while
  the phone is moving).
- Green at ≤ 2°, yellow at 3–5°, red above 5° by default.
- Sensitivity presets: Relaxed (3°/7°), Standard (2°/5°), Strict (1°/3°).
- 0.4° hysteresis stops the colour flickering at a threshold.
- Live angle and tilt hint; tap the badge for the full level sheet.
- Calibration stores the current orientation as zero; reset from the sheet or
  Settings.
- Graceful "No sensor" fallback on devices or emulators without an
  accelerometer.

### Gallery

- Tabs for **All**, **Edited**, and **References**, with counts.
- View full-screen with zoom, metadata, edit, trace, and delete.
- Import photos directly into the gallery.
- Storage usage display and "delete all" with confirmation.
- Index is rewritten atomically; corrupt or missing entries are recovered
  safely on load.

### Settings

- Theme: System, Light, or Dark (dark by default).
- Default tracing opacity and keep-screen-awake.
- Level sensitivity and calibration reset.
- Processing quality: Fast (1280 px), Balanced (1600 px), High (2048 px).
- Optional **Online anime** switch, disabled unless the build has a proxy URL
  and app token. Turning it on shows a first-use privacy notice.
- Optional **Online face transform** switch, with a first-use notice and a
  permission checkbox. Disabled unless the build has a face proxy.
- Storage usage, delete all images, reset preferences.
- Version, privacy summary, and open-source licenses.

---

## Privacy

- Sketchify works fully offline by default. No analytics, accounts, ads, or
  background uploads.
- The main Android manifest declares `INTERNET` for the optional online Anime
  and face-transform features. The app makes no network request unless the
  matching switch is on, the build is configured with a proxy, and the user has
  accepted the first-use notice.
- With both online options off, the bundled Anime model runs entirely on the
  device. No image, tensor, or result leaves the app.
- With online Anime on, only the photo being styled is sent to the configured
  Sketchify proxy and on to the hosted model provider. The proxy does not write
  photos to disk or keep server copies. Provider-side handling is governed by
  that provider's policy.
- With face transform on, the photo the user chooses to transform is sent to the
  same proxy and the configured face model. The user must confirm they have
  permission from the person in the photo. The proxy does not keep copies, but
  the model provider's retention policy still applies. AI face editing can look
  unrealistic and may not preserve the person's identity.
- The Replicate provider key exists only in the proxy environment. The app
  carries separate low-privilege app tokens used for authentication and rate
  limiting. They are extractable from an APK, so rotate them if abused. Face
  transform reuses the Anime app token unless `FACE_APP_TOKEN` is set.
- Camera Tracing frames are displayed, never recorded or uploaded.
- Snap & stylize photos stay in memory until the user taps Save. Only the styled
  result is written to the app gallery.
- Imported and edited images live in the app's private documents directory
  (typically `/data/user/0/com.sketchify.app/app_flutter/sketchify`):
  - `images/` — edited and imported photos
  - `references/` — tracing references
  - `thumbnails/` — gallery thumbnails
  - `gallery_index.json` — metadata index
- Images are not exported to the system gallery and disappear when the app is
  uninstalled or its storage is cleared.
- The photo picker grants access to the one image the user chooses; no broad
  storage permission is requested.

---

## Getting started

### Prerequisites

- Flutter 3.38.x or newer (Dart 3.10.x)
- Android SDK 36 and Java 17
- An Android device or emulator running API 24+

### Run

```bash
flutter pub get
flutter run
```

Online Anime is disabled unless the build supplies both Anime defines. Face
transform is disabled unless the same token (or `FACE_APP_TOKEN`) and a face URL
are available. The face URL is derived from the Anime URL when it is omitted.

```bash
flutter run \
  --dart-define=ANIME_PROXY_URL=https://your-service.example/anime \
  --dart-define=ANIME_APP_TOKEN=the-same-app-token \
  --dart-define=FACE_PROXY_URL=https://your-service.example/face-transform \
  --dart-define=FACE_APP_TOKEN=the-same-app-token
```

### Build

```bash
# Debug APK (verified)
flutter build apk --debug

# Release APK
flutter build apk --release

# Smaller per-ABI release builds
flutter build apk --release --split-per-abi

# Release build with optional online Anime and face transform
flutter build apk --release --split-per-abi \
  --dart-define=ANIME_PROXY_URL=https://your-service.example/anime \
  --dart-define=ANIME_APP_TOKEN=the-same-app-token \
  --dart-define=FACE_PROXY_URL=https://your-service.example/face-transform \
  --dart-define=FACE_APP_TOKEN=the-same-app-token
```

`FACE_PROXY_URL` and `FACE_APP_TOKEN` are optional. When omitted, the app derives
`/face-transform` from `ANIME_PROXY_URL` and reuses `ANIME_APP_TOKEN`.

The release build is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The debug build is written to:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

The universal release APK carries the 8.24 MB model plus LiteRT native
libraries for arm64-v8a, armeabi-v7a, and x86_64. `--split-per-abi` produces
smaller per-device APKs; use the arm64 build for modern phones. The first Gradle
build downloads dependencies and can take several minutes.

### Optional online AI proxy

The optional proxy lives in [`server/anime-proxy`](server/anime-proxy). It is a
small Node 20 + Express service with two authenticated JPEG endpoints:

- `POST /anime` calls a hosted Replicate anime model.
- `POST /face-transform?direction=feminize|masculinize` calls the configured face
  model and returns an attention-cropped JPEG at the uploaded dimensions.

Both return a JPEG with exactly the uploaded dimensions. See its README for the
full contract, face-model configuration, and Render/Railway/Fly.io deployment
steps.

Provider secrets stay on the server:

```text
REPLICATE_API_TOKEN        # provider key, never in the APK
APP_TOKEN                  # shared with the app build
REPLICATE_MODEL_VERSION    # anime model version
FACE_MODEL                 # or FACE_MODEL_VERSION; optional face model
FACE_DIRECTION_FIELD       # optional target-gender input name
FACE_FEMINIZE_INPUT_JSON   # optional per-direction model inputs
FACE_MASCULINIZE_INPUT_JSON
```

Online Anime and face transform are intentionally opt-in and off by default.
Anime quality should be checked on 3–5 photos before recommending it; a hosted
model is not automatically better than the bundled AnimeGANv2 portrait model.
Check the face model's input schema, output format, cost, latency, and licence
before enabling it. The provided face filters are explicit transforms, not
automatic gender detection.

### Dependency note

`permission_handler` is pinned to **12.0.3**. `permission_handler_android`
13/14 requires a newer AGP/Kotlin toolchain (AGP 9, Kotlin 2.3) and fails to
compile with this project's Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 setup.
Do not bump the pin without upgrading the Android toolchain and re-running the
APK build.

---

## Permissions

| Permission / feature | Why | If unavailable |
|---|---|---|
| `CAMERA` | Live tracing preview and Snap & stylize capture | Editor and gallery still work; tracing falls back to a paper backdrop and offers retry/settings |
| `INTERNET` | Optional online Anime and face transform only | Anime falls back to the bundled on-device model; face transform stays unavailable |
| Accelerometer (optional feature) | Smart Level | Shows "No sensor" and keeps tracing usable |
| Gyroscope (optional feature) | Faster smoothing while moving | Level still works from the accelerometer |
| Photo picker | Choosing photos and references | No storage permission needed |
| Wakelock (`FLAG_KEEP_SCREEN_ON`) | Keep the screen on while tracing | Optional in Settings |

Camera and sensor features are declared `required="false"`, so the app installs
on devices that lack them.

---

## Architecture

Sketchify uses a small, explicit layered structure rather than a heavyweight
state-management framework.

```text
lib/
├── main.dart                     App bootstrap, online AI config, MaterialApp
├── core/
│   ├── app_scope.dart            InheritedWidget exposing shared services
│   ├── constants/                App-wide limits and defaults
│   ├── theme/                    Colours and Material 3 themes
│   └── utils/                    Errors, formatting, IDs, level maths
├── models/
│   ├── filter_type.dart          All 13 filters, labels, icons, camera subset
│   ├── face_transform.dart       Feminize/masculinize direction enum
│   ├── quick_style.dart          Fixed Quick styles chips and disclaimer
│   ├── gallery_item.dart         Persisted metadata + JSON mapping
│   ├── level_reading.dart        Angle, status, labels, sensitivity presets
│   └── overlay_controller.dart   Opacity, scale, rotation, pan, flip, lock
├── services/
│   ├── anime/
│   │   ├── anime_engine.dart     Worker isolate, CPU runtime, timeouts, restart
│   │   ├── anime_styler.dart     Renderer interface and result types
│   │   ├── anime_tensor.dart     Model contract, letterboxing, tensor I/O
│   │   └── remote_anime_client.dart  Authenticated proxy upload + validation
│   ├── face_transform/
│   │   └── remote_face_transform_client.dart  Directional proxy upload
│   ├── camera_service.dart       Camera lifecycle, lens, flash, capture
│   ├── sensor_service.dart       Smoothed level readings and calibration
│   ├── image_picker_service.dart Photo picker wrapper
│   ├── image_processing_service.dart  Decode, AI routing, filters, JPEG
│   ├── filters/filter_engine.dart     Pure-Dart effects and Anime fallback
│   ├── storage_service.dart      App-private directories and atomic index
│   ├── gallery_repository.dart   In-memory list + persisted index
│   ├── library_service.dart      Import, thumbnail, save, delete
│   └── settings_service.dart     SharedPreferences-backed preferences
├── features/
│   ├── splash/                   Animated launch screen
│   ├── home/                     Studio dashboard and recent work
│   ├── camera/                   Snap & stylize capture, filter strip, result
│   ├── editor/                   Quick styles, filters, compare, save
│   ├── filters/                  Filter cards and full-screen picker
│   ├── gallery/                  Tabs, tiles, detail, delete
│   ├── tracing/                  Camera overlay, Smart Level, controls
│   └── settings/                 Preferences, online consent, storage tools
└── shared/
    ├── widgets/                  Logo, loading, empty/error states, headers
    └── utils/                    Haptics and snackbar helpers
```

**State flow.** `main.dart` creates the services and mounts an `AppScope`
(`InheritedWidget`). `SettingsService` and `GalleryRepository` are
`ChangeNotifier`s; `SensorService` exposes a `ValueNotifier<LevelReading>`.
Screens read services from `AppScope.of(context)` and listen to the notifiers
they need. Navigation uses `Navigator.push` with Material routes.

**Image pipeline.** Photos are decoded through `dart:ui` at a bounded target
size (so a 50 MP source never becomes a 50 MP RGBA buffer), converted to
`rawStraightRgba`, and dispatched by `ImageProcessingService`. Anime frames try
`RemoteAnimeClient` first when opted in, then `AnimeEngine`, then the pure-Dart
engine; the two face filters branch to `RemoteFaceTransformClient` with no local
fallback; other filters go straight through `Isolate.run` and `FilterEngine`.
The result is encoded as JPEG (quality 93, or 95 for edges). Thumbnails are
520 px JPEGs. The editor caches one result per filter, discards stale results
with a request token, and skips all AI filters when building the fast preview
strip.

**Online Anime.** `main.dart` reads `ANIME_PROXY_URL` and `ANIME_APP_TOKEN` from
dart-defines. If either is missing, the setting is disabled and no network path
is created. `RemoteAnimeClient` encodes the decoded frame to JPEG off the UI
isolate, posts it with a bearer token, and validates the reply before any pixels
are used. `ImageProcessingService` falls back to the bundled model on timeout,
HTTP failure, malformed output, or missing configuration.

**Online face transform.** `main.dart` reads `FACE_PROXY_URL`/`FACE_APP_TOKEN`
or derives them from the Anime values. `RemoteFaceTransformClient` appends the
selected direction, uploads a JPEG, and rejects malformed or wrong-sized
replies. `ImageProcessingService` throws a user-facing error instead of falling
back, because a cosmetic local filter would not actually transform the person.
The editor gates the first run on a stored permission/consent notice and offers
the two directions in **All filters** only.

**Anime runtime ownership.** `AnimeEngine` owns its isolate instead of using
`IsolateInterpreter`, so native crashes, tensor-contract errors, and timeouts
surface as `AnimeException` rather than a permanently pending future. The worker
is spawned lazily, warmed at startup, restarted after a failure, and reports the
active backend (`CPU · 4 threads`). All native handles are closed when the
engine is disposed.

**Storage.** `StorageService` owns the directory layout and writes the index
through a temporary file plus rename, with a Windows-safe fallback. The gallery
repository filters out entries whose image file has disappeared.

**Tracing lifecycle.** `CameraService` handles permission states and rear-camera
selection; the tracing screen uses a monotonically increasing token and a
restart queue to survive pause/resume races. The camera is disposed when the
screen is paused, hidden, or popped, and sensor subscriptions are cancelled.
`SensorService` is a shared singleton and is never disposed by the screen.

**Smart Level maths.** `gravityTiltDegrees` computes the angle between the
current gravity vector and a flat reference (or the saved calibration vector).
An exponential moving average smooths the accelerometer, with a faster alpha
while the gyroscope reports movement. `resolveLevelStatus` applies a 0.4°
hysteresis band around each threshold.

---

## Tests

```bash
flutter analyze
flutter test
```

The suite contains **126 tests** across fifteen files:

| File | Coverage |
|---|---|
| `test/filter_engine_test.dart` | Opaque output, alpha flattening, sketch, edges, Anime fallback, mono/noir, comic, vintage, poster, portrait tone shifts, face-transform rejection, validation, 1×1 images |
| `test/anime_tensor_test.dart` | TFL3 magic, NCHW/NHWC layout detection, tensor-shape rejection, letterbox mapping, normalization, transparency flattening, output de-normalization and upsampling |
| `test/face_transform_test.dart` | Direction wire names, AI/online flags, cosmetic preset separation, camera subset, legacy name mapping |
| `test/remote_anime_client_test.dart` | Auth header, JPEG upload, exact-dimension validation, non-image replies, rejected token, timeout, missing app token |
| `test/remote_face_transform_client_test.dart` | Direction query, auth header, JPEG upload, exact-dimension validation, HTTP error mapping, timeout, missing app token |
| `test/image_processing_service_test.dart` | Local AI success, online-first success, proxy-to-local fallback, opt-out, no-token handling, both-AI failure, face direction routing, face no-fallback errors, previews skipping AI |
| `test/face_transform_consent_test.dart` | Consent copy, permission checkbox gating, cancel/agree results, persistent reminder |
| `test/quick_style_test.dart` | Fixed chip labels and filter mappings, portrait disclaimer, face-transform exclusion |
| `test/quick_styles_sheet_test.dart` | Sheet renders all chips, returns the tapped style, marks the current filter |
| `test/camera_widgets_test.dart` | Curated camera strip, single AI badge, face-transform exclusion, filter taps, busy state, shutter enablement |
| `test/level_math_test.dart` | Gravity angle, calibration, hints, thresholds, hysteresis, presets, labels |
| `test/overlay_controller_test.dart` | Clamping, pan/zoom/rotate/flip, lock, reset, matrix composition, notifications |
| `test/gallery_item_test.dart` | JSON round-trip, missing/unknown fields, titles, legacy `cartoon` mapping |
| `test/gallery_repository_test.dart` | Persistence, sorting, tabs, delete, delete-all, corrupt index, missing files, usage |
| `test/level_badge_test.dart` | Angle/status rendering, unavailable fallback, semantics and tap |

Tests use `StorageService.createAt(Directory)` so gallery/storage tests never
touch `path_provider` or real app data. Online AI tests use mocked HTTP clients
and never call a real service.

---

## Launcher icon & splash

- Adaptive icon (API 26+): gradient vector background plus lens/pencil vector
  foreground and a monochrome layer for Android 13 themed icons.
- Legacy mipmap PNGs (API 24–25), including a round variant.
- Native splash: dark ink window with the vector Sketchify mark, so there is no
  white flash before Flutter draws the first frame.

Regenerate the legacy PNGs and previews after changing the brand mark:

```bash
dart run tool/generate_icons.dart
```

The adaptive icon vectors live in `android/app/src/main/res/drawable/` and are
edited directly.

---

## Known limitations

- **Portrait only** on Android (`screenOrientation="portrait"`).
- **Android is the verified target.** The iOS project and `Info.plist`
  permissions are configured, but iOS builds require macOS/Xcode and were not
  produced here.
- **Anime and face transform are the AI filters; the rest are deterministic
  stylisations.** Very large images are downscaled to the selected processing
  quality (1280–2048 px on the long edge) before processing.
- **Local Anime on a CPU-only device is slow.** Expect roughly 20 seconds for a
  2048 px render on a mid-range phone; later passes reuse the loaded model. If
  inference fails or exceeds 60 seconds, the app uses the pure-Dart fallback.
- **Online Anime is opt-in and off by default.** It requires a deployed proxy
  and dart-defines; without them the Settings switch is disabled. Hosted model
  quality still needs a 3–5 photo comparison.
- **Face transform is online-only and opt-in.** It requires the face proxy
  configuration, a hosted model, consent, and the permission checkbox. There is
  no local fallback, so offline or failed requests leave the photo unchanged.
- **Face transform is not automatic gender detection.** Sketchify never decides
  who is in the photo; the user explicitly picks Feminize Face or Masculinize
  Face. Results can look unrealistic, may edit only one person in a group photo,
  and may not preserve identity.
- **The face model contract is deployment-specific.** The proxy exposes
  configurable model, image field, direction field, and per-direction JSON
  inputs. Verify the model's schema, licence, cost, and latency before enabling
  it. The bundled app contains no face model.
- **AnimeGANv2 weights are licensed for non-commercial use.** Check the hosted
  model's licence too. See `THIRD_PARTY_NOTICES.md` before redistributing the
  APK.
- The gallery is app-private by design; there is no "export to system gallery"
  action.
- Camera Tracing uses the live preview only. Snap & stylize is a separate camera
  mode with an explicit shutter and Save.
- Devices without an accelerometer show the "No sensor" level state; devices
  without a rear camera fall back to the paper backdrop.
- Emulators may not provide camera or sensor data; use a physical device to
  exercise tracing, the Smart Level, and Snap & stylize end to end.

---

## Troubleshooting

| Symptom | What to try |
|---|---|
| Camera shows black or "Camera unavailable" | Grant camera permission, close other camera apps, then tap the status chip to retry |
| Camera permanently blocked | Tap the status chip and choose **Settings**, enable Camera, return to the app |
| Smart Level says "No sensor" | The device/emulator has no accelerometer; tracing still works |
| Level colour flickers at a threshold | Expected hysteresis is 0.4°; choose Relaxed sensitivity for a wider band |
| `flutter build apk` fails in `permission_handler_android` | Keep `permission_handler: 12.0.3`; newer Android plugin releases need AGP 9/Kotlin 2.3 |
| Anime shows "Local fallback — AI unavailable" | Both neural paths failed. Check `adb logcat`, confirm the device has enough memory, or try a smaller processing quality |
| Online Anime is greyed out | The build lacks `ANIME_PROXY_URL` or `ANIME_APP_TOKEN`; rebuild with both defines |
| Online Anime falls back every time | Check the proxy URL, app token, provider token, model version, and `/health`; the app shows an on-device note when the proxy fails |
| Online face transform is greyed out | The build lacks a face URL/token, or the proxy has no `FACE_MODEL`/`FACE_MODEL_VERSION`; add the face configuration and rebuild or redeploy |
| Face transform shows a timeout or busy error | The hosted face model is slow or the hourly `FACE_RATE_LIMIT_MAX` budget is exhausted; retry later, raise the limit, or use a faster model |
| Face transform fails but Anime works | The proxy's face route is misconfigured. Check `FACE_MODEL`, the direction field/values, the model input schema, and the deployed face variables |
| Face filter changes nothing | Check that the proxy returned a valid JPEG with the exact uploaded dimensions and that the model actually performs the requested direction |
| Anime is very slow or times out | The local CPU backend takes roughly 20 s for a full-size render on a mid-range phone. Close memory-heavy apps, try a lower processing quality, or enable online Anime |
| Filter is slow on an old phone | Set **Settings → Image processing → Fast (1280 px)** |
| Saved images disappeared | They are app-private; uninstalling or clearing app storage removes them |

---

## Built with

Flutter, `camera`, `sensors_plus`, `wakelock_plus`, `image_picker`, `image`,
`http`, `path_provider`, `shared_preferences`, `permission_handler`, `intl`,
`tflite_flutter` (LiteRT), and the bundled AnimeGANv2 model. The optional
online proxy uses Node.js, Express, Sharp, and Replicate for both Anime and face
transform.

Sketchify is an offline-first portfolio app; no license is declared for
redistribution. The AnimeGANv2 weights are non-commercial — see
`THIRD_PARTY_NOTICES.md`.
#   S k e t c h i f y  
 #   S k e t c h i f y  
 