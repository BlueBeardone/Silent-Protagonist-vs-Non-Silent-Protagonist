import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';

void main() {
  test('reads a category id from a games response', () {
    expect(
      parseTwitchGameId('{"data":[{"id":"21779","name":"Elden Ring"}]}'),
      '21779',
    );
  });

  test('a games response with no match has no id', () {
    expect(parseTwitchGameId('{"data":[]}'), isNull);
    expect(parseTwitchGameId('{"data":[{"name":"x"}]}'), isNull);
  });

  test('counts live channels and sums their viewers', () {
    const body = '{"data":[{"viewer_count":1000},{"viewer_count":250},'
        '{"viewer_count":3}],"pagination":{"cursor":"abc"}}';
    final page = parseTwitchStreamsPage(body);
    expect(page.channels, 3);
    expect(page.viewers, 1253);
    expect(page.cursor, 'abc');
  });

  test('an empty stream page is zero channels and viewers', () {
    final page = parseTwitchStreamsPage('{"data":[]}');
    expect(page.channels, 0);
    expect(page.viewers, 0);
    expect(page.cursor, isNull);
  });

  test('a stream page with no data object is treated as empty', () {
    final page = parseTwitchStreamsPage('{}');
    expect(page.channels, 0);
    expect(page.viewers, 0);
  });

  test('parses a proxy response including nulls', () {
    final stats = parseTwitchResponse(
        '[{"name":"Elden Ring","camp":"silent","appid":1245620,'
        '"category":"Elden Ring","channels":12,"viewers":3456},'
        '{"name":"GTA V","camp":"nonSilent","appid":271590,'
        '"category":"Grand Theft Auto V","channels":null,"viewers":null}]');
    expect(stats, hasLength(2));
    expect(stats[0].viewers, 3456);
    expect(stats[1].channels, isNull);
  });

  test('every game has exactly one Twitch category', () {
    expect(twitchCategories.keys.toSet(), games.map((g) => g.appid).toSet());
    expect(twitchCategories.values.every((c) => c.isNotEmpty), isTrue);
  });

  test('maps representative games to their categories', () {
    expect(twitchCategories[1245620], 'Elden Ring');
    expect(twitchCategories[271590], 'Grand Theft Auto V');
  });

  test('maps Twitch metrics to their fields and labels', () {
    const game = TwitchStats(
        name: 'E',
        camp: Camp.silent,
        appid: 1,
        category: 'E',
        channels: 3,
        viewers: 40);
    expect(twitchMetricValue(game, TwitchMetric.channels), 3);
    expect(twitchMetricValue(game, TwitchMetric.viewers), 40);
    expect(twitchMetricLabel(TwitchMetric.viewers), 'Live viewers');
    expect(twitchMetricLabel(TwitchMetric.channels), 'Live channels');
  });

  test('summarizeTwitch skips nulls and totals per camp', () {
    final summaries = summarizeTwitch(const [
      TwitchStats(
          name: 'a',
          camp: Camp.silent,
          appid: 1,
          category: 'a',
          channels: 2,
          viewers: 100),
      TwitchStats(
          name: 'b',
          camp: Camp.silent,
          appid: 2,
          category: 'b',
          channels: null,
          viewers: 50),
      TwitchStats(
          name: 'c',
          camp: Camp.nonSilent,
          appid: 3,
          category: 'c',
          channels: 5,
          viewers: null),
    ]);
    expect(summaries[0].label, 'Live viewers');
    expect(summaries[0].silentTotal, 150);
    expect(summaries[0].silentCount, 2);
    expect(summaries[0].nonSilentCount, 0);
    expect(summaries[1].silentCount, 1);
    expect(summaries[1].nonSilentTotal, 5);
  });
}
