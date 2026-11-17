import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'comments/logic/comments_api.dart';
import 'comments/ui/community_tab.dart';
import 'stats/logic/overall.dart';
import 'stats/logic/stats.dart';
import 'stats/logic/twitch.dart';
import 'stats/ui/chart.dart';
import 'stats/ui/numbers.dart';
import 'stats/ui/overall.dart';
import 'stats/ui/twitch_chart.dart';

const proxyUrl = '$apiBaseUrl/api/stats';
const twitchUrl = '$apiBaseUrl/api/twitch';

/// Base URL for the comments API, without a trailing slash.
///
/// Empty by default, which makes [CommentsApi] issue same-origin relative
/// URLs — the production setup, where this server also hosts the built app.
///
/// Under `flutter run -d chrome` the app is served by the Flutter dev server
/// on its own port, a different origin than the API, so a relative URL would
/// hit the dev server and 404. Point it at the proxy instead:
///
///     flutter run -d chrome --web-port=4200 \
///       --dart-define=API_BASE_URL=http://localhost:8080
///
/// The dev web port is pinned so the proxy's `ALLOWED_ORIGIN` can match it.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Viewport width at or above which the app uses the wide layout (left
/// drawer). Narrower screens get the bottom navigation bar.
const wideBreakpoint = 800.0;

/// Loads the stats shown on the page. Injectable so tests can supply fixtures
/// without touching the network.
typedef StatsLoader = Future<List<GameStats>> Function();

/// Loads the Twitch numbers shown on the Twitch and Overall pages. Injectable
/// so tests can supply fixtures without touching the network.
typedef TwitchLoader = Future<List<TwitchStats>> Function();

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Silent vs Non-Silent Protagonist',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.loadStats, this.loadTwitch, this.api});

  /// Overrides how the stats are fetched; null uses the local proxy.
  final StatsLoader? loadStats;

  /// Overrides how the Twitch numbers are fetched; null uses the local proxy.
  final TwitchLoader? loadTwitch;

  /// Overrides the comments client used by the Community tab; null builds a
  /// real same-origin client.
  final CommentsApi? api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _OverallData {
  const _OverallData({required this.steam, required this.twitch});

  final List<GameStats> steam;
  final List<TwitchStats> twitch;
}

class _HomePageState extends State<HomePage> {
  late Future<List<GameStats>> _stats;
  late Future<List<TwitchStats>> _twitch;
  late Future<_OverallData> _overall;
  late final CommentsApi _api = widget.api ?? CommentsApi(baseUrl: apiBaseUrl);

