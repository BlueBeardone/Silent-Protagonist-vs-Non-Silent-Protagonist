import 'dart:convert';

import 'comparison.dart';
import 'stats.dart';

/// Twitch's public numbers for one game's category.
///
/// These are audience numbers outside the game itself: how many channels are
/// live and how many people are watching them right now.
class TwitchStats {
  const TwitchStats({
    required this.name,
    required this.camp,
    required this.appid,
    required this.category,
    this.channels,
    this.viewers,
  });

  final String name;
  final Camp camp;
  final int appid;

  /// The Twitch category the game streams under.
  final String category;

  /// Live channels; null when the lookup failed.
  final int? channels;

  /// Viewers summed across those live channels; null when the lookup failed.
  final int? viewers;

  Map<String, dynamic> toJson() => {
        'name': name,
        'camp': camp.name,
        'appid': appid,
        'category': category,
        'channels': channels,
        'viewers': viewers,
      };
}

/// One page of a Twitch `/streams` listing.
class TwitchStreamsPage {
  const TwitchStreamsPage({
    required this.channels,
    required this.viewers,
    this.cursor,
  });

  final int channels;
  final int viewers;

  /// The cursor for the next page, or null on the last page.
  final String? cursor;
}

/// Reads the category id from a `/helix/games` body, or null when Twitch has
/// no category with that name.
String? parseTwitchGameId(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return null;
  final data = decoded['data'];
  if (data is! List || data.isEmpty) return null;
  final first = data.first;
  if (first is! Map<String, dynamic>) return null;
  final id = first['id'];
  return id is String && id.isNotEmpty ? id : null;
}

/// Counts the live channels and sums their viewers on one `/streams` page.
///
/// A page with an empty `data` array is a real zero. A body without one is
/// malformed, so it throws: turning that into zero would count a failed
/// lookup as evidence that nothing is live.
TwitchStreamsPage parseTwitchStreamsPage(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Twitch streams response was not an object: $body');
  }
  final data = decoded['data'];
  if (data is! List) {
    throw FormatException('Twitch streams response had no data list: $body');
  }
  var channels = 0;
  var viewers = 0;
  for (final stream in data) {
    if (stream is! Map<String, dynamic>) {
      throw FormatException('Twitch stream entry was not an object: $body');
    }
    final count = stream['viewer_count'];
    if (count is! int) {
      throw FormatException('Twitch stream had no viewer_count: $body');
    }
    channels++;
    viewers += count;
  }
  final pagination = decoded['pagination'];
  final cursor =
      pagination is Map<String, dynamic> ? pagination['cursor'] : null;
  return TwitchStreamsPage(
    channels: channels,
    viewers: viewers,
    cursor: cursor is String && cursor.isNotEmpty ? cursor : null,
  );
}

/// Rebuilds the games from the proxy's `/api/twitch` JSON body.
List<TwitchStats> parseTwitchResponse(String body) {
  final decoded = jsonDecode(body) as List<dynamic>;
  return [
    for (final item in decoded.cast<Map<String, dynamic>>())
      TwitchStats(
        name: item['name'] as String,
        camp: Camp.values.byName(item['camp'] as String),
        appid: item['appid'] as int,
        category: item['category'] as String,
        channels: item['channels'] as int?,
        viewers: item['viewers'] as int?,
      ),
  ];
}

/// The two numbers we compare for each Twitch category.
enum TwitchMetric { viewers, channels }

/// Picks a game's value for [metric], or null when that lookup failed.
double? twitchMetricValue(TwitchStats game, TwitchMetric metric) =>
    switch (metric) {
      TwitchMetric.viewers => game.viewers?.toDouble(),
      TwitchMetric.channels => game.channels?.toDouble(),
    };

/// Human-readable name for a Twitch metric.
String twitchMetricLabel(TwitchMetric metric) => switch (metric) {
      TwitchMetric.viewers => 'Live viewers',
      TwitchMetric.channels => 'Live channels',
    };

/// One [Comparison] per Twitch metric, totalled across every game.
List<Comparison> summarizeTwitch(List<TwitchStats> stats) => [
      for (final metric in TwitchMetric.values)
        compareValues(
          label: twitchMetricLabel(metric),
          silent: [
            for (final game in stats)
              if (game.camp == Camp.silent) ?twitchMetricValue(game, metric),
          ],
          nonSilent: [
            for (final game in stats)
              if (game.camp == Camp.nonSilent)
                ?twitchMetricValue(game, metric),
          ],
        ),
    ];

/// The Twitch category for each game, keyed by Steam appid.
///
/// Twitch names its categories itself, so a few differ from the Steam title
/// (Skyrim Special Edition streams under the base game, for example). A name
/// Twitch does not recognise resolves to no category and the game dashes.
const Map<int, String> twitchCategories = {
  // Silent / self-insert.
  570940: 'Dark Souls: Remastered',
  1245620: 'Elden Ring',
  374320: 'Dark Souls III',
  582010: 'Monster Hunter: World',
  489830: 'The Elder Scrolls V: Skyrim',
  22380: 'Fallout: New Vegas',
  413150: 'Stardew Valley',
  105600: 'Terraria',
  892970: 'Valheim',
  346110: 'ARK: Survival Evolved',
  252490: 'Rust',
  238960: 'Path of Exile',
  230410: 'Warframe',
  275850: 'No Man\'s Sky',
  435150: 'Divinity: Original Sin 2',

  // Non-silent: an authored protagonist whose story you follow.
  271590: 'Grand Theft Auto V',
  1593500: 'God of War',
  292030: 'The Witcher 3: Wild Hunt',
  1174180: 'Red Dead Redemption 2',
  812140: 'Assassin\'s Creed Odyssey',
  582160: 'Assassin\'s Creed Origins',
  976730: 'Halo: The Master Chief Collection',
  883710: 'Resident Evil 2',
  524220: 'NieR:Automata',
  1151640: 'Horizon Zero Dawn',
  1817070: 'Marvel\'s Spider-Man Remastered',
  1888930: 'The Last of Us Part I',
  1172380: 'Star Wars Jedi: Fallen Order',
  391220: 'Rise of the Tomb Raider',
  2215430: 'Ghost of Tsushima',
};
