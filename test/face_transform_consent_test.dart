import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/core/theme/app_theme.dart';
import 'package:sketchify/features/settings/widgets/face_transform_consent.dart';

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const FaceTransformConsentDialog(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains the upload, offline limit and permission rule', (
    tester,
  ) async {
    await _openDialog(tester);

    expect(find.text('Use online face transform?'), findsOneWidget);
    expect(find.textContaining('hosted AI service'), findsOneWidget);
    expect(find.textContaining('not a real gender transition'), findsOneWidget);
    expect(
      find.text('I have permission from the person in this photo.'),
      findsOneWidget,
    );
    expect(find.textContaining('Internet is required'), findsOneWidget);
  });

  testWidgets('agree stays disabled until the permission box is checked', (
    tester,
  ) async {
    await _openDialog(tester);

    final agree = find.widgetWithText(FilledButton, 'Agree & continue');
    expect(tester.widget<FilledButton>(agree).onPressed, isNull);

    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(agree).onPressed, isNotNull);
  });

  testWidgets('cancel closes without consent', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const FaceTransformConsentDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('agree returns true after checking the permission box', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const FaceTransformConsentDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree & continue'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  test('the persistent reminder keeps the permission rule visible', () {
    expect(faceTransformReminder, contains('permission'));
    expect(faceTransformReminder, contains('may not preserve'));
  });
}
