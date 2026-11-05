import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/main.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats.dart';

void main() {
  const sample = <GameStats>[
    GameStats(
        name: 'Elden Ring',
        camp: Camp.silent,
        appid: 1,
        current: 900,
        avg30d: 800,
        avg6m: 700),
    GameStats(
        name: 'God of War',
        camp: Camp.nonSilent,
        appid: 2,
        current: 100,
        avg30d: 200,
        avg6m: 300),
  ];

  Widget app() => MaterialApp(home: HomePage(loadStats: () async => sample));

  testWidgets('offers a Chart tab and a Numbers tab', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Chart'), findsOneWidget);
    expect(find.text('Numbers'), findsOneWidget);
  });

  testWidgets('opens on the chart', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Silent total'), findsNothing);
  });

  testWidgets('switching to Numbers shows the numerical comparison',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Numbers'));
    await tester.pumpAndSettle();

    expect(find.text('Silent total'), findsOneWidget);
    expect(find.text('Silent games are more popular overall'), findsOneWidget);
  });

  testWidgets('Community tab is reachable even when stats fail',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(loadStats: () async => throw Exception('steam down')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Community'), findsOneWidget);
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    expect(find.text('Post'), findsOneWidget);
  });
}
