import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/reddit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/reddit_chart.dart';

void main() {
  const elden = RedditStats(
      name: 'Elden Ring',
      camp: Camp.silent,
      appid: 1245620,
      subreddit: 'Eldenring',
      online: 15269,
      members: 1234567);
  const gta = RedditStats(
      name: 'GTA V',
      camp: Camp.nonSilent,
      appid: 271590,
      subreddit: 'GTAV',
      online: 24649,
      members: 987654);

  Widget host(List<RedditStats> stats, {double width = 800}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 1200,
            child: RedditComparison(stats: stats),
          ),
        ),
      );

  testWidgets('labels games and both Reddit metrics', (tester) async {
    await tester.pumpWidget(host(const [elden, gta]));

    expect(find.text('Elden Ring'), findsOneWidget);
    expect(find.text('Online now'), findsWidgets);
    expect(find.text('Total members'), findsWidgets);
    expect(find.text('1,234,567'), findsOneWidget);
  });

  testWidgets('dashes failed lookups', (tester) async {
    // A second, working game keeps this out of the all-null "unavailable"
    // state the next test covers.
    await tester.pumpWidget(host(const [
      RedditStats(
          name: 'Broken', camp: Camp.silent, appid: 1, subreddit: 'broken'),
      gta,
    ]));

    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('camp filter hides the other camp', (tester) async {
    await tester.pumpWidget(host(const [elden, gta]));

    await tester.tap(find.text('Non-silent'));
    await tester.pumpAndSettle();

    expect(find.text('Elden Ring'), findsNothing);
    expect(find.text('GTA V'), findsOneWidget);
  });

  testWidgets('verdict names the leader', (tester) async {
    await tester.pumpWidget(host(const [
      RedditStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1245620,
          subreddit: 'Eldenring',
          online: 30000,
          members: 1234567),
      gta,
    ]));

    expect(find.textContaining('subreddits are ahead overall'), findsOneWidget);
  });

  testWidgets('a 1-1 split says both sides are equally active',
      (tester) async {
    await tester.pumpWidget(host(const [
      RedditStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1,
          subreddit: 'a',
          online: 100,
          members: 1000),
      RedditStats(
          name: 'GTA V',
          camp: Camp.nonSilent,
          appid: 2,
          subreddit: 'b',
          online: 5000,
          members: 10),
    ]));

    expect(find.text('Both sides are equally active'), findsOneWidget);
  });

  testWidgets('an all-null response shows the unavailable note',
      (tester) async {
    await tester.pumpWidget(host(const [
      RedditStats(name: 'A', camp: Camp.silent, appid: 1, subreddit: 'a'),
      RedditStats(name: 'B', camp: Camp.nonSilent, appid: 2, subreddit: 'b'),
    ]));

    expect(find.textContaining('Reddit data unavailable'), findsOneWidget);
  });

  testWidgets('a long game name does not overflow a narrow host',
      (tester) async {
    await tester.pumpWidget(host([
      RedditStats(
          name: 'A very long game name ' * 6,
          camp: Camp.silent,
          appid: 1,
          subreddit: 'a',
          online: 10,
          members: 20),
    ], width: 400));

    expect(tester.takeException(), isNull);
  });
}
