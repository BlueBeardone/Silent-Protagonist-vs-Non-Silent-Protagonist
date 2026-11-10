import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/camp_filter.dart';

void main() {
  Widget host(Camp? selected, ValueChanged<Camp?> onChanged) => MaterialApp(
    home: Scaffold(
      body: CampFilter(selected: selected, onChanged: onChanged),
    ),
  );

  testWidgets('offers all, silent, and non-silent filters', (tester) async {
    await tester.pumpWidget(host(null, (_) {}));

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.text('Non-silent'), findsOneWidget);
  });

  testWidgets('reports the camp the user picks', (tester) async {
    Camp? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CampFilter(
              selected: selected,
              onChanged: (camp) => setState(() => selected = camp),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Silent'));
    await tester.pumpAndSettle();
    expect(selected, Camp.silent);

    await tester.tap(find.text('Non-silent'));
    await tester.pumpAndSettle();
    expect(selected, Camp.nonSilent);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
