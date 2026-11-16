import 'dart:convert';

import 'stats.dart';

/// Reddit's public numbers for one game's subreddit.
class RedditStats {
  const RedditStats({
    required this.name,
    required this.camp,
    required this.appid,
    required this.subreddit,
    this.online,
    this.members,
  });

  final String name;
  final Camp camp;
  final int appid;
  final String subreddit;

  /// `active_user_count`; null when the lookup failed.
  final int? online;

  /// `subscribers`; null when the lookup failed.
  final int? members;

  Map<String, dynamic> toJson() => {
        'name': name,
        'camp': camp.name,
        'appid': appid,
        'subreddit': subreddit,
        'online': online,
        'members': members,
      };
}

/// One subreddit lookup's parsed values.
class RedditAbout {
  const RedditAbout({required this.online, required this.members});

  final int online;
  final int members;
}

/// Parses a Reddit `/about.json` body.
///
/// Throws [FormatException] when the `data.active_user_count` /
/// `data.subscribers` shape is missing.
RedditAbout parseRedditAbout(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Reddit response was not a JSON object: $body');
  }
  final data = decoded['data'];
  if (data is! Map<String, dynamic>) {
    throw FormatException('Reddit response had no data object: $body');
  }
  final online = data['active_user_count'];
  final members = data['subscribers'];
  if (online is! int || members is! int) {
    throw FormatException(
      'Reddit response had no active_user_count/subscribers: $body',
    );
  }
  return RedditAbout(online: online, members: members);
}

/// Rebuilds the games from the proxy's `/api/reddit` JSON body.
List<RedditStats> parseRedditResponse(String body) {
  final decoded = jsonDecode(body) as List<dynamic>;
  return [
    for (final item in decoded.cast<Map<String, dynamic>>())
      RedditStats(
        name: item['name'] as String,
        camp: Camp.values.byName(item['camp'] as String),
        appid: item['appid'] as int,
        subreddit: item['subreddit'] as String,
        online: item['online'] as int?,
        members: item['members'] as int?,
      ),
  ];
}

/// The subreddit for each game, keyed by Steam appid.
///
/// Where a game shares a franchise subreddit with other games, the shared
/// subreddit is used as-is: the comparison is audience size, not per-title
/// isolation.
const Map<int, String> subreddits = {
  // Silent / self-insert.
  570940: 'darksouls',
  1245620: 'Eldenring',
  374320: 'darksouls3',
  582010: 'MonsterHunterWorld',
  489830: 'skyrim',
  22380: 'fnv',
  413150: 'StardewValley',
  105600: 'Terraria',
  892970: 'valheim',
  346110: 'ARK',
  252490: 'playrust',
  238960: 'pathofexile',
  230410: 'Warframe',
  275850: 'NoMansSkyTheGame',
  435150: 'DivinityOriginalSin',

  // Non-silent: an authored protagonist whose story you follow.
  271590: 'GTAV',
  1593500: 'GodofWar',
  292030: 'witcher',
  1174180: 'reddeadredemption',
  812140: 'AssassinsCreedOdyssey',
  582160: 'AssassinsCreedOrigins',
  976730: 'halo',
  883710: 'residentevil',
  524220: 'nier',
  1151640: 'horizon',
  1817070: 'SpidermanPS4',
  1888930: 'thelastofus',
  1172380: 'FallenOrder',
  391220: 'TombRaider',
  2215430: 'ghostoftsushima',
};
