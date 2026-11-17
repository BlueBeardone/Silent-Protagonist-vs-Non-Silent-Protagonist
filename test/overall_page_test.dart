import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/overall.dart';

void main() {
  const steam = [
    GameStats(
        name: 'Elden Ring',
        camp: Camp.silent,
        appid: 1,
        current: 100,
        avg30d: 200),
    GameStats(
        name: 'Dark Souls',
        camp: Camp.silent,
        appid: 2,
        current: 300,
        avg30d: 400),
    GameStats(
        name: 'GTA V', camp: Camp.nonSilent, appid: 3, current: 50, avg30d: 25),
  ];
  const twitch = [
    TwitchStats(
        name: 'Elden Ring',
        camp: Camp.silent,
        appid: 1,
        category: 'a',
        channels: 10,
        viewers: 1000),
    TwitchStats(
        name: 'GTA V',
        camp: Camp.nonSilent,
        appid: 3,
        category: 'b',
        channels: 5,
        viewers: 4000),
  ];

  Widget host(List<GameStats> steamStats, List<TwitchStats> twitchStats,
          {double width = 900}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 900,
            child:
                OverallComparison(steam: steamStats, twitch: twitchStats),
          ),
        ),
      );

  testWidgets('shows the four measure rows in order', (tester) async {
    await tester.pumpWidget(host(steam, twitch));

    expect(find.text('Steam current players'), findsOneWidget);
    expect(find.text('Steam 30-day average'), findsOneWidget);
    expect(find.text('Twitch live viewers'), findsOneWidget);
    expect(find.text('Twitch live channels'), findsOneWidget);
  });

  testWidgets('shows camp totals', (tester) async {
    await tester.pumpWidget(host(steam, twitch));

    expect(find.text('400'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('dashes a side with no resolved values', (tester) async {
    await tester.pumpWidget(host(steam, const [
      TwitchStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1,
          category: 'a',
          channels: 10,
          viewers: 1000),
      TwitchStats(name: 'GTA V', camp: Camp.nonSilent, appid: 3, category: 'b'),
    ]));

    expect(find.text('—'), findsWidgets);
  });

  testWidgets('verdict counts only complete rows', (tester) async {
    await tester.pumpWidget(host(steam, twitch));

    expect(find.textContaining('lead on'), findsOneWidget);
    expect(find.textContaining('3 of 4'), findsOneWidget);
  });

  testWidgets('narrow screens show cards, not a data table', (tester) async {
    await tester.pumpWidget(host(steam, twitch, width: 600));

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Steam current players'), findsOneWidget);
  });

  testWidgets('notes an unavailable source', (tester) async {
    await tester.pumpWidget(host(steam, const []));

    expect(find.textContaining('Twitch data unavailable'), findsOneWidget);
    expect(find.textContaining('TWITCH_CLIENT_ID'), findsOneWidget);
  });

  testWidgets('an incomplete measure names the short side and its counts',
      (tester) async {
    // Three silent games, the last with no Steam values, so the Steam rows are
    // short two of three on the silent side and complete on the other.
    await tester.pumpWidget(host(const [
      GameStats(
          name: 'A', camp: Camp.silent, appid: 1, current: 100, avg30d: 10),
      GameStats(
          name: 'B', camp: Camp.silent, appid: 2, current: 200, avg30d: 20),
      GameStats(name: 'C', camp: Camp.silent, appid: 3),
      GameStats(
          name: 'D', camp: Camp.nonSilent, appid: 4, current: 50, avg30d: 5),
    ], const []));

    // The missing side is named, not just an ambiguous combined fraction.
    expect(find.text('Steam current players (Silent 2/3)'), findsOneWidget);
    expect(find.text('Steam 30-day average (Silent 2/3)'), findsOneWidget);
  });
}
