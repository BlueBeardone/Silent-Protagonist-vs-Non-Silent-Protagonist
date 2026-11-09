import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments_api.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/ui/community_tab.dart';

/// A client backed by a live, in-memory list: GET returns the current comments
/// and POST prepends the new one, so a refresh after posting sees the change.
CommentsApi apiWith(List<Map<String, dynamic>> comments) => CommentsApi(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final created = {
            'id': 'new',
            'email': 'bar***@gmail.com',
            'comment': body['comment'],
            'createdAt': '2026-11-05T13:00:00.000Z',
          };
          comments.insert(0, created);
          return http.Response(jsonEncode(created), 201);
        }
        return http.Response(
          jsonEncode({'comments': comments, 'nextCursor': null}),
          200,
        );
      }),
    );

Widget tab(CommentsApi api) => MaterialApp(home: CommunityTab(api: api));

void main() {
  testWidgets('loads and shows comments on open, without pressing anything',
      (tester) async {
    final api = apiWith([
      {
        'id': '1',
        'email': 'bar***@gmail.com',
        'comment': 'immersive',
        'createdAt': '2026-11-05T12:00:00.000Z',
      },
    ]);

    await tester.pumpWidget(tab(api));
    await tester.pumpAndSettle();

    expect(find.text('immersive'), findsOneWidget);
    expect(find.text('bar***@gmail.com'), findsOneWidget);
  });

  testWidgets('shows the research notice', (tester) async {
    await tester.pumpWidget(tab(apiWith([])));
    await tester.pumpAndSettle();

    expect(find.text(researchNotice), findsOneWidget);
  });

  testWidgets('the floating action button opens the composer',
      (tester) async {
    await tester.pumpWidget(tab(apiWith([])));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comment')), findsOneWidget);
    expect(find.byKey(const Key('email')), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
    expect(find.text(composeNotice), findsOneWidget);
  });

  testWidgets('the composer rejects a blank email', (tester) async {
    await tester.pumpWidget(tab(apiWith([])));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('comment')), 'nice');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your email address.'), findsOneWidget);
  });

  testWidgets('posting from the composer refreshes the list', (tester) async {
    await tester.pumpWidget(tab(apiWith([])));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'barry@gmail.com');
    await tester.enterText(find.byKey(const Key('comment')), 'immersive');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(find.text('immersive'), findsOneWidget);
    expect(find.byKey(const Key('comment')), findsNothing);
  });

  testWidgets('shows an error with retry when loading fails', (tester) async {
    final api = CommentsApi(
      client: MockClient((_) async => http.Response('nope', 500)),
    );

    await tester.pumpWidget(tab(api));
    await tester.pumpAndSettle();

    expect(find.text('Could not load comments. Please try again.'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
