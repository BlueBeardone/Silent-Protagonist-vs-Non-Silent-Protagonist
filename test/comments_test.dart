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
}
