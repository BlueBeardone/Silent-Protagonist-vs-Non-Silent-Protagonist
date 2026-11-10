import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/comments.dart';
import '../logic/comments_api.dart';

/// The notice shown at the top of the Community tab.
const String researchNotice =
    'Research project. This collects how people feel about silent vs. '
    'non-silent protagonists. Comments are public; your email is masked and '
    'never shown in full.';

/// The shorter notice shown inside the composer, right before posting.
const String composeNotice =
    'Used for research. We may email you occasionally to follow up, and your '
    'comment is public.';

/// The Community tab: every comment, newest first, loaded on open, plus a
/// floating action button that opens a composer for adding one.
///
/// Validation happens locally before anything touches the network: an invalid
/// email or blank comment is reported inline and [CommentsApi.post] is never
/// called. Comment bodies and emails are rendered with plain [Text] widgets so
/// any markup someone types is shown literally rather than interpreted.
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key, required this.api});

  /// The client used to post and list comments. Injectable so tests can supply
  /// a mock transport.
  final CommentsApi api;

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  List<Comment>? _comments;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final comments = await widget.api.listAll();
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load comments. Please try again.';
      });
    }
  }

  Future<void> _openComposer() async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: _CommentComposer(api: widget.api),
      ),
    );
    // Re-fetch so the just-posted comment appears at the top.
    if (posted == true) await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Notice(text: researchNotice),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse('/privacy.html')),
              child: const Text('Privacy policy'),
            ),
          ),
          Expanded(child: _buildList(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        tooltip: 'Add a comment',
        child: const Icon(Icons.add_comment),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadComments, child: const Text('Retry')),
          ],
        ),
      );
    }
    final comments = _comments ?? const <Comment>[];
    if (comments.isEmpty) {
      return const Center(child: Text('No comments yet. Be the first.'));
    }
    return ListView.builder(
      // Extra bottom padding keeps the last row clear of the floating button.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        final scheme = Theme.of(context).colorScheme;
        // A lighter card with a visible outline so adjacent comments are easy
        // to tell apart against the page background.
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(comment.comment),
              const SizedBox(height: 6),
              Text(
                comment.email,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A quiet full-width banner carrying the research notice.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// The composer sheet: the same email + comment fields as before, posting to
/// the API and popping with `true` on success so the tab can refresh.
class _CommentComposer extends StatefulWidget {
  const _CommentComposer({required this.api});

  final CommentsApi api;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final _commentController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final email = _emailController.text;
    final comment = _commentController.text;

    // Validate locally first so an invalid form never hits the API.
    final problem = validateEmail(email) ?? validateComment(comment);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.api.post(
        email: email,
        comment: comment,
        website: _websiteController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not post your comment. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Share your thoughts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(composeNotice, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            key: const Key('email'),
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Your email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('comment'),
            controller: _commentController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Your comment',
              border: OutlineInputBorder(),
            ),
          ),
          // Honeypot: invisible to people, tempting to bots. A non-empty
          // value is rejected by the server.
          Offstage(
            offstage: true,
            child: TextField(
              key: const Key('website'),
              controller: _websiteController,
              autofocus: false,
              decoration: const InputDecoration(labelText: 'Website'),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(55),
            ),
            onPressed: _loading ? null : _post,
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}
