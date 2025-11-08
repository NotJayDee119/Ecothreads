import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CommentsPage extends StatefulWidget {
  final Map<String, dynamic> post;

  const CommentsPage({Key? key, required this.post}) : super(key: key);

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final supabase = Supabase.instance.client;
  final uuid = const Uuid();
  final TextEditingController _commentController = TextEditingController();
  final _commentsStreamController = StreamController<List<Map<String, dynamic>>>.broadcast();
  bool _posting = false;
  String? _deviceId;  // For anonymous commenting

  @override
  void initState() {
    super.initState();
    _loadComments();
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentsStreamController.close();
    supabase.removeAllChannels();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    // Listen to comments table for real-time updates
    final channel = supabase.channel('comments_channel_${widget.post['id']}');
    
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.post['id'],
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('💬 Comment event detected: ${payload.eventType}');
            print('📦 Payload data: ${payload.newRecord}');
            
            if (payload.eventType == PostgresChangeEvent.insert) {
              // New comment added
              print('➕ New comment added by another user');
              _loadCommentsInBackground();
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              // Comment deleted
              print('🗑️ Comment deleted');
              _loadCommentsInBackground();
            } else if (payload.eventType == PostgresChangeEvent.update) {
              // Comment updated
              print('✏️ Comment updated');
              _loadCommentsInBackground();
            }
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Channel subscription status: $status');
          if (error != null) {
            print('❌ Subscription error: $error');
          }
        });
  }

  Future<void> _loadComments() async {
    try {
      final response = await supabase
          .from('comments')
          .select()
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: false);

      _commentsStreamController.add(List<Map<String, dynamic>>.from(response));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading comments: $e')),
        );
      }
    }
  }

  // Load comments in background without showing loading indicator
  // Used for real-time updates from other users
  Future<void> _loadCommentsInBackground() async {
    try {
      final response = await supabase
          .from('comments')
          .select()
          .eq('post_id', widget.post['id'])
          .order('created_at', ascending: false);

      if (mounted) {
        _commentsStreamController.add(List<Map<String, dynamic>>.from(response));
      }
    } catch (e) {
      print('❌ Error loading comments in background: $e');
      // Don't show error to user for background updates
    }
  }

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _posting = true);

    try {
      // Reddit-style: Allow anyone to comment
      String commenterId;
      String commenterName;
      String? commenterAvatar;
      
      final user = supabase.auth.currentUser;
      
      if (user != null) {
        // Authenticated user
        commenterId = user.id;
        commenterName = user.userMetadata?['name'] ?? 
                       user.email?.split('@')[0] ?? 
                       'EcoThreads User';
        commenterAvatar = user.userMetadata?['avatar_url'];
      } else {
        // Anonymous user
        _deviceId ??= 'anon_${uuid.v4()}';
        commenterId = _deviceId!;
        commenterName = 'Anonymous User';
        commenterAvatar = null;
      }

      await supabase.from('comments').insert({
        'post_id': widget.post['id'],
        'user_id': commenterId,
        'user_name': commenterName,
        'user_avatar': commenterAvatar,
        'content': _commentController.text.trim(),
      });

      _commentController.clear();
      // No need to manually reload - real-time subscription will handle it

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment posted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting comment: $e')),
        );
      }
    } finally {
      setState(() => _posting = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Are you sure you want to delete this comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('comments').delete().eq('id', commentId);
      // No need to manually reload - real-time subscription will handle it

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting comment: $e')),
        );
      }
    }
  }

  Future<void> _reportComment(Map<String, dynamic> comment) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to report comments')),
      );
      return;
    }

    // Show report dialog
    String? selectedReason;
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Report Comment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Why are you reporting this comment?'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  value: selectedReason,
                  items: const [
                    DropdownMenuItem(value: 'spam', child: Text('Spam')),
                    DropdownMenuItem(value: 'harassment', child: Text('Harassment')),
                    DropdownMenuItem(value: 'hate_speech', child: Text('Hate Speech')),
                    DropdownMenuItem(value: 'misinformation', child: Text('Misinformation')),
                    DropdownMenuItem(value: 'inappropriate_content', child: Text('Inappropriate Content')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    setState(() => selectedReason = value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Submit Report', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (result != true || selectedReason == null) {
      reasonController.dispose();
      return;
    }

    try {
      final userName = supabase.auth.currentUser?.userMetadata?['name'] ?? 
                       supabase.auth.currentUser?.email?.split('@')[0] ?? 
                       'EcoThreads User';

      await supabase.from('reports').insert({
        'reporter_id': userId,
        'reporter_name': userName,
        'content_type': 'comment',
        'content_id': comment['id'],
        'reason': selectedReason,
        'description': reasonController.text.trim().isEmpty 
            ? null 
            : reasonController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you for helping keep our community safe.')),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('duplicate key')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You have already reported this comment')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error submitting report: $e')),
          );
        }
      }
    } finally {
      reasonController.dispose();
    }
  }

  String _timeAgo(String? timestamp) {
    if (timestamp == null) return 'Just now';
    final dateTime = DateTime.parse(timestamp);
    final diff = DateTime.now().difference(dateTime);

    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    // Convert UUID to string for comparison with TEXT field in database
    final currentUserId = supabase.auth.currentUser?.id.toString() ?? '';
    final postOwnerId = widget.post['user_id']?.toString() ?? '';
    final isPostOwner = currentUserId.isNotEmpty && currentUserId == postOwnerId;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Discussion',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.green, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Post Preview - Modern Card Design
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.green[50],
                          backgroundImage: widget.post['user_avatar'] != null
                              ? NetworkImage(widget.post['user_avatar'])
                              : null,
                          child: widget.post['user_avatar'] == null
                              ? Text(
                                  (widget.post['user_name'] ?? 'E')[0].toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                    fontSize: 18,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.post['user_name'] ?? 'EcoThreads User',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Original Post',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.post['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  if (widget.post['content'] != null &&
                      widget.post['content'].toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.post['content'],
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 14,
                        height: 1.5,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Comments List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _commentsStreamController.stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final comments = snapshot.data ?? [];

                if (comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 64,
                            color: Colors.green[400],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No comments yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final isOwnComment =
                        comment['user_id'] == currentUserId;
                    final canDeleteComment = isOwnComment || isPostOwner;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.green.withOpacity(0.2),
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.green[50],
                                    backgroundImage:
                                        comment['user_avatar'] != null
                                            ? NetworkImage(
                                                comment['user_avatar'])
                                            : null,
                                    child: comment['user_avatar'] == null
                                        ? Text(
                                            (comment['user_name'] ?? 'E')[0]
                                                .toUpperCase(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green[700],
                                              fontSize: 14,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        comment['user_name'] ??
                                            'EcoThreads User',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 12,
                                            color: Colors.grey[500],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _timeAgo(comment['created_at']),
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (canDeleteComment)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red, size: 20),
                                      onPressed: () =>
                                          _deleteComment(comment['id']),
                                      padding: const EdgeInsets.all(8),
                                      constraints: const BoxConstraints(),
                                    ),
                                  )
                                else if (currentUserId.isNotEmpty)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.flag_outlined,
                                          color: Colors.orange, size: 20),
                                      onPressed: () =>
                                          _reportComment(comment),
                                      padding: const EdgeInsets.all(8),
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                comment['content'] ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Comment Input - Modern Design
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Share your thoughts...',
                            hintStyle: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          style: const TextStyle(fontSize: 14),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _postComment(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _posting
                        ? Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          )
                        : Material(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              onTap: _postComment,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.green[400]!,
                                      Colors.green[600]!,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
