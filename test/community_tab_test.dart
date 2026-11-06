import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments_api.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/ui/community_tab.dart';

CommentsApi apiReturning(List<Map<String, dynamic>> comments) => CommentsApi(
      client: MockClient((_) async => http.Response(jsonEncode({'comments': comments}), 200)),
    );

void main() {
  testWidgets('rejects a blank email', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommunityTab(api: apiReturning([])))));
    await tester.enterText(find.byKey(const Key('comment')), 'nice');
    expect(find.text('Please enter your email address.'), findsNothing);
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(find.text('Please enter your email address.'), findsOneWidget);
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
