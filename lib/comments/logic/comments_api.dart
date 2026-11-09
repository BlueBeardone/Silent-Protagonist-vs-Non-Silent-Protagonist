import 'dart:convert';

import 'package:http/http.dart' as http;

import 'comments.dart';

/// A thin HTTP client for the community-comments API.
///
/// Both calls go through a single [http.Client] so callers can inject a mock
/// (see `package:http/testing.dart`) or share connection pooling. Every
/// request is JSON and any non-2xx response throws, so a caller can rely on a
/// returned [Comment] or a thrown error — never a silent failure.
class CommentsApi {
  /// Creates a client that talks to [baseUrl].
  ///
  /// [baseUrl] defaults to the empty string, which produces same-origin
  /// relative URLs (`/api/comments`) — the production setup. [client] defaults
  /// to a fresh [http.Client]; inject one to control the transport in tests.
  CommentsApi({this.baseUrl = '', http.Client? client})
      : _client = client ?? http.Client();

  /// Origin the API lives at, with no trailing slash (for example
  /// `http://localhost:8080`).
  final String baseUrl;

  final http.Client _client;

  /// Posts a new comment and returns the server's stored view of it.
  ///
  /// The full [email] is sent; the server stores it and echoes back only the
  /// masked form, which is what the returned [Comment] carries.
  Future<Comment> post({
    required String email,
    required String comment,
    String? turnstileToken,
    String? website,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/comments'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'comment': comment,
        'turnstileToken': ?turnstileToken,
        'website': ?website,
      }),
    );
    _ensureSuccess(response, 'POST');
    return _commentFromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Lists comments newest-first, up to [limit].
  ///
  /// When [before] is given (an ISO-8601 timestamp, typically a previous
  /// response's `nextCursor`), only comments strictly older than it are
  /// returned. The server wraps the results in a `{"comments": [...],
  /// "nextCursor": ...}` envelope; only `comments` is unwrapped here.
  Future<List<Comment>> list({int limit = 50, String? before}) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) query['before'] = before;
    final uri = Uri.parse('$baseUrl/api/comments')
        .replace(queryParameters: query);
    final response = await _client.get(uri);
    _ensureSuccess(response, 'GET');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final comments = body['comments'] as List<dynamic>;
    return [
      for (final comment in comments)
        _commentFromJson(comment as Map<String, dynamic>),
    ];
  }

  /// Lists every comment, newest first.
  ///
  /// The server pages its results, so this walks the cursor: each request asks
  /// for up to [pageSize] comments starting just older than the previous
  /// page's last entry, and stops when a page comes back shorter than
  /// [pageSize] (including empty). [pageSize] is capped at 100 by the server;
  /// values above that simply make the final short page smaller.
  Future<List<Comment>> listAll({int pageSize = 100}) async {
    final all = <Comment>[];
    String? before;
    while (true) {
      final page = await list(limit: pageSize, before: before);
      all.addAll(page);
      if (page.length < pageSize) break;
      before = page.last.createdAt.toUtc().toIso8601String();
    }
    return all;
  }

  /// Throws a descriptive [http.ClientException] when [response] is not 2xx.
  void _ensureSuccess(http.Response response, String method) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw http.ClientException(
      '$method /api/comments failed with HTTP ${response.statusCode}',
    );
  }

  /// Rebuilds a [Comment] from the server's JSON view of one.
  Comment _commentFromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        email: json['email'] as String,
        comment: json['comment'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