  /// Which destination in the left drawer is showing: 0 chart, 1 numbers,
  /// 2 twitch, 3 overall, 4 community.
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _stats = _load();
    _twitch = _loadTwitch()..ignore();
    _overall = _loadOverall()..ignore();
  }

  Future<List<GameStats>> _load() => (widget.loadStats ?? _loadFromProxy)();

  Future<List<TwitchStats>> _loadTwitch() =>
      (widget.loadTwitch ?? _loadTwitchFromProxy)();

  Future<List<GameStats>> _loadFromProxy() async {
    final response = await http.get(Uri.parse(proxyUrl));
    if (response.statusCode != 200) {
      throw Exception('Proxy returned ${response.statusCode}');
    }
    return parseStatsResponse(response.body);
  }

  Future<List<TwitchStats>> _loadTwitchFromProxy() async {
    final response = await http.get(Uri.parse(twitchUrl));
    if (response.statusCode != 200) {
      throw Exception('Proxy returned ${response.statusCode}');
    }
    return parseTwitchResponse(response.body);
  }

  /// Waits for both sources, keeping whichever side loaded. When neither side
  /// produced a single number, the tab shows its retry panel: an all-dash table
  /// with a "level" verdict would claim a comparison that never happened.
  Future<_OverallData> _loadOverall() async {
    var steam = <GameStats>[];
    var twitch = <TwitchStats>[];
    try {
      steam = await _stats;
    } catch (_) {
      // Leave Steam empty; the page notes it is unavailable.
    }
    try {
      twitch = await _twitch;
    } catch (_) {
      // Leave Twitch empty; the page notes it is unavailable.
    }
    if (!steamHasData(steam) && !twitchHasData(twitch)) {
      throw Exception('Both stats sources are unavailable.');
    }
    return _OverallData(steam: steam, twitch: twitch);
  }

  void _refresh() => setState(() {
        _stats = _load();
        _twitch = _loadTwitch()..ignore();
        _overall = _loadOverall()..ignore();
      });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Silent vs Non-Silent Protagonists'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: isWide ? _buildDrawer(context) : null,
      body: _buildBody(),
      bottomNavigationBar: isWide ? null : _buildBottomNav(context),
    );
  }

  /// The bottom navigation bar shown on narrow screens, mirroring the wide
  /// drawer's destinations.
  Widget _buildBottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) =>
          setState(() => _selectedIndex = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Chart'),
        NavigationDestination(icon: Icon(Icons.tag), label: 'Numbers'),
        NavigationDestination(icon: Icon(Icons.live_tv), label: 'Twitch'),
        NavigationDestination(icon: Icon(Icons.insights), label: 'Overall'),
        NavigationDestination(icon: Icon(Icons.forum), label: 'Community'),
      ],
    );
  }

  /// The destination currently chosen in the drawer. Only this one is built,
  /// matching the old tab behaviour where off-screen tabs did not exist in the
  /// tree.
  Widget _buildBody() {
    switch (_selectedIndex) {
      case 1:
        return _AsyncTab<List<GameStats>>(
          future: _stats,
          onRetry: _refresh,
          builder: (stats) => NumbersComparison(stats: stats),
        );
      case 2:
        return _AsyncTab<List<TwitchStats>>(
          future: _twitch,
          onRetry: _refresh,
          errorMessage: 'Could not load Twitch numbers from /api/twitch.',
          builder: (stats) => TwitchComparison(stats: stats),
        );
      case 3:
        return _AsyncTab<_OverallData>(
          future: _overall,
          onRetry: _refresh,
          errorMessage: 'Could not load either stats source.',
          builder: (data) =>
              OverallComparison(steam: data.steam, twitch: data.twitch),
        );
      case 4:
        return CommunityTab(api: _api);
      default:
        return _AsyncTab<List<GameStats>>(
          future: _stats,
          onRetry: _refresh,
          builder: (stats) => ComparisonChart(stats: stats),
        );
    }
  }

  /// The left navigation drawer. Choosing an entry switches the shown
  /// destination and closes the drawer.
  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Silent vs Non-Silent',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          _DrawerEntry(
            icon: Icons.bar_chart,
            label: 'Chart',
            selected: _selectedIndex == 0,
            onTap: () => _select(0, context),
          ),
          _DrawerEntry(
            icon: Icons.tag,
            label: 'Numbers',
            selected: _selectedIndex == 1,
            onTap: () => _select(1, context),
          ),
          _DrawerEntry(
            icon: Icons.live_tv,
            label: 'Twitch',
            selected: _selectedIndex == 2,
            onTap: () => _select(2, context),
          ),
          _DrawerEntry(
            icon: Icons.insights,
            label: 'Overall',
            selected: _selectedIndex == 3,
            onTap: () => _select(3, context),
          ),
          _DrawerEntry(
            icon: Icons.forum,
            label: 'Community',
            selected: _selectedIndex == 4,
            onTap: () => _select(4, context),
          ),
        ],
      ),
    );
  }

  void _select(int index, BuildContext context) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context);
  }
}

/// A single row in the navigation drawer.
class _DrawerEntry extends StatelessWidget {
  const _DrawerEntry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Renders [builder] with the loaded value, or this tab's own loading/error
/// state derived from [future]. Keeping the state per-tab lets the Community
/// tab stay reachable even when the stats load fails.
class _AsyncTab<T> extends StatelessWidget {
  const _AsyncTab({
    required this.future,
    required this.onRetry,
    required this.builder,
    this.errorMessage = 'Could not reach the local proxy.',
  });

  final Future<T> future;
  final VoidCallback onRetry;
  final Widget Function(T value) builder;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(errorMessage),
                const SizedBox(height: 8),
                Text(
                  'Start it with: dart run bin/server.dart',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final value = snapshot.data;
        if (value == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return builder(value);
      },
    );
  }
}
