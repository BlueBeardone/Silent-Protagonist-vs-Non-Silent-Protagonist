import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/reddit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

void main() {
  // Real-shaped about.json fixture (fields trimmed to what we read).
  const about = '{"kind":"t5","data":{"active_user_count":15269,'
      '"subscribers":1234567,"display_name":"Eldenring"}}';

  test('reads online and members from an about.json body', () {
    final parsed = parseRedditAbout(about);
    expect(parsed.online, 15269);
    expect(parsed.members, 1234567);
  });

  test('reads different values (not constants)', () {
    final parsed = parseRedditAbout(
        '{"data":{"active_user_count":42,"subscribers":999}}');
    expect(parsed.online, 42);
    expect(parsed.members, 999);
  });

  test('throws when the data fields are missing', () {
    expect(() => parseRedditAbout('{"data":{}}'), throwsFormatException);
    expect(() => parseRedditAbout('{"kind":"t5"}'), throwsFormatException);
  });

  test('parses a proxy response including nulls', () {
    final stats = parseRedditResponse(
        '[{"name":"Elden Ring","camp":"silent","appid":1245620,'
        '"subreddit":"Eldenring","online":15269,"members":1234567},'
        '{"name":"GTA V","camp":"nonSilent","appid":271590,'
        '"subreddit":"GTAV","online":null,"members":null}]');
    expect(stats, hasLength(2));
    expect(stats[0].online, 15269);
    expect(stats[1].members, isNull);
  });

  test('every game has exactly one subreddit', () {
    expect(subreddits.keys.toSet(), games.map((g) => g.appid).toSet());
    expect(subreddits.values.every((s) => s.isNotEmpty), isTrue);
  });

  test('maps representative games to their subreddits', () {
    expect(subreddits[1245620], 'Eldenring');
    expect(subreddits[271590], 'GTAV');
  });
}
