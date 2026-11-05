import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'chart.dart';
import 'stats.dart';

/// Where the local proxy serves the combined numbers.
const proxyUrl = 'http://localhost:8080/api/stats';

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
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<GameStats>> _stats;

  @override
  void initState() {
    super.initState();
    _stats = _load();
  }

  Future<List<GameStats>> _load() async {
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
      body: FutureBuilder<List<GameStats>>(
        future: _stats,
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
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Current players (solid) vs 30-day average (light)',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              Expanded(child: ComparisonChart(stats: snapshot.data!)),
            ],
          );
        },
      ),
    );
  }
}
