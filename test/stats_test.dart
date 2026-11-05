import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats.dart';

void main() {
  group('parseCurrentPlayers', () {
    test('reads player_count from a real Steam response', () {
      // Real fixture captured from the Steam Web API for GTA V (appid 271590).
      const body = '{"response":{"player_count":24930,"result":1}}';
      expect(parseCurrentPlayers(body), 24930);
    });

    test('reads a different player_count (not a constant)', () {
      // Real fixture for Dark Souls Remastered (appid 570940).
      const body = '{"response":{"player_count":1828,"result":1}}';
      expect(parseCurrentPlayers(body), 1828);
    });

    test('throws when Steam omits player_count (invalid appid)', () {
      // Steam returns this shape when the appid has no stats.
      const body = '{"response":{"result":42}}';
      expect(() => parseCurrentPlayers(body), throwsA(isA<Exception>()));
    });
  });

  group('parseSteamChartsAvg', () {
    // Real structure captured from steamcharts.com/app/<id>: the "Last 30 Days"
    // row holds Avg. Players in the td.num-f cell. A decoy monthly row sits
    // above it so a parser that grabs the first num-f fails.
    const html = '''
      <table class="common-table">
        <thead><tr><th>Month</th><th>Avg. Players</th><th>Gain</th><th>% Gain</th><th>Peak Players</th></tr></thead>
        <tbody>
          <tr>
            <td class="month-cell left">September 2026</td>
            <td class="right num-f">50000.00</td>
            <td class="right num-p gainorloss">-36.3</td>
            <td class="right gainorloss">-0.08%</td>
            <td class="right num">79877</td>
          </tr>
          <tr>
            <td class="month-cell left italic">Last 30 Days</td>
            <td class="right num-f italic">47137.17</td>
            <td class="right num-p gainorloss italic">-36.3</td>
            <td class="right gainorloss italic">-0.08%</td>
            <td class="right num italic">79877</td>
          </tr>
        </tbody>
      </table>
      ''';

    test('reads the Last 30 Days average, not a decoy month', () {
      expect(parseSteamChartsAvg(html), 47137.17);
    });

    test('reads a different average (not a constant)', () {
      const other = '''
        <table><tbody>
        <tr><td class="month-cell left italic">Last 30 Days</td>
        <td class="right num-f italic">22428.18</td></tr>
        </tbody></table>
        ''';
      expect(parseSteamChartsAvg(other), 22428.18);
    });

    test('throws when there is no Last 30 Days row', () {
      const noRow = '<table><tr><td class="month-cell left">August 2026</td>'
          '<td class="right num-f">123.0</td></tr></table>';
      expect(() => parseSteamChartsAvg(noRow), throwsA(isA<Exception>()));
    });
  });

  group('games', () {
    test('has fifteen games on each side of the spectrum', () {
      final silent = games.where((g) => g.camp == Camp.silent);
      final nonSilent = games.where((g) => g.camp == Camp.nonSilent);

      expect(silent, hasLength(15));
      expect(nonSilent, hasLength(15));
    });

    test('every game has a unique, positive Steam appid', () {
      final appids = games.map((g) => g.appid).toList();

      expect(appids.every((id) => id > 0), isTrue);
      expect(appids.toSet(), hasLength(games.length));
    });
  });

  group('parseStatsResponse', () {
    test('rebuilds every game, keeping missing numbers null', () {
      const body = '['
          '{"name":"GTA V","camp":"nonSilent","appid":271590,'
          '"current":24649,"avg30d":47137.17},'
          '{"name":"God of War","camp":"nonSilent","appid":1593500,'
          '"current":null,"avg30d":null}'
          ']';

      final result = parseStatsResponse(body);

      expect(result, hasLength(2));
      expect(result.first.name, 'GTA V');
      expect(result.first.camp, Camp.nonSilent);
      expect(result.first.appid, 271590);
      expect(result.first.current, 24649);
      expect(result.first.avg30d, 47137.17);
      expect(result[1].name, 'God of War');
      expect(result[1].current, isNull);
      expect(result[1].avg30d, isNull);
    });
  });
}
