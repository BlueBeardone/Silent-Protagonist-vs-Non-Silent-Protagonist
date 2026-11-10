import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/numbers.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

void main() {
  Widget host(List<GameStats> stats, {double width = 1000}) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
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
      peakAllTime: 1000,
    ),
    GameStats(
      name: 'God of War',
      camp: Camp.nonSilent,
      appid: 2,
      current: 100,
      avg30d: 200,
      avg6m: 300,
      peakAllTime: 200,
    ),
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

    testWidgets('shows a dash for every metric that could not be fetched', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const [
          GameStats(
            name: 'God of War',
            camp: Camp.nonSilent,
            appid: 2,
            current: null,
            avg30d: 200,
            avg6m: null,
          ),
        ]),
      );

      // current and avg6m failed; those cells render as dashes.
      expect(find.text('—'), findsWidgets);
      expect(find.text('200'), findsWidgets);
    });

    testWidgets('shows a subtotal and average row for each camp', (
      tester,
    ) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Silent total'), findsOneWidget);
      expect(find.text('Silent average'), findsOneWidget);
      expect(find.text('Non-silent total'), findsOneWidget);
      expect(find.text('Non-silent average'), findsOneWidget);
    });

    testWidgets('names the more popular side at the bottom', (tester) async {
      await tester.pumpWidget(host(sample));

      expect(
        find.text('Silent games are more popular overall'),
        findsOneWidget,
      );
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

    testWidgets('shows an all-time peak column with each game\'s record', (
      tester,
    ) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Peak'), findsOneWidget);
      // Elden Ring's record is 1,000 (row, total, and average all show it).
      expect(find.text('1,000'), findsWidgets);
    });

    testWidgets('says both sides are equal on a tie', (tester) async {
      await tester.pumpWidget(
        host(const [
          GameStats(
            name: 'A',
            camp: Camp.silent,
            appid: 1,
            current: 100,
            avg30d: 100,
            avg6m: 100,
          ),
          GameStats(
            name: 'B',
            camp: Camp.nonSilent,
            appid: 2,
            current: 100,
            avg30d: 100,
            avg6m: 100,
          ),
        ]),
      );

      expect(find.text('Both sides are equally popular'), findsOneWidget);
      expect(find.textContaining('Deciding factor'), findsOneWidget);
    });

    testWidgets('on a narrow view shows only the 30-day column', (
      tester,
    ) async {
      await tester.pumpWidget(host(sample, width: 700));

      expect(find.text('30-day'), findsOneWidget);
      expect(find.text('Current'), findsNothing);
      expect(find.text('6-month'), findsNothing);
      expect(find.text('Peak'), findsNothing);
      expect(find.text('Current players'), findsNothing);
      expect(find.text('Camp'), findsNothing);
    });

    testWidgets('tapping a game row reveals the other statistics', (
      tester,
    ) async {
      await tester.pumpWidget(host(sample, width: 700));

      await tester.tap(find.text('Elden Ring'));
      await tester.pumpAndSettle();

      expect(find.text('Current players'), findsOneWidget);
      expect(find.text('6-month average'), findsOneWidget);
      expect(find.text('All-time peak'), findsOneWidget);
      expect(find.text('900'), findsOneWidget);
      expect(find.text('700'), findsOneWidget);
      expect(find.text('1,000'), findsOneWidget);
    });

    testWidgets('tapping an expanded row again collapses it', (tester) async {
      await tester.pumpWidget(host(sample, width: 700));

      await tester.tap(find.text('Elden Ring'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elden Ring'));
      await tester.pumpAndSettle();

      expect(find.text('Current players'), findsNothing);
    });

    testWidgets('each game row expands independently', (tester) async {
      await tester.pumpWidget(host(sample, width: 700));

      await tester.tap(find.text('Elden Ring'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('God of War'));
      await tester.tap(find.text('God of War'));
      await tester.pumpAndSettle();

      // Both rows are now expanded, so both sets of values are visible.
      expect(find.text('900'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('offers a filter for all, silent, and non-silent games',
        (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Silent'), findsOneWidget);
      expect(find.text('Non-silent'), findsOneWidget);
    });

    testWidgets('filtering to silent hides non-silent games', (tester) async {
      await tester.pumpWidget(host(sample));

      await tester.tap(find.text('Silent'));
      await tester.pumpAndSettle();

      expect(find.text('Elden Ring'), findsOneWidget);
      expect(find.text('God of War'), findsNothing);
      expect(find.text('Non-silent total'), findsNothing);
      expect(find.text('Non-silent average'), findsNothing);
    });

    testWidgets('filtering to non-silent hides silent games', (tester) async {
      await tester.pumpWidget(host(sample));

      await tester.tap(find.text('Non-silent'));
      await tester.pumpAndSettle();

      expect(find.text('Elden Ring'), findsNothing);
      expect(find.text('God of War'), findsOneWidget);
      expect(find.text('Silent total'), findsNothing);
      expect(find.text('Silent average'), findsNothing);
    });

    testWidgets('the wide table has no camp column', (tester) async {
      await tester.pumpWidget(host(sample));

      expect(find.text('Camp'), findsNothing);
    });

    testWidgets('the compact table has no camp column', (tester) async {
      await tester.pumpWidget(host(sample, width: 700));

      expect(find.text('Camp'), findsNothing);
    });

    testWidgets('hides the verdict when filtered to one camp', (tester) async {
      await tester.pumpWidget(host(sample));

      await tester.tap(find.text('Silent'));
      await tester.pumpAndSettle();

      expect(find.text('Silent games are more popular overall'), findsNothing);
      expect(find.text('Deciding factor: Current players — Silent +800%'),
          findsNothing);
    });
  });
}
