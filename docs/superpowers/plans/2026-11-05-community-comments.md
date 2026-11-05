# Community Comments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let visitors post a free-text comment (email required) that is stored in MongoDB and browse every comment newest-first with each commenter's email masked.

**Architecture:** The existing Dart `shelf` server gains three JSON routes (`POST/GET/DELETE /api/comments`) backed by a `CommentsStore` interface. A `MongoCommentsStore` is the real implementation; an in-memory store keeps the handler tests off the network. The Flutter web app gains a third **Community** tab whose tab shell no longer depends on the Steam stats load.

**Tech Stack:** Dart 3 / Flutter web, `shelf`, `shelf_router`, `mongo_dart`, `shelf_static`, `http`.

**Spec:** `docs/superpowers/specs/2026-11-05-comments-design.md`

## Global Constraints

- Dart SDK `^3.13.0` (existing `pubspec.yaml`). New dependencies: `mongo_dart` and `shelf_static` only.
- Comment: trimmed, required non-empty, 1–2000 characters, control characters stripped except `\n`.
- Email: required, max 254 characters, conservative `local@domain` format.
- Request body limit: 8192 bytes → `413`.
- Rate limits per client IP: writes 5 per 10 minutes, reads 60 per minute → `429`.
- Read list: default `limit` 50, max 100, newest first, opaque `before` cursor.
- Masking: first 3 local characters + `***@domain`; local part of 3 characters or fewer → `***@domain`.
- Secrets from environment: `MONGODB_URI`, `ADMIN_TOKEN`, `ALLOWED_ORIGIN`, `TRUSTED_PROXY_HOPS`. `.env` is gitignored; full emails are never logged.
- Tests run with `flutter test <path>`; lint with `dart analyze`.

## Review Focus

- A short email local part (`ab@x.com`) must not be reconstructable from its masked form — Task 1.
- A body that is not JSON, is missing fields, or carries a non-string field must get `400`, never `500` — Task 4.
- A malformed comment id on `DELETE` must get `404`, never `500` — Task 4.
- A spoofed `X-Forwarded-For` with no trusted proxy configured must not bypass the rate limit — Task 4.
- A comment containing HTML/script markup must round-trip verbatim as inert text — Task 4 (server) and Task 8 (rendered as `Text`).

---

### Task 1: Email masking and input validation

**Files:**
- Create: `lib/comments.dart`
- Test: `test/comments_test.dart`

**Interfaces:**
- Produces:
  - `String maskEmail(String email)`
  - `String? validateEmail(String email)` — null when valid, else a human-readable reason.
  - `String? validateComment(String comment)` — null when valid, else a reason.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments.dart';

