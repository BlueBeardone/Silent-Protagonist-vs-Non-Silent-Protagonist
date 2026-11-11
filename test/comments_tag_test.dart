import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments.dart';

void main() {
  group('CommentTag.fromWire', () {
    test('maps every wire name back to its tag', () {
      for (final tag in CommentTag.values) {
        expect(CommentTag.fromWire(tag.wireName), tag);
      }
    });

    test('returns null for an unknown or missing value', () {
      expect(CommentTag.fromWire('nonsense'), isNull);
      expect(CommentTag.fromWire(''), isNull);
      expect(CommentTag.fromWire(null), isNull);
    });
  });

  group('commentTagLabel', () {
    test('gives a distinct human label for every tag', () {
      final labels = {for (final tag in CommentTag.values) commentTagLabel(tag)};
      expect(labels, hasLength(CommentTag.values.length));
      expect(commentTagLabel(CommentTag.stronglySilent), 'Strongly silent');
      expect(commentTagLabel(CommentTag.stronglyTalking), 'Strongly talking');
    });
  });
}
