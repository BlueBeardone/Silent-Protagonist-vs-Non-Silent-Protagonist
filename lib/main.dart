import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'comments/logic/comments_api.dart';
import 'comments/ui/community_tab.dart';
import 'stats/logic/stats.dart';
import 'stats/ui/chart.dart';
import 'stats/ui/numbers.dart';

/// Where the local proxy serves the combined numbers.
const proxyUrl = 'http://localhost:8080/api/stats';

/// Loads the stats shown on the page. Injectable so tests can supply fixtures
/// without touching the network.
typedef StatsLoader = Future<List<GameStats>> Function();

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
  const HomePage({super.key, this.loadStats, this.api});

  /// Overrides how the stats are fetched; null uses the local proxy.
  final StatsLoader? loadStats;

  /// Overrides the comments client used by the Community tab; null builds a
  /// real same-origin client.
  final CommentsApi? api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<GameStats>> _stats;
  late final CommentsApi _api = widget.api ?? CommentsApi();

  @override
  void initState() {
    super.initState();
    _stats = _load();
  }

  Future<List<GameStats>> _load() => (widget.loadStats ?? _loadFromProxy)();

  Future<List<GameStats>> _loadFromProxy() async {
    final response = await http.get(Uri.parse(proxyUrl));
    if (response.statusCode != 200) {
      throw Exception('Proxy returned ${response.statusCode}');
    }
    return parseStatsResponse(response.body);
  }

  void _refresh() => setState(() => _stats = _load());

  @override
  Widget build(BuildContext context) {
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
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Chart'),
                Tab(text: 'Numbers'),
                Tab(text: 'Community'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _StatsTab(
                    stats: _stats,
                    onRetry: _refresh,
                    builder: (stats) => Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Current players (solid) vs 30-day (light) vs 6-month (lightest)',
                            style:
                                TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ),
                        Expanded(child: ComparisonChart(stats: stats)),
                      ],
                    ),
                  ),
                  _StatsTab(
                    stats: _stats,
                    onRetry: _refresh,
                    builder: (stats) => NumbersComparison(stats: stats),
                  ),
                  CommunityTab(api: _api),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders [builder] with the loaded stats, or this tab's own loading/error
/// state derived from [stats]. Keeping the state per-tab lets the Community
/// tab stay reachable even when the stats load fails.
class _StatsTab extends StatelessWidget {
  const _StatsTab({
    required this.stats,
    required this.onRetry,
    required this.builder,
  });

  final Future<List<GameStats>> stats;
  final VoidCallback onRetry;
  final Widget Function(List<GameStats> stats) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GameStats>>(
      future: stats,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not reach the local proxy.'),
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
        return builder(snapshot.data!);
      },
    );
  }
}
