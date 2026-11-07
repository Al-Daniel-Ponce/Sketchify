import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/core/theme/app_theme.dart';
import 'package:sketchify/features/tracing/widgets/level_badge.dart';
import 'package:sketchify/models/level_reading.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: child),
    ),
  );
}

void main() {
  testWidgets('shows the live angle and status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LevelBadge(
          reading: LevelReading(
            status: LevelStatus.good,
            tiltDegrees: 0.42,
            calibrated: true,
          ),
        ),
      ),
    );

    expect(find.text('0.4°'), findsOneWidget);
    expect(find.text('LEVEL'), findsOneWidget);
  });

  testWidgets('shows a tilted warning', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LevelBadge(
          reading: LevelReading(status: LevelStatus.tilted, tiltDegrees: 7.26),
        ),
      ),
    );

    expect(find.text('7.3°'), findsOneWidget);
    expect(find.text('TILTED'), findsOneWidget);
  });

  testWidgets('falls back when the sensor is unavailable', (tester) async {
    await tester.pumpWidget(
      _wrap(const LevelBadge(reading: LevelReading.unavailable())),
    );

    expect(find.text('--'), findsOneWidget);
    expect(find.text('NO SENSOR'), findsOneWidget);
  });

  testWidgets('is tappable and exposes semantics', (tester) async {
    var taps = 0;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        LevelBadge(
          reading: const LevelReading(
            status: LevelStatus.warning,
            tiltDegrees: 3.5,
          ),
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('Smart level')), findsOneWidget);

    await tester.tap(find.byType(LevelBadge));
    await tester.pump();
    expect(taps, 1);

    handle.dispose();
  });
}
