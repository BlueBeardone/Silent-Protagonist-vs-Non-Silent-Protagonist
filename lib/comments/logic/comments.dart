/// Email masking and comment input validation for the community-comments
/// feature. All three functions are pure: they depend on nothing but their
/// arguments and never touch the network or the widget tree.
library;

import 'package:mongo_dart/mongo_dart.dart';

import 'email_cipher.dart';

/// A conservative address shape: something before the `@`, a dotted domain,
/// and a TLD of at least two letters. Deliberately stricter than RFC 5322 —
/// this only needs to catch obvious typos, not every legal address.
final RegExp _emailPattern =
    RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

/// The longest email we accept, matching the SMTP path limit.
const int _maxEmailLength = 254;

/// The longest comment we accept.
const int _maxCommentLength = 2000;

/// Masks an email address for display, keeping the domain visible.
///
/// The first three characters of the local part are kept; a local part of
/// three characters or fewer is masked entirely. Sub-addressing (`+tag`) is
/// stripped first so it never leaks into the visible part. An input without a
/// usable local part is returned unchanged.
String maskEmail(String email) {
  final at = email.lastIndexOf('@');
  if (at <= 0) return email;
  final domain = email.substring(at + 1);
  var local = email.substring(0, at);
  final plus = local.indexOf('+');
  if (plus >= 0) local = local.substring(0, plus);
  final visible = local.length > 3 ? local.substring(0, 3) : '';
  return '$visible***@$domain';
}

/// Returns null when [email] looks like a valid address, else a human-readable
/// reason it was rejected.
String? validateEmail(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return 'Please enter your email address.';
  if (trimmed.length > _maxEmailLength) {
    return 'Email address must be $_maxEmailLength characters or fewer.';
  }
  if (!_emailPattern.hasMatch(trimmed)) {
    return 'Please enter a valid email address.';
  }
  return null;
}

/// Strips control characters from [comment] and trims the result.
///
/// Control characters (code points below `0x20`) are removed except for the
/// newline (`\n`), and `0x7F` (DELETE) is removed too. The spec requires this
/// so that a comment cannot carry terminal escapes or other invisible control
/// bytes into storage or display.
String sanitizeComment(String comment) {
  final buffer = StringBuffer();
  for (final rune in comment.runes) {
    if (rune == 0x0A || (rune >= 0x20 && rune != 0x7F)) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().trim();
}

/// Returns null when [comment] is a valid comment, else a human-readable
/// reason it was rejected. The comment is sanitized (control characters
/// stripped) and trimmed before checking, so a comment made only of control
/// characters is rejected as empty.
String? validateComment(String comment) {
  final sanitized = sanitizeComment(comment);
  if (sanitized.isEmpty) return 'Please enter a comment.';
  if (sanitized.length > _maxCommentLength) {
    return 'Comment must be $_maxCommentLength characters or fewer.';
  }
  return null;
}

/// Signals that the comments backend is unreachable. The HTTP handler lets
/// this propagate so the availability middleware can translate it to a `503`.
class CommentsUnavailableException implements Exception {
  CommentsUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'CommentsUnavailableException: $message';
}

/// A single community comment as stored and displayed.
///
/// The [email] is kept in full internally for persistence, but [toJson] only
/// ever emits the masked form, so the full address never leaves the app.
class Comment {
  final String id;
  final String email;
  final String comment;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.email,
    required this.comment,
    required this.createdAt,
  });

  /// A JSON-safe view of this comment. `email` is masked via [maskEmail] and
  /// `createdAt` is a UTC ISO-8601 string.
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': maskEmail(email),
        'comment': comment,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

/// Persistence boundary for community comments.
abstract class CommentsStore {
  /// Persists a new comment and returns it with its generated id and
  /// `createdAt` timestamp.
  Future<Comment> add({required String email, required String comment});

  /// Returns up to [limit] comments, newest first. When [before] is given,
  /// only comments strictly older than that timestamp are returned.
  Future<List<Comment>> recent({int limit = 50, String? before});

  /// Removes the comment with [id]; returns whether anything was removed.
  Future<bool> deleteById(String id);
}

/// A [CommentsStore] that keeps everything in memory. Intended for tests and
/// local development; nothing survives a restart.
class InMemoryCommentsStore implements CommentsStore {
  InMemoryCommentsStore();

  final List<Comment> _comments = <Comment>[];
  int _nextId = 0;

  @override
  Future<Comment> add({required String email, required String comment}) async {
    final created = Comment(
      id: (_nextId++).toString(),
      email: email,
      comment: comment,
      createdAt: DateTime.now().toUtc(),
    );
    _comments.add(created);
    return created;
  }

  @override
  Future<List<Comment>> recent({int limit = 50, String? before}) async {
    final beforeTime = before == null ? null : DateTime.parse(before);
    final indexed = _comments.indexed
        .where((entry) =>
            beforeTime == null || entry.$2.createdAt.isBefore(beforeTime))
        .toList()
      ..sort((a, b) {
        final byTime = b.$2.createdAt.compareTo(a.$2.createdAt);
        if (byTime != 0) return byTime;
        return b.$1.compareTo(a.$1);
      });
    return indexed.take(limit).map((entry) => entry.$2).toList();
  }

