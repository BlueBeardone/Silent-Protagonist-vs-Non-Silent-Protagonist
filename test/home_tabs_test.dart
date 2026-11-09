import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/ui/community_tab.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/main.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

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

  /// Opens the left drawer via its hamburger button.
  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
  }

  testWidgets('drawer offers Chart, Numbers and Community destinations',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Chart'), findsNothing);
    await openDrawer(tester);

    expect(find.text('Chart'), findsOneWidget);
    expect(find.text('Numbers'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
  });

  testWidgets('opens on the chart', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Silent total'), findsNothing);
  });

  testWidgets('choosing Numbers from the drawer shows the numerical comparison',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.text('Numbers'));
    await tester.pumpAndSettle();

    expect(find.text('Silent total'), findsOneWidget);
    expect(find.text('Silent games are more popular overall'), findsOneWidget);
  });

  testWidgets('Community destination is reachable even when stats fail',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(loadStats: () async => throw Exception('steam down')),
    ));
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityTab), findsOneWidget);
  });

  /// Sizes the test surface to a phone-like viewport narrower than the
  /// breakpoint, and restores it afterwards.
  void useNarrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('narrow screen shows a bottom navigation bar, not a drawer',
      (tester) async {
    useNarrowScreen(tester);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('bottom navigation switches destination on a narrow screen',
      (tester) async {
    useNarrowScreen(tester);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Numbers'));
    await tester.pumpAndSettle();

    expect(find.text('Silent total'), findsOneWidget);
  });

  testWidgets('wide screen keeps the drawer navigation',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
