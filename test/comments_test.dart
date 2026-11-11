import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments.dart';

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
    test('rejects text made only of control characters', () {
      expect(validateComment('\u0000\u0007\u0008'), isNotNull);
    });
  });

  group('sanitizeComment', () {
    test('removes control characters but keeps newlines', () {
      expect(sanitizeComment('a\u0000b\u0007c'), 'abc');
      expect(sanitizeComment('line1\nline2'), 'line1\nline2');
      expect(sanitizeComment('tab\there'), 'tabhere');
      expect(sanitizeComment('del\u007f'), 'del');
    });
    test('trims surrounding whitespace', () {
      expect(sanitizeComment('  hello  '), 'hello');
    });
    test('leaves ordinary unicode intact', () {
      expect(sanitizeComment('café 🎮'), 'café 🎮');
    });
  });

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

    test('emits the tag wire name, or null when untagged', () {
      Comment tagged(CommentTag? tag) => Comment(
            id: '1',
            email: 'a@x.com',
            comment: 'c',
            createdAt: DateTime.utc(2026, 11, 5, 12),
            tag: tag,
          );
      expect(tagged(CommentTag.leansSilent).toJson()['tag'], 'leans_silent');
      expect(tagged(null).toJson()['tag'], isNull);
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

    test('keeps the tag handed to add', () async {
      final store = InMemoryCommentsStore();
      await store.add(
        email: 'a@x.com',
        comment: 'one',
        tag: CommentTag.stronglyTalking,
      );
      expect((await store.recent()).single.tag, CommentTag.stronglyTalking);
    });
  });

  group('mongo mapping', () {    test('round-trips a document', () {
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

    test('stores the tag wire name and omits it when untagged', () {
      final tagged = commentToMongo(
        email: 'a@x.com',
        comment: 'hi',
        createdAt: DateTime.utc(2026, 11, 5, 12),
        tag: CommentTag.mixed,
      );
      expect(tagged['tag'], 'mixed');
      expect(commentFromMongo({'_id': 'abc', ...tagged}).tag, CommentTag.mixed);

      final untagged = commentToMongo(
        email: 'a@x.com',
        comment: 'hi',
        createdAt: DateTime.utc(2026, 11, 5, 12),
      );
      expect(untagged.containsKey('tag'), isFalse);
      expect(commentFromMongo({'_id': 'abc', ...untagged}).tag, isNull);
    });
  });

  Comment commentWith(CommentTag? tag) => Comment(
        id: '$tag',
        email: 'a@x.com',
        comment: 'c',
        createdAt: DateTime.utc(2026, 11, 5, 12),
        tag: tag,
      );

  group('tagCounts', () {
    test('counts each tag and includes zeroes for the rest', () {
      final counts = tagCounts([
        commentWith(CommentTag.leansSilent),
        commentWith(CommentTag.leansSilent),
        commentWith(CommentTag.mixed),
        commentWith(null),
      ]);
      expect(counts[CommentTag.leansSilent], 2);
      expect(counts[CommentTag.mixed], 1);
      expect(counts[CommentTag.stronglyTalking], 0);
      expect(counts.keys, containsAll(CommentTag.values));
    });
  });

  group('filterByTags', () {
    test('returns everything when no tags are selected', () {
      final comments = [commentWith(CommentTag.mixed), commentWith(null)];
      expect(filterByTags(comments, const {}), comments);
    });

    test('keeps only the selected tags and drops the untagged', () {
      final comments = [
        commentWith(CommentTag.mixed),
        commentWith(CommentTag.leansTalking),
        commentWith(null),
      ];
      final filtered =
          filterByTags(comments, const {CommentTag.leansTalking});
      expect(filtered.map((c) => c.tag), [CommentTag.leansTalking]);
    });
  });
}
