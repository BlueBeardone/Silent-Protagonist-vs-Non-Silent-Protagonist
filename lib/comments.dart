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
