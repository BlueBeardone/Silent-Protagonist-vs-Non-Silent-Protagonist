import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/numbers.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

void main() {
  Widget host(List<GameStats> stats) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: NumbersComparison(stats: stats),
          ),
        ),
      );

  // Silent wins every metric; the relative gaps shrink per metric so the
  // deciding factor is current players.
  const sample = <GameStats>[
    GameStats(
        name: 'Elden Ring',
        camp: Camp.silent,
        appid: 1,
        current: 900,
        avg30d: 800,
        avg6m: 700,
        peakAllTime: 1000),
    GameStats(
        name: 'God of War',
        camp: Camp.nonSilent,
        appid: 2,
        current: 100,
        avg30d: 200,
        avg6m: 300,
        peakAllTime: 200),
  ];

  group('formatPercent', () {
    test('rounds to a whole percentage with a sign-free number', () {
      expect(formatPercent(300.4), '300%');
      expect(formatPercent(66.7), '67%');
    });

    test('shows a dash when there is no percentage', () {
      expect(formatPercent(null), '—');
    });
  });

  group('NumbersComparison', () {
    testWidgets('lists every game it is given', (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Elden Ring'), findsOneWidget);
      expect(find.text('God of War'), findsOneWidget);
    });

    testWidgets('shows a dash for every metric that could not be fetched',
        (tester) async {
      await tester.pumpWidget(host(const [
        GameStats(
            name: 'God of War',
            camp: Camp.nonSilent,
            appid: 2,
            current: null,
            avg30d: 200,
            avg6m: null),
      ]));

      // current and avg6m failed; those cells render as dashes.
      expect(find.text('—'), findsWidgets);
      expect(find.text('200'), findsWidgets);
    });

    testWidgets('shows a subtotal and average row for each camp',
        (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Silent total'), findsOneWidget);
      expect(find.text('Silent average'), findsOneWidget);
      expect(find.text('Non-silent total'), findsOneWidget);
      expect(find.text('Non-silent average'), findsOneWidget);
    });

    testWidgets('names the more popular side at the bottom', (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Silent games are more popular overall'), findsOneWidget);
    });

    testWidgets('names the deciding factor at the bottom', (tester) async {
      await tester.pumpWidget(host(sample));

      expect(
        find.text('Deciding factor: Current players — Silent +800%'),
        findsOneWidget,
      );
    });

    testWidgets('summarises each metric by winner and margin', (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Current players: Silent by 800'), findsOneWidget);
      expect(find.text('30-day average: Silent by 600'), findsOneWidget);
      expect(find.text('6-month average: Silent by 400'), findsOneWidget);
      expect(find.text('All-time peak: Silent by 800'), findsOneWidget);
    });

    testWidgets('shows an all-time peak column with each game\'s record',
        (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Peak'), findsOneWidget);
      // Elden Ring's record is 1,000 (row, total, and average all show it).
      expect(find.text('1,000'), findsWidgets);
    });

    testWidgets('says both sides are equal on a tie', (tester) async {
      await tester.pumpWidget(host(const [
        GameStats(
            name: 'A',
            camp: Camp.silent,
            appid: 1,
            current: 100,
            avg30d: 100,
            avg6m: 100),
        GameStats(
            name: 'B',
            camp: Camp.nonSilent,
            appid: 2,
            current: 100,
            avg30d: 100,
            avg6m: 100),
      ]));

      expect(find.text('Both sides are equally popular'), findsOneWidget);
      expect(find.textContaining('Deciding factor'), findsOneWidget);
    });
  });
}
