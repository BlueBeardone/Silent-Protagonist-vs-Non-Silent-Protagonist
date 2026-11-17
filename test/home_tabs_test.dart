import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/ui/community_tab.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/main.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/overall.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/twitch_chart.dart';

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

  const twitchSample = <TwitchStats>[
    TwitchStats(
        name: 'Elden Ring',
        camp: Camp.silent,
        appid: 1,
        category: 'Elden Ring',
        channels: 90,
        viewers: 9000),
    TwitchStats(
        name: 'God of War',
        camp: Camp.nonSilent,
        appid: 2,
        category: 'God of War',
        channels: 10,
        viewers: 1000),
  ];

  Widget app() => MaterialApp(
        home: HomePage(
          loadStats: () async => sample,
          loadTwitch: () async => twitchSample,
        ),
      );

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
    expect(find.text('Twitch'), findsOneWidget);
    expect(find.text('Overall'), findsOneWidget);
  });

  testWidgets('Twitch destination shows the Twitch page', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.text('Twitch'));
    await tester.pumpAndSettle();

    expect(find.byType(TwitchComparison), findsOneWidget);
  });

  testWidgets('Overall destination shows the combined page', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();

    expect(find.byType(OverallComparison), findsOneWidget);
    expect(find.text('Steam current players'), findsOneWidget);
  });

  testWidgets('a Twitch failure does not break the Steam chart',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        loadStats: () async => sample,
        loadTwitch: () async => throw Exception('twitch down'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Elden Ring'), findsOneWidget);
  });

  testWidgets('both sources failing shows the Overall retry panel',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        loadStats: () async => throw Exception('steam down'),
        loadTwitch: () async => throw Exception('twitch down'),
      ),
    ));
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
      'both sources resolving to all-null data shows the Overall retry panel',
      (tester) async {
    // Neither loader throws, but neither source produced a usable number:
    // this is the "credentials unset plus Steam upstream down" case.
    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        loadStats: () async => const [
          GameStats(name: 'Elden Ring', camp: Camp.silent, appid: 1),
          GameStats(name: 'God of War', camp: Camp.nonSilent, appid: 2),
        ],
        loadTwitch: () async => const [
          TwitchStats(
              name: 'Elden Ring', camp: Camp.silent, appid: 1, category: 'a'),
          TwitchStats(
              name: 'God of War',
              camp: Camp.nonSilent,
              appid: 2,
              category: 'b'),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    await openDrawer(tester);
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('level across'), findsNothing);
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
