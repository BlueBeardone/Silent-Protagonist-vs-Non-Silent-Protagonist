import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/twitch_chart.dart';

void main() {
  const elden = TwitchStats(
      name: 'Elden Ring',
      camp: Camp.silent,
      appid: 1245620,
      category: 'Elden Ring',
      channels: 120,
      viewers: 15269);
  const gta = TwitchStats(
      name: 'GTA V',
      camp: Camp.nonSilent,
      appid: 271590,
      category: 'Grand Theft Auto V',
      channels: 260,
      viewers: 24649);

  Widget host(List<TwitchStats> stats, {double width = 800}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 1200,
            child: TwitchComparison(stats: stats),
          ),
        ),
      );

  testWidgets('labels games and both Twitch metrics', (tester) async {
    await tester.pumpWidget(host(const [elden, gta]));

    expect(find.text('Elden Ring'), findsOneWidget);
    expect(find.text('Live viewers'), findsWidgets);
    expect(find.text('Live channels'), findsWidgets);
    expect(find.text('15,269'), findsOneWidget);
  });

  testWidgets('dashes failed lookups', (tester) async {
    // A second, working game keeps this out of the all-null "unavailable"
    // state the next test covers.
    await tester.pumpWidget(host(const [
      TwitchStats(
          name: 'Broken', camp: Camp.silent, appid: 1, category: 'broken'),
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
      TwitchStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1245620,
          category: 'Elden Ring',
          channels: 300,
          viewers: 30000),
      gta,
    ]));

    expect(find.textContaining('are ahead overall'), findsOneWidget);
  });

  testWidgets('a 1-1 split says both sides are equally active',
      (tester) async {
    await tester.pumpWidget(host(const [
      TwitchStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1,
          category: 'a',
          channels: 100,
          viewers: 1000),
      TwitchStats(
          name: 'GTA V',
          camp: Camp.nonSilent,
          appid: 2,
          category: 'b',
          channels: 10,
          viewers: 5000),
    ]));

    expect(find.text('Both sides are equally active'), findsOneWidget);
  });

  testWidgets('an all-null response shows the unavailable note',
      (tester) async {
    await tester.pumpWidget(host(const [
      TwitchStats(name: 'A', camp: Camp.silent, appid: 1, category: 'a'),
      TwitchStats(name: 'B', camp: Camp.nonSilent, appid: 2, category: 'b'),
    ]));

    expect(find.textContaining('Twitch data unavailable'), findsOneWidget);
  });

  testWidgets('the unavailable note names both credentials', (tester) async {
    await tester.pumpWidget(host(const []));

    expect(find.textContaining('TWITCH_CLIENT_ID'), findsOneWidget);
    expect(find.textContaining('TWITCH_CLIENT_SECRET'), findsOneWidget);
  });

  testWidgets('zero live channels is shown as a real zero', (tester) async {
    await tester.pumpWidget(host(const [
      TwitchStats(
          name: 'Quiet',
          camp: Camp.silent,
          appid: 1,
          category: 'quiet',
          channels: 0,
          viewers: 0),
      gta,
    ]));

    expect(find.textContaining('Twitch data unavailable'), findsNothing);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('a one-sided result is not called a tie', (tester) async {
    // Only the silent camp resolved, so there is nothing to compare against;
    // saying "equally active" would assert a comparison that never happened.
    await tester.pumpWidget(host(const [
      TwitchStats(
          name: 'A',
          camp: Camp.silent,
          appid: 1,
          category: 'a',
          channels: 10,
          viewers: 100),
      TwitchStats(name: 'B', camp: Camp.nonSilent, appid: 2, category: 'b'),
    ]));

    expect(find.text('Not enough Twitch data to compare'), findsOneWidget);
    expect(find.text('Both sides are equally active'), findsNothing);
  });

  testWidgets('a long game name does not overflow a narrow host',
      (tester) async {
    await tester.pumpWidget(host([
      TwitchStats(
          name: 'A very long game name ' * 6,
          camp: Camp.silent,
          appid: 1,
          category: 'a',
          channels: 10,
          viewers: 20),
    ], width: 400));

    expect(tester.takeException(), isNull);
  });
}