void main() {
  group('maskEmail', () {
    test('keeps three local chars and the domain', () {
      expect(maskEmail('barry@gmail.com'), 'bar***@gmail.com');
    });
    test('masks the whole local part when it is three chars or fewer', () {
      expect(maskEmail('ab@x.com'), '***@x.com');
      expect(maskEmail('abc@x.com'), '***@x.com');
    });
    test('keeps sub-addressing out of the visible part', () {
      expect(maskEmail('barry+steam@gmail.com'), 'bar***@gmail.com');
    });
  });

  group('validateEmail', () {
    test('accepts a normal address', () {
      expect(validateEmail('barry@gmail.com'), isNull);
    });
    test('rejects blank, malformed, and over-long addresses', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('nope'), isNotNull);
      expect(validateEmail('${'a' * 250}@x.com'), isNotNull);
    });
  });

  group('validateComment', () {
    test('accepts normal text', () {
      expect(validateComment('I got lost in it for hours'), isNull);
    });
    test('rejects blank and whitespace-only text', () {
      expect(validateComment('   '), isNotNull);
    });
    test('rejects text over 2000 characters', () {
      expect(validateComment('a' * 2001), isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/comments_test.dart`
Expected: FAIL — `comments.dart` has no `maskEmail`.

- [ ] **Step 3: Implement the three functions in `lib/comments.dart`**

`maskEmail` splits on the last `@`; the local part has sub-addressing (`+tag`) stripped before masking. `validateEmail` uses a conservative regex and a 254-char cap. `validateComment` trims, requires non-empty, and caps at 2000 characters.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/comments_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comments.dart test/comments_test.dart
git commit -m "feat: mask emails and validate comment input"
```

---

### Task 2: Comment model, store interface, and in-memory store

**Files:**
- Modify: `lib/comments.dart`
- Test: `test/comments_test.dart`

**Interfaces:**
- Consumes: `maskEmail` (Task 1).
- Produces:
  - `class Comment { final String id; final String email; final String comment; final DateTime createdAt; Comment({required String id, required String email, required String comment, required DateTime createdAt}); Map<String, dynamic> toJson(); }` — `toJson` emits `id`, masked `email`, `comment`, and `createdAt` as a UTC ISO-8601 string.
  - `abstract class CommentsStore { Future<Comment> add({required String email, required String comment}); Future<List<Comment>> recent({int limit = 50, String? before}); Future<bool> deleteById(String id); }`
  - `class InMemoryCommentsStore implements CommentsStore { InMemoryCommentsStore(); }`

- [ ] **Step 1: Write the failing test**

```dart
group('Comment.toJson', () {
  test('emits the masked email, never the full one', () {
    final json = Comment(
      id: '1',
      email: 'barry@gmail.com',
      comment: 'great game',
      createdAt: DateTime.utc(2026, 11, 5, 12),
    ).toJson();
    expect(json['email'], 'bar***@gmail.com');
    expect(json.toString(), isNot(contains('barry@gmail.com')));
    expect(json['createdAt'], '2026-11-05T12:00:00.000Z');
  });
});

group('InMemoryCommentsStore', () {
  test('adds, lists newest-first, and deletes', () async {
    final store = InMemoryCommentsStore();
    final first = await store.add(email: 'a@x.com', comment: 'one');
    await store.add(email: 'b@x.com', comment: 'two');
    final list = await store.recent();
    expect(list.map((c) => c.comment), ['two', 'one']);
    expect(await store.deleteById(first.id), isTrue);
    expect(await store.deleteById(first.id), isFalse);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/comments_test.dart`
Expected: FAIL — no `Comment`.

- [ ] **Step 3: Implement the model, interface, and in-memory store in `lib/comments.dart`**

In-memory store keeps a `List<Comment>`; `add` generates an id from a counter or timestamp, sets `createdAt` to `DateTime.now().toUtc()`, and appends. `recent` sorts by `createdAt` descending and ties broken by insertion order descending, applies `before` (exclusive), and takes `limit`. `deleteById` removes and reports whether anything was removed.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/comments_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comments.dart test/comments_test.dart
git commit -m "feat: add Comment model and in-memory store"
```

---

### Task 3: Per-key sliding-window rate limiter

**Files:**
- Create: `lib/rate_limit.dart`
- Test: `test/rate_limit_test.dart`

**Interfaces:**
- Produces: `class RateLimiter { RateLimiter({required int maxRequests, required Duration window, DateTime Function()? now}); bool allow(String key); }`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/rate_limit.dart';

void main() {
  test('allows up to the limit inside the window, then blocks', () {
    var clock = DateTime.utc(2026, 11, 5, 12);
    final limiter = RateLimiter(
      maxRequests: 2,
      window: const Duration(minutes: 10),
      now: () => clock,
    );
    expect(limiter.allow('ip'), isTrue);
    expect(limiter.allow('ip'), isTrue);
    expect(limiter.allow('ip'), isFalse);
    clock = clock.add(const Duration(minutes: 11));
    expect(limiter.allow('ip'), isTrue);
  });

  test('counts each key separately', () {
    final limiter = RateLimiter(maxRequests: 1, window: const Duration(minutes: 10));
    expect(limiter.allow('a'), isTrue);
    expect(limiter.allow('b'), isTrue);
    expect(limiter.allow('a'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/rate_limit_test.dart`
Expected: FAIL — no `RateLimiter`.

- [ ] **Step 3: Implement `RateLimiter` in `lib/rate_limit.dart`**

Keep `Map<String, List<DateTime>>`; on each call drop timestamps older than `window`, then allow if the remaining count is below `maxRequests`. `now` defaults to `DateTime.now`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/rate_limit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rate_limit.dart test/rate_limit_test.dart
git commit -m "feat: add sliding-window rate limiter"
```

---

### Task 4: Comments HTTP handler

**Files:**
- Modify: `lib/server.dart`
- Test: `test/server_comments_test.dart`

**Interfaces:**
- Consumes: `CommentsStore`, `Comment`, `validateEmail`, `validateComment` (Tasks 1–2); `RateLimiter` (Task 3).
- Produces:
  - `Handler commentsHandler({required CommentsStore store, required RateLimiter writeLimiter, required RateLimiter readLimiter, String? allowedOrigin, String adminToken = '', int trustedProxyHops = 0})`
  - Routes: `POST /api/comments`, `GET /api/comments`, `DELETE /api/comments/<id>`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/rate_limit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/server.dart';

Handler build({String adminToken = 'secret'}) => commentsHandler(
      store: InMemoryCommentsStore(),
      writeLimiter: RateLimiter(maxRequests: 5, window: const Duration(minutes: 10)),
      readLimiter: RateLimiter(maxRequests: 60, window: const Duration(minutes: 1)),
      adminToken: adminToken,
    );

Request post(Object body) => Request(
      'POST',
      Uri.parse('http://localhost/api/comments'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('stores a valid comment and returns the masked email', () async {
    final response = await build()(post({'email': 'barry@gmail.com', 'comment': 'loved it'}));
    expect(response.statusCode, 201);
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(json['email'], 'bar***@gmail.com');
    expect(json.toString(), isNot(contains('barry@gmail.com')));
  });

  test('rejects bad input with 400, never 500', () async {
    final handler = build();
    for (final body in [
      {'comment': 'no email'},
      {'email': 'nope', 'comment': 'x'},
      {'email': 'a@x.com', 'comment': '   '},
      {'email': 'a@x.com', 'comment': 'a' * 2001},
      {'email': 5, 'comment': 'x'},
      {'email': 'a@x.com', 'comment': 'x', r'$where': '1'},
    ]) {
      expect((await handler(post(body))).statusCode, 400, reason: '$body');
    }
  });

  test('rejects a non-JSON body and a wrong content-type', () async {
    final handler = build();
    final bad = await handler(Request('POST', Uri.parse('http://localhost/api/comments'),
        body: 'not json', headers: {'content-type': 'application/json'}));
    expect(bad.statusCode, 400);
    final wrong = await handler(Request('POST', Uri.parse('http://localhost/api/comments'),
        body: '{}', headers: {'content-type': 'text/plain'}));
    expect(wrong.statusCode, 415);
  });

  test('rejects an oversized body with 413', () async {
    final body = jsonEncode({'email': 'a@x.com', 'comment': 'a' * 9000});
    final response = await build()(Request('POST', Uri.parse('http://localhost/api/comments'),
        body: body, headers: {'content-type': 'application/json'}));
    expect(response.statusCode, 413);
  });

  test('lists comments newest-first with masked emails only', () async {
    final handler = build();
    await handler(post({'email': 'a@x.com', 'comment': 'one'}));
    await handler(post({'email': 'barry@gmail.com', 'comment': 'two'}));
    final response = await handler(Request('GET', Uri.parse('http://localhost/api/comments')));
    expect(response.statusCode, 200);
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final comments = json['comments'] as List;
    expect(comments.first['comment'], 'two');
    expect(comments.first['email'], 'bar***@gmail.com');
    expect(response.headers['access-control-allow-origin'], isNotNull);
  });

  test('round-trips HTML markup as inert text', () async {
    final handler = build();
    await handler(post({'email': 'a@x.com', 'comment': '<script>alert(1)</script>'}));
    final response = await handler(Request('GET', Uri.parse('http://localhost/api/comments')));
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect((json['comments'] as List).first['comment'], '<script>alert(1)</script>');
  });

  test('rate limits writes', () async {
    final handler = build();
    for (var i = 0; i < 5; i++) {
      expect((await handler(post({'email': 'a@x.com', 'comment': 'x'}))).statusCode, 201);
    }
    expect((await handler(post({'email': 'a@x.com', 'comment': 'x'}))).statusCode, 429);
  });

  test('ignores a spoofed X-Forwarded-For when no proxy is trusted', () async {
    final handler = build();
    Future<Response> postFrom(String ip) => handler(Request(
          'POST',
          Uri.parse('http://localhost/api/comments'),
          body: jsonEncode({'email': 'a@x.com', 'comment': 'x'}),
          headers: {'content-type': 'application/json', 'x-forwarded-for': ip},
        ));
    for (var i = 0; i < 5; i++) {
      await postFrom('1.1.1.$i');
    }
    expect((await postFrom('2.2.2.2')).statusCode, 429);
  });

  test('delete needs the admin token and 404s a malformed id', () async {
    final handler = build();
    final created = jsonDecode(await (await handler(post({'email': 'a@x.com', 'comment': 'x'})))
        .readAsString()) as Map<String, dynamic>;
    final id = created['id'] as String;
    expect((await handler(Request('DELETE', Uri.parse('http://localhost/api/comments/$id')))).statusCode, 401);
    expect((await handler(Request('DELETE', Uri.parse('http://localhost/api/comments/abc'),
        headers: {'x-admin-token': 'secret'}))).statusCode, 404);
    expect((await handler(Request('DELETE', Uri.parse('http://localhost/api/comments/$id'),
        headers: {'x-admin-token': 'secret'}))).statusCode, 204);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/server_comments_test.dart`
Expected: FAIL — no `commentsHandler`.

- [ ] **Step 3: Implement `commentsHandler` in `lib/server.dart`**

Add a `Router` with the three routes. Read the body only after checking `content-length` against 8192 (413 otherwise) and the `content-type` (415 unless JSON). Parse JSON, require exactly the keys `email` and `comment`, both strings; validate both (400 with the validator's reason). Rate-limit by client IP before doing work. `GET` reads `limit` and `before` query params (cap limit at 100, default 50) and returns `{"comments": [...], "nextCursor": ...}`. `DELETE` checks `x-admin-token` with a constant-time compare (401), then `store.deleteById` (204/404). Add the `access-control-allow-origin` header to every response, including errors, when `allowedOrigin` is set. Resolve the client IP from `request.context['shelf.io.connection_info']`; only read `x-forwarded-for` when `trustedProxyHops > 0`, and then take the hop-th-from-last entry.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/server_comments_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/server.dart test/server_comments_test.dart
git commit -m "feat: add comments HTTP handler"
```

---

### Task 5: MongoDB store

**Files:**
- Modify: `lib/comments.dart`
- Modify: `pubspec.yaml`
- Test: `test/comments_test.dart`

**Interfaces:**
- Consumes: `Comment`, `CommentsStore` (Task 2).
- Produces:
  - `Map<String, dynamic> commentToMongo({required String email, required String comment, required DateTime createdAt})`
  - `Comment commentFromMongo(Map<String, dynamic> doc)`
  - `class MongoCommentsStore implements CommentsStore { MongoCommentsStore(DbCollection comments); static Future<MongoCommentsStore> connect(String uri); }`

- [ ] **Step 1: Write the failing test**

```dart
group('mongo mapping', () {
  test('round-trips a document', () {
    final doc = commentToMongo(
      email: 'barry@gmail.com',
      comment: 'hi',
      createdAt: DateTime.utc(2026, 11, 5, 12),
    );
    final back = commentFromMongo({'_id': 'abc', ...doc});
    expect(back.email, 'barry@gmail.com');
    expect(back.comment, 'hi');
    expect(back.createdAt, DateTime.utc(2026, 11, 5, 12));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/comments_test.dart`
Expected: FAIL — no `commentToMongo`.

- [ ] **Step 3: Implement the mapping and `MongoCommentsStore`**

Add `mongo_dart` to `pubspec.yaml`. `commentToMongo` returns `{'email': ..., 'comment': ..., 'createdAt': ...}`; `commentFromMongo` reads `_id` via `.toString()`, `email`, `comment`, and `createdAt` as a `DateTime`. `MongoCommentsStore` uses `insertOne` with a `createdAt` typed value, `find(where.sortBy('createdAt', descending: true).limit(limit))` for `recent` (applying `where.lt('createdAt', ...)` when `before` is given), and `deleteOne(where.id(ObjectId.fromHexString(id)))` wrapped so a malformed id returns `false`. `connect` opens a `Db`, ensures the `{ createdAt: -1 }` index, and returns the store. No unit test touches Atlas; the mapping is the tested part.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/comments_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comments.dart pubspec.yaml pubspec.lock test/comments_test.dart
git commit -m "feat: add MongoDB comments store"
```

---

### Task 6: Server entrypoint — env, Mongo, static hosting

**Files:**
- Modify: `bin/server.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: `commentsHandler` (Task 4), `MongoCommentsStore` (Task 5), `statsHandler`, `fetchLiveStats` (existing).

- [ ] **Step 1: Wire the entrypoint**

Add `shelf_static` to `pubspec.yaml`. In `bin/server.dart`: read `MONGODB_URI` (fail fast if missing), `ADMIN_TOKEN`, `ALLOWED_ORIGIN`, `TRUSTED_PROXY_HOPS`; connect the `MongoCommentsStore`; build the write and read `RateLimiter`s; serve a `Cascade` that tries the comments and stats routers first and falls back to `createStaticHandler('build/web', defaultDocument: 'index.html')`. Bind `0.0.0.0` and read `$PORT` (default 8080). If Atlas is unreachable at boot, log it and keep serving stats; comments routes return `503` until the store reconnects. Add `.env` to `.gitignore` and commit only a `.env.example` listing the variable names with placeholder values. Never log a full email.

- [ ] **Step 2: Verify it compiles and analyzes**

Run: `dart analyze bin/server.dart`
Expected: No issues.

- [ ] **Step 3: Verify the app still runs without Mongo configured**

Run: `MONGODB_URI= dart run bin/server.dart`
Expected: exits with a clear "MONGODB_URI is required" message and non-zero status.

- [ ] **Step 4: Commit**

```bash
git add bin/server.dart pubspec.yaml pubspec.lock
git commit -m "feat: wire Mongo, env config, and static hosting into the server"
```

---

### Task 7: Flutter comments client

**Files:**
- Create: `lib/comments_api.dart`
- Test: `test/comments_api_test.dart`

**Interfaces:**
- Consumes: `Comment` (Task 2).
- Produces:
  - `class CommentsApi { CommentsApi({String baseUrl = '', http.Client? client}); Future<Comment> post({required String email, required String comment}); Future<List<Comment>> list({int limit = 50, String? before}); }`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments_api.dart';

void main() {
  test('post sends email and comment and parses the reply', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'id': '1', 'email': 'bar***@gmail.com', 'comment': 'hi', 'createdAt': '2026-11-05T12:00:00.000Z'}),
        201,
      );
    });
    final api = CommentsApi(client: client);
    final comment = await api.post(email: 'barry@gmail.com', comment: 'hi');
    expect(jsonDecode(seen.body)['email'], 'barry@gmail.com');
    expect(comment.comment, 'hi');
  });

  test('list parses the comments array', () async {
    final client = MockClient((_) async => http.Response(
      jsonEncode({'comments': [{'id': '1', 'email': '***@x.com', 'comment': 'hi', 'createdAt': '2026-11-05T12:00:00.000Z'}], 'nextCursor': null}),
      200,
    ));
    expect((await CommentsApi(client: client).list()).single.comment, 'hi');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/comments_api_test.dart`
Expected: FAIL — no `CommentsApi`.

- [ ] **Step 3: Implement `CommentsApi` in `lib/comments_api.dart`**

`post` sends a JSON `POST` to `$baseUrl/api/comments`; `list` sends a `GET` with `limit`/`before` query params. Both throw on a non-2xx status; `list` reads `comments` from the envelope.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/comments_api_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/comments_api.dart test/comments_api_test.dart
git commit -m "feat: add Flutter comments API client"
```

---

### Task 8: Community tab UI

**Files:**
- Create: `lib/community_tab.dart`
- Test: `test/community_tab_test.dart`

**Interfaces:**
- Consumes: `CommentsApi` (Task 7), `Comment` (Task 2).
- Produces: `class CommunityTab extends StatefulWidget { const CommunityTab({super.key, required CommentsApi api}); }`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments_api.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/community_tab.dart';

CommentsApi apiReturning(List<Map<String, dynamic>> comments) => CommentsApi(
      client: MockClient((_) async => http.Response(jsonEncode({'comments': comments}), 200)),
    );

void main() {
  testWidgets('rejects a blank email', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommunityTab(api: apiReturning([])))));
    await tester.enterText(find.byKey(const Key('comment')), 'nice');
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(find.textContaining('email'), findsWidgets);
  });

  testWidgets('shows comments with masked emails behind the button', (tester) async {
    final api = apiReturning([
      {'id': '1', 'email': 'bar***@gmail.com', 'comment': 'immersive', 'createdAt': '2026-11-05T12:00:00.000Z'},
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommunityTab(api: api))));
    await tester.tap(find.text('See what others said'));
    await tester.pumpAndSettle();
    expect(find.text('immersive'), findsOneWidget);
    expect(find.text('bar***@gmail.com'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/community_tab_test.dart`
Expected: FAIL — no `CommunityTab`.

- [ ] **Step 3: Implement `CommunityTab` in `lib/community_tab.dart`**

A `TextField` (key `comment`) for the comment, a `TextField` (key `email`) for the email, a `Post` button that validates locally (email non-empty, comment non-empty) then calls `api.post`, and a `See what others said` button that calls `api.list` and renders each comment as a `ListTile` with the comment text and masked email (both plain `Text` widgets). Show a progress indicator while loading and a message on failure.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/community_tab_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/community_tab.dart test/community_tab_test.dart
git commit -m "feat: add Community tab UI"
```

---

### Task 9: Make the tab shell independent of the stats load

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/home_tabs_test.dart`

**Interfaces:**
- Consumes: `CommunityTab` (Task 8).

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('Community tab is reachable even when stats fail', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: HomePage(loadStats: () async => throw Exception('steam down')),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Community'), findsOneWidget);
  await tester.tap(find.text('Community'));
  await tester.pumpAndSettle();
  expect(find.text('Post'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/home_tabs_test.dart`
Expected: FAIL — no Community tab.

- [ ] **Step 3: Restructure `HomePage` in `lib/main.dart`**

Move the `DefaultTabController`/`TabBar`/`TabBarView` outside the stats `FutureBuilder` so it always renders. Give it three tabs: Chart, Numbers, Community. The Chart and Numbers tabs keep their existing content but render their own loading/error state from `_stats`; Community renders `CommunityTab`. `HomePage` gains an optional `CommentsApi? api` parameter (defaulting to a real `CommentsApi`) so widget tests can inject one.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS, including the existing Chart and Numbers tests.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart test/home_tabs_test.dart
git commit -m "feat: add Community tab independent of the stats load"
```
