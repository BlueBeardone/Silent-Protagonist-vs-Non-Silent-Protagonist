import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/chart.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats.dart';

void main() {
  Widget host(List<GameStats> stats) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: ComparisonChart(stats: stats),
          ),
        ),
      );

  testWidgets('labels every game it is given', (tester) async {
    await tester.pumpWidget(host(const [
      GameStats(
          name: 'Elden Ring',
          camp: Camp.silent,
          appid: 1245620,
          current: 15269,
          avg30d: 22428.18),
      GameStats(
          name: 'GTA V',
          camp: Camp.nonSilent,
          appid: 271590,
          current: 24649,
          avg30d: 47137.17),
    ]));

    expect(find.text('Elden Ring'), findsOneWidget);
    expect(find.text('GTA V'), findsOneWidget);
  });

  testWidgets('shows a bar for current, 30-day, and six-month values',
      (tester) async {
    await tester.pumpWidget(host(const [
      GameStats(
          name: 'Valheim',
          camp: Camp.silent,
          appid: 892970,
          current: 1000,
          avg30d: 2000,
          avg6m: 3000),
    ]));

    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('2,000'), findsOneWidget);
    expect(find.text('3,000'), findsOneWidget);
  });

  testWidgets('shows a dash for each metric that could not be fetched',
      (tester) async {
    await tester.pumpWidget(host(const [
      GameStats(
          name: 'God of War',
          camp: Camp.nonSilent,
          appid: 1593500,
          current: null,
          avg30d: 2100.0,
          avg6m: null),
    ]));

    // current and avg6m failed; only avg30d fetched, so two dashes.
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('2,100'), findsOneWidget);
  });
}
