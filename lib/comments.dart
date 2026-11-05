/// Email masking and comment input validation for the community-comments
/// feature. All three functions are pure: they depend on nothing but their
/// arguments and never touch the network or the widget tree.
library;

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

/// Returns null when [comment] is a valid comment, else a human-readable
/// reason it was rejected. The comment is trimmed before checking.
String? validateComment(String comment) {
  final trimmed = comment.trim();
  if (trimmed.isEmpty) return 'Please enter a comment.';
  if (trimmed.length > _maxCommentLength) {
    return 'Comment must be $_maxCommentLength characters or fewer.';
  }
  return null;
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
