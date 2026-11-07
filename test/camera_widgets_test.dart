import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/core/theme/app_theme.dart';
import 'package:sketchify/features/camera/widgets/camera_filter_strip.dart';
import 'package:sketchify/features/camera/widgets/camera_shutter_button.dart';
import 'package:sketchify/models/filter_type.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: SizedBox(width: 390, child: child)),
    ),
  );
}

void main() {
  testWidgets('shows every camera filter with a single AI badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(CameraFilterStrip(selected: FilterType.sketch, onSelected: (_) {})),
    );

    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Sketch'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('Edges'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    // Editor-only looks stay out of the camera strip, including the online
    // face transforms.
    expect(find.text('Mono'), findsNothing);
    expect(find.text('Vintage'), findsNothing);
    expect(find.text('Feminize'), findsNothing);
    expect(find.text('Masculinize'), findsNothing);
    expect(find.textContaining('ONLINE'), findsNothing);
  });

  testWidgets('reports the tapped camera filter', (tester) async {
    FilterType? choice;
    await tester.pumpWidget(
      _wrap(
        CameraFilterStrip(
          selected: FilterType.sketch,
          onSelected: (filter) => choice = filter,
        ),
      ),
    );

    await tester.tap(find.text('Anime'));
    await tester.pump();

    expect(choice, FilterType.anime);
  });

  testWidgets('ignores filter taps while the camera is busy', (tester) async {
    FilterType? choice;
    await tester.pumpWidget(
      _wrap(
        CameraFilterStrip(
          selected: FilterType.sketch,
          onSelected: (filter) => choice = filter,
          enabled: false,
        ),
      ),
    );

    await tester.tap(find.text('Edges'), warnIfMissed: false);
    await tester.pump();

    expect(choice, isNull);
  });

  testWidgets('shutter only fires when it is enabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        CameraShutterButton(
          enabled: false,
          busy: false,
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(CameraShutterButton), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);

    await tester.pumpWidget(
      _wrap(
        CameraShutterButton(
          enabled: true,
          busy: false,
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byType(CameraShutterButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('shutter shows progress and blocks capture while busy', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        CameraShutterButton(enabled: true, busy: true, onPressed: () => taps++),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(CameraShutterButton), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
  });
}
