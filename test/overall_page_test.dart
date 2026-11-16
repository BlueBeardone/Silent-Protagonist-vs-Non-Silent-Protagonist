import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/reddit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
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
  const reddit = [
    RedditStats(
        name: 'Elden Ring',
        camp: Camp.silent,
        appid: 1,
        subreddit: 'a',
        online: 1000,
        members: 5000),
    RedditStats(
        name: 'GTA V',
        camp: Camp.nonSilent,
        appid: 3,
        subreddit: 'b',
        online: 4000,
        members: 600),
  ];

  Widget host(List<GameStats> steamStats, List<RedditStats> redditStats,
          {double width = 900}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 900,
            child:
                OverallComparison(steam: steamStats, reddit: redditStats),
          ),
        ),
      );

  testWidgets('shows the four measure rows in order', (tester) async {
    await tester.pumpWidget(host(steam, reddit));

    expect(find.text('Steam current players'), findsOneWidget);
    expect(find.text('Steam 30-day average'), findsOneWidget);
    expect(find.text('Reddit online now'), findsOneWidget);
    expect(find.text('Reddit total members'), findsOneWidget);
  });

  testWidgets('shows camp totals', (tester) async {
    await tester.pumpWidget(host(steam, reddit));

    expect(find.text('400'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('dashes a side with no resolved values', (tester) async {
    await tester.pumpWidget(host(steam, const [
      RedditStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1,
          subreddit: 'a',
          online: 1000,
          members: 5000),
      RedditStats(name: 'GTA V', camp: Camp.nonSilent, appid: 3, subreddit: 'b'),
    ]));

    expect(find.text('—'), findsWidgets);
  });

  testWidgets('verdict counts only complete rows', (tester) async {
    await tester.pumpWidget(host(steam, reddit));

    expect(find.textContaining('lead on'), findsOneWidget);
    expect(find.textContaining('3 of 4'), findsOneWidget);
  });

  testWidgets('narrow screens show cards, not a data table', (tester) async {
    await tester.pumpWidget(host(steam, reddit, width: 600));

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Steam current players'), findsOneWidget);
  });

  testWidgets('notes an unavailable source', (tester) async {
    await tester.pumpWidget(host(steam, const []));

    expect(find.textContaining('Reddit data unavailable'), findsOneWidget);
  });
}
