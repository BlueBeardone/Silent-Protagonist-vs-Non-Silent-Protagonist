import 'package:flutter/material.dart';

import '../logic/comments.dart';
import '../logic/comments_api.dart';

/// The Community tab: a small form for leaving a comment plus a button that
/// reveals what everyone else said.
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
  final _commentController = TextEditingController();
  final _emailController = TextEditingController();

  List<Comment>? _comments;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final email = _emailController.text;
    final comment = _commentController.text;

    // Validate locally first so an invalid form never hits the API.
    final problem = validateEmail(email) ?? validateComment(comment);
    if (problem != null) {
      setState(() {
        _error = problem;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.api.post(email: email, comment: comment);
      if (!mounted) return;
      _commentController.clear();
      _emailController.clear();
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not post your comment. Please try again.';
      });
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final comments = await widget.api.list();
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

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('comment'),
            controller: _commentController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Your comment',
              border: OutlineInputBorder(),
            ),
          ),
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
          FilledButton(
            onPressed: _loading ? null : _post,
            child: const Text('Post'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loading ? null : _loadComments,
            child: const Text('See what others said'),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (comments != null)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8),
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  final comment = comments[index];
                  return ListTile(
                    title: Text(comment.comment),
                    subtitle: Text(comment.email),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
