import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:silent_protagonist_vs_non_silent_protagonist/server.dart';

Future<void> main() async {
  final server = await shelf_io.serve(
    statsHandler(fetchLiveStats),
    InternetAddress.loopbackIPv4,
    8080,
  );
  stdout.writeln('Proxy listening on http://localhost:${server.port}');
}