  @override
  Future<bool> deleteById(String id) async {
    final index = _comments.indexWhere((c) => c.id == id);
    if (index < 0) return false;
    _comments.removeAt(index);
    return true;
  }
}

/// Builds the BSON document persisted for a new comment.
///
/// `createdAt` is a native [DateTime] so the driver stores it as a BSON date,
/// which both range queries ([MongoCommentsStore.recent]) and the
/// `{ createdAt: -1 }` index rely on.
///
/// When [emailEncrypted] is provided, the plaintext `email` is not stored:
/// the document keeps the encrypted value and the masked form. When it is
/// absent, the plaintext is stored (used by the in-memory store and tests).
Map<String, dynamic> commentToMongo({
  required String email,
  required String comment,
  required DateTime createdAt,
  String? emailEncrypted,
}) {
  final doc = <String, dynamic>{
    'comment': comment,
    'createdAt': createdAt,
  };
  if (emailEncrypted != null) {
    doc['emailEncrypted'] = emailEncrypted;
    doc['maskedEmail'] = maskEmail(email);
  } else {
    doc['email'] = email;
  }
  return doc;
}

/// Rebuilds a [Comment] from a MongoDB document.
///
/// The `_id` is exposed as the hex string the HTTP layer uses in URLs and that
/// [MongoCommentsStore.deleteById] parses back. The driver hands us an
/// [ObjectId] for stored documents, whose `toString()` is
/// `ObjectId("…")` — not the hex form the API contract requires — so the hex
/// [ObjectId.oid] is used in that case. A plain string id (as in the mapping
/// test) is stringified directly.
Comment commentFromMongo(Map<String, dynamic> doc) {
  final rawId = doc['_id'];
  final id = rawId is ObjectId ? rawId.oid : rawId.toString();
  return Comment(
    id: id,
    email: doc['email'] as String,
    comment: doc['comment'] as String,
    createdAt: doc['createdAt'] as DateTime,
  );
}

/// A [CommentsStore] backed by a MongoDB `comments` collection.
///
/// Intended for the server entrypoint (Task 6); it is not exercised by unit
/// tests, which never touch a live database.
class MongoCommentsStore implements CommentsStore {
  MongoCommentsStore(this._comments, this._rateLimits, [this._cipher]);

  final DbCollection _comments;
  final DbCollection _rateLimits;
  final EmailCipher? _cipher;

  /// The `rate_limits` collection used by the shared rate limiter.
  DbCollection get rateLimits => _rateLimits;

  /// Opens [uri], ensures the `{ createdAt: -1 }` index used by [recent], and
  /// returns a store over the `comments` collection.
  ///
  /// It also creates the `rate_limits` collection and its TTL index, so the
  /// shared rate limiter can expire old buckets without a separate job.
  ///
  /// When [emailEncryptionKey] is a base64 32-byte key, emails are encrypted
  /// at rest. The plaintext address is never written to the collection.
  static Future<MongoCommentsStore> connect(
    String uri, {
    String? emailEncryptionKey,
  }) async {
    final db = await Db.create(uri);
    await db.open();
    final comments = db.collection('comments');
    await comments.createIndex(keys: {'createdAt': -1});
    final rateLimits = db.collection('rate_limits');
    await db.runCommand({
      'createIndexes': 'rate_limits',
      'indexes': [
        {
          'key': {'expiresAt': 1},
          'name': 'expiresAt_ttl',
          'expireAfterSeconds': 0,
        },
      ],
    });
    final cipher = (emailEncryptionKey == null || emailEncryptionKey.isEmpty)
        ? null
        : EmailCipher(key: emailEncryptionKey);
    return MongoCommentsStore(comments, rateLimits, cipher);
  }

  @override
  Future<Comment> add({required String email, required String comment}) async {
    final createdAt = DateTime.now().toUtc();
    final emailEncrypted = _cipher == null ? null : await _cipher.encrypt(email);
    final doc = commentToMongo(
      email: email,
      comment: comment,
      createdAt: createdAt,
      emailEncrypted: emailEncrypted,
    );
    final result = await _comments.insertOne(doc);
    return commentFromMongo({'_id': result.id, ...doc, 'email': email});
  }

  @override
  Future<List<Comment>> recent({int limit = 50, String? before}) async {
    var selector = where.sortBy('createdAt', descending: true).limit(limit);
    if (before != null) {
      selector = selector.lt('createdAt', DateTime.parse(before));
    }
    final docs = await _comments.find(selector).toList();
    return Future.wait(docs.map(_commentFromMongo));
  }

  Future<Comment> _commentFromMongo(Map<String, dynamic> doc) async {
    final encrypted = doc['emailEncrypted'];
    if (encrypted is String && _cipher != null) {
      final email = await _cipher.decrypt(encrypted);
      return commentFromMongo({...doc, 'email': email});
    }
    return commentFromMongo(doc);
  }

  @override
  Future<bool> deleteById(String id) async {
    final ObjectId oid;
    try {
      oid = ObjectId.fromHexString(id);
    } on ArgumentError {
      // A malformed id is a miss, not a server error: the DELETE route turns
      // `false` into a 404 and must never surface a 500.
      return false;
    }
    final result = await _comments.deleteOne(where.id(oid));
    return result.nRemoved > 0;
  }
}
