import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/main.dart';

// Note: flutter_test blocks real network access, so the page shows its waiting
// or error state here. This test only proves the shell boots and wires up.
void main() {
  testWidgets('boots and shows its title and refresh control', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Silent vs Non-Silent Protagonists'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
