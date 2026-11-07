import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sketchify/core/theme/app_theme.dart';
import 'package:sketchify/features/editor/widgets/quick_styles_sheet.dart';
import 'package:sketchify/models/filter_type.dart';
import 'package:sketchify/models/quick_style.dart';

void main() {
  testWidgets('shows every prompt chip and returns the tapped style', (
    tester,
  ) async {
    QuickStyle? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  choice = await showQuickStylesSheet(
                    context,
                    selected: FilterType.original,
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

    for (final style in QuickStyle.values) {
      expect(find.text(style.label), findsOneWidget);
    }
    expect(find.textContaining('cosmetic tone'), findsOneWidget);

    await tester.tap(find.text('Comic book'));
    await tester.pumpAndSettle();

    expect(choice, QuickStyle.comicBook);
  });

  testWidgets('marks the current filter as selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showQuickStylesSheet(
                  context,
                  selected: FilterType.feminine,
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

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Soft portrait'),
    );
    expect(chip.selected, isTrue);
  });
}
