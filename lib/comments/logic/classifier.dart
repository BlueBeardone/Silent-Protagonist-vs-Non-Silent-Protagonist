import 'dart:convert';

import 'package:http/http.dart' as http;

import 'comments.dart';

/// The instruction sent to the model ahead of the comment.
///
/// It names every [CommentTag.wireName] and demands a bare token back, so a
/// compliant reply parses with [parseTagFromModelOutput] and anything else is
/// treated as a failed classification.
const String classifierSystemPrompt =
    'You label how a video-game comment feels about the protagonist. '
    'Silent protagonists never speak; talking protagonists have an authored '
    'voice. Reply with exactly one of these words and nothing else: '
    'strongly_silent, leans_silent, mixed, leans_talking, strongly_talking, '
    'unclear. Use unclear when the comment expresses no preference or is off '
    'topic.';

/// The model used when `OPENROUTER_MODEL` is unset.
const String defaultClassifierModel = 'parallel/decisions-fast:free';

/// Reads a [CommentTag] out of a model reply.
///
/// The model is asked for a bare wire name, but it may add punctuation or a
/// short sentence, so this scans [text] for the earliest tag and accepts both
/// the `snake_case` and spaced forms. Returns null when no tag is present.
CommentTag? parseTagFromModelOutput(String text) {
  final lower = text.toLowerCase();
  CommentTag? best;
  var bestIndex = -1;
  for (final tag in CommentTag.values) {
    for (final form in [tag.wireName, tag.wireName.replaceAll('_', ' ')]) {
      final index = lower.indexOf(form);
      if (index >= 0 && (bestIndex < 0 || index < bestIndex)) {
        best = tag;
        bestIndex = index;
      }
    }
  }
  return best;
}

/// Classifies a comment onto the silent-vs-talking spectrum via OpenRouter.
///
/// Every failure path — a missing key, a network error, a non-200 response, or
/// an unparseable reply — returns null rather than throwing, so a model outage
/// can never stop a comment from being posted. That is why [classify] is
/// best-effort by contract.
class CommentClassifier {
  CommentClassifier({
    required this.apiKey,
    this.model = defaultClassifierModel,
    this.baseUrl = 'https://openrouter.ai/api/v1',
    this.timeout = const Duration(seconds: 5),
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The OpenRouter API key. Blank disables classification.
  final String apiKey;

  /// The OpenRouter model id, e.g. `parallel/decisions-fast:free`.
  final String model;

  /// The OpenRouter API root, without a trailing slash.
  final String baseUrl;

  /// How long to wait for the model before giving up.
  final Duration timeout;

  final http.Client _client;

  /// Whether classification is configured. A blank key means no calls are made.
  bool get enabled => apiKey.trim().isNotEmpty;

  /// Returns the comment's [CommentTag], or null when it could not be decided.
  Future<CommentTag?> classify(String comment) async {
    if (!enabled) return null;
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0,
              'max_tokens': 12,
              'messages': [
                {'role': 'system', 'content': classifierSystemPrompt},
                {'role': 'user', 'content': comment},
              ],
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final message = (choices.first as Map)['message'];
      final content = message is Map ? message['content'] : null;
      if (content is! String) return null;
      return parseTagFromModelOutput(content);
    } catch (_) {
      return null;
    }
  }
}
