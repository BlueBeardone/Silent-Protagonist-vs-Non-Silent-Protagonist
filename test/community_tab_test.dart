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

  testWidgets('the filter button lists every tag with its count',
      (tester) async {
    final api = apiWith([
      {
        'id': '1',
        'email': '***@x.com',
        'comment': 'A',
        'createdAt': '2026-11-05T12:00:00.000Z',
        'tag': 'mixed',
      },
      {
        'id': '2',
        'email': '***@x.com',
        'comment': 'B',
        'createdAt': '2026-11-05T11:00:00.000Z',
        'tag': 'mixed',
      },
      {
        'id': '3',
        'email': '***@x.com',
        'comment': 'C',
        'createdAt': '2026-11-05T10:00:00.000Z',
        'tag': 'leans_talking',
      },
    ]);

    await tester.pumpWidget(tab(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tag-filter')));
    await tester.pumpAndSettle();

    // Every tag is offered, even the ones with no comments.
    expect(find.text('Leans silent'), findsOneWidget);
    expect(find.text('Strongly silent'), findsOneWidget);
    // Counts sit beside their tag.
    expect(
      find.descendant(
        of: find.byKey(const Key('tag-option-mixed')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tag-option-leans_talking')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('selecting a tag narrows the list to matching comments',
      (tester) async {
    final api = apiWith([
      {
        'id': '1',
        'email': '***@x.com',
        'comment': 'only mixed here',
        'createdAt': '2026-11-05T12:00:00.000Z',
        'tag': 'mixed',
      },
      {
        'id': '2',
        'email': '***@x.com',
        'comment': 'only talking here',
        'createdAt': '2026-11-05T11:00:00.000Z',
        'tag': 'leans_talking',
      },
    ]);

    await tester.pumpWidget(tab(api));
    await tester.pumpAndSettle();
    expect(find.text('only talking here'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tag-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tag-option-mixed')));
    await tester.pumpAndSettle();

    expect(find.text('only mixed here'), findsOneWidget);
    expect(find.text('only talking here'), findsNothing);
  });
}
