import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/classifier.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments.dart';

/// A 200 OpenRouter reply whose assistant message is [content].
String _reply(String content) => jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    });

void main() {
  group('parseTagFromModelOutput', () {
    test('reads a bare tag', () {
      expect(parseTagFromModelOutput('strongly_silent'),
          CommentTag.stronglySilent);
    });

    test('reads a tag wrapped in punctuation or a sentence', () {
      expect(parseTagFromModelOutput('  Leans talking.  '),
          CommentTag.leansTalking);
      expect(
        parseTagFromModelOutput('The answer is: mixed'),
        CommentTag.mixed,
      );
    });

    test('accepts a spaced form of a two-word tag', () {
      expect(parseTagFromModelOutput('strongly talking'),
          CommentTag.stronglyTalking);
    });

    test('returns null when no tag appears', () {
      expect(parseTagFromModelOutput('I cannot tell'), isNull);
    });
  });

  group('classifierSystemPrompt', () {
    test('names every tag so the model can choose one', () {
      for (final tag in CommentTag.values) {
        expect(classifierSystemPrompt, contains(tag.wireName));
      }
    });
  });

  group('CommentClassifier.classify', () {
    test('posts the comment to OpenRouter and returns the tag', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(_reply('leans_silent'), 200);
      });
      final classifier = CommentClassifier(
        apiKey: 'sk-test',
        model: 'some/model',
        client: client,
      );

      final tag = await classifier.classify('I love a quiet hero');

      expect(tag, CommentTag.leansSilent);
      expect(seen.url.toString(),
          'https://openrouter.ai/api/v1/chat/completions');
      expect(seen.headers['authorization'], 'Bearer sk-test');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['model'], 'some/model');
      final messages = body['messages'] as List;
      expect(messages.last['content'], 'I love a quiet hero');
    });

    test('returns null and skips the network when no key is set', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(_reply('mixed'), 200);
      });
      final tag = await CommentClassifier(
        apiKey: '  ',
        client: client,
      ).classify('anything');
      expect(tag, isNull);
      expect(called, isFalse);
    });

    test('returns null on a non-200 response', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      expect(
        await CommentClassifier(apiKey: 'k', client: client)
            .classify('text'),
        isNull,
      );
    });

    test('returns null when the request throws', () async {
      final client = MockClient((_) async => throw http.ClientException('x'));
      expect(
        await CommentClassifier(apiKey: 'k', client: client)
            .classify('text'),
        isNull,
      );
    });

    test('returns null when the model output has no tag', () async {
      final client = MockClient((_) async => http.Response(_reply('hmm'), 200));
      expect(
        await CommentClassifier(apiKey: 'k', client: client)
            .classify('text'),
        isNull,
      );
    });
  });
}
