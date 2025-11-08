import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'notification_page.dart';
import 'comments_page.dart';
import 'user_profile_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({Key? key}) : super(key: key);

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  final uuid = const Uuid();
  String selectedCategory = "All";
  
  // StreamControllers for real-time updates
  final _postsStreamController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _votesStreamController = StreamController<Map<String, String>>.broadcast();
  final _savedPostsStreamController = StreamController<Set<String>>.broadcast();
  final _notificationCountStreamController = StreamController<int>.broadcast();
  
  Map<String, String> userVotes = {};
  Set<String> savedPosts = {};
  String? _deviceId;
  bool _isFirstBuild = true; // Track first build to prevent double emission
  
  // Cache of current posts for instant updates
  List<Map<String, dynamic>> _currentPosts = [];

  @override
  bool get wantKeepAlive => true; // Keep the state alive when navigating away

  final List<String> categories = [
    "All",
    "Repair Tips",
    "Upcycling",
    "Recycling Centers",
    "Composting",
    "DIY Projects",
    "Ask Eco"
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
    _setupRealtimeSubscriptions();
  }

  // Initialize all data when page loads
  Future<void> _initializeData() async {
    await Future.wait([
      _fetchPosts(),
      _loadUserVotes(),
      _loadSavedPosts(),
      _loadUnreadNotificationCount(),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app comes back to foreground
      _refreshAllData();
    }
  }

  // Called when widget is rebuilt and becomes visible again
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Skip first build (data loads via initState)
    if (_isFirstBuild) {
      _isFirstBuild = false;
      return;
    }
    // Re-emit cached data when returning to this page
    _emitCurrentStreamData();
  }

  // Emit current cached data to all streams
  void _emitCurrentStreamData() {
    if (!_postsStreamController.isClosed && _currentPosts.isNotEmpty) {
      _postsStreamController.add(_currentPosts);
    }
    if (!_votesStreamController.isClosed) {
      _votesStreamController.add(userVotes);
    }
    if (!_savedPostsStreamController.isClosed) {
      _savedPostsStreamController.add(savedPosts);
    }
  }

  // Refresh all data
  void _refreshAllData() {
    _fetchPosts();
    _loadUserVotes();
    _loadSavedPosts();
    _loadUnreadNotificationCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Don't close streams when using AutomaticKeepAliveClientMixin
    // They will be closed when the widget is truly disposed
    if (!wantKeepAlive) {
      _postsStreamController.close();
      _votesStreamController.close();
      _savedPostsStreamController.close();
      _notificationCountStreamController.close();
    }
    supabase.removeAllChannels();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    // Listen to posts table changes (for upvotes, downvotes, comments_count updates)
    supabase
        .channel('feed_posts_stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: (payload) async {
            if (!mounted) return;
            
            print('🔥 Posts changed: ${payload.eventType}');
            
            if (payload.eventType == PostgresChangeEvent.update) {
              // INSTANT UPDATE: Update specific post without refetching entire list
              final newData = payload.newRecord;
              _updatePostInStream(newData);
            } else {
              // For INSERT/DELETE, refetch the full list
              _fetchPosts();
            }
          },
        )
        .subscribe();

    // Listen to votes table changes
    supabase
        .channel('feed_votes_stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'votes',
          callback: (payload) async {
            if (!mounted) return;
            print('🗳️ Votes changed - updating user votes');
            _loadUserVotes();
            // The trigger will update posts table, which will trigger posts stream
          },
        )
        .subscribe();

    // Listen to comments table changes
    supabase
        .channel('feed_comments_stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          callback: (payload) {
            if (!mounted) return;
            print('💬 Comments changed');
            // The trigger will update posts table, which will trigger posts stream
          },
        )
        .subscribe();

    // Listen to saved_posts table changes
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      supabase
          .channel('feed_saved_posts_stream')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'saved_posts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              if (!mounted) return;
              print('💾 Saved posts changed');
              _loadSavedPosts();
            },
          )
          .subscribe();
    }
  }

  // NEW METHOD: Update a specific post in the stream INSTANTLY without refetching
  void _updatePostInStream(Map<String, dynamic> updatedPost) {
    if (_currentPosts.isEmpty) return;
    
    // Find and update the specific post in the cached list
    bool updated = false;
    for (int i = 0; i < _currentPosts.length; i++) {
      if (_currentPosts[i]['id'] == updatedPost['id']) {
        // Merge updated counts with existing post data
        _currentPosts[i] = {..._currentPosts[i], ...updatedPost};
        updated = true;
        break;
      }
    }
    
    if (updated) {
      print('⚡ INSTANT UPDATE: Post ${updatedPost['id']} - upvotes: ${updatedPost['upvotes']}, downvotes: ${updatedPost['downvotes']}, comments: ${updatedPost['comments_count']}');
      // Push the updated list to the stream only if not closed
      if (!_postsStreamController.isClosed) {
        _postsStreamController.add(List.from(_currentPosts));
      }
    }
  }

  Future<void> _loadUserVotes() async {
    try {
      String voterId;
      final authUser = supabase.auth.currentUser;
      
      if (authUser != null) {
        voterId = authUser.id;
      } else {
        _deviceId ??= 'anon_${uuid.v4()}';
        voterId = _deviceId!;
      }

      final response = await supabase
          .from('votes')
          .select('post_id, vote_type')
          .eq('user_id', voterId);

      userVotes = {
        for (var vote in response)
          vote['post_id'] as String: vote['vote_type'] as String
      };
      
      // Only add to stream if not closed
      if (!_votesStreamController.isClosed) {
        _votesStreamController.add(userVotes);
      }
    } catch (e) {
      print('❌ Error loading votes: $e');
    }
  }

  Future<void> _loadSavedPosts() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('saved_posts')
          .select('post_id')
          .eq('user_id', userId);

      savedPosts = {
        for (var saved in response) saved['post_id'] as String
      };
      
      // Only add to stream if not closed
      if (!_savedPostsStreamController.isClosed) {
        _savedPostsStreamController.add(savedPosts);
      }
    } catch (e) {
      print('❌ Error loading saved posts: $e');
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (!_notificationCountStreamController.isClosed) {
          _notificationCountStreamController.add(0);
        }
        return;
      }

      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .eq('is_read', false);

      // Only add to stream if not closed
      if (!_notificationCountStreamController.isClosed) {
        _notificationCountStreamController.add(response.length);
      }
    } catch (e) {
      print('❌ Error loading notification count: $e');
    }
  }

  Future<void> _fetchPosts() async {
    try {
      final response = await supabase
          .from('posts')
          .select()
          .order('created_at', ascending: false);

      final posts = List<Map<String, dynamic>>.from(response);
      _currentPosts = posts; // Cache the posts for instant updates
      
      // Only add to stream if not closed
      if (!_postsStreamController.isClosed) {
        _postsStreamController.add(posts);
      }
    } catch (e) {
      print('❌ Error fetching posts: $e');
    }
  }

  Future<void> _deletePost(String postId, String? imageUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
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
      // Delete image from storage if exists
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final fileName = imageUrl.split('/').last;
          await supabase.storage.from('posts').remove([fileName]);
        } catch (e) {
          // Ignore if image doesn't exist
        }
      }

      await supabase.from('posts').delete().eq('id', postId);
      // Real-time will handle the update via stream

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting post: $e')),
        );
      }
    }
  }

  Future<void> _editPost(Map<String, dynamic> post) async {
    final titleController = TextEditingController(text: post['title']);
    final contentController = TextEditingController(text: post['content']);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Post'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await supabase.from('posts').update({
        'title': titleController.text.trim(),
        'content': contentController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', post['id']);

      // Real-time will handle the update via stream

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating post: $e')),
        );
      }
    } finally {
      titleController.dispose();
      contentController.dispose();
    }
  }

  Future<void> _reportPost(Map<String, dynamic> post) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to report posts')),
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
          title: const Text('Report Post'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Why are you reporting this post?'),
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
        'content_type': 'post',
        'content_id': post['id'],
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
            const SnackBar(content: Text('You have already reported this post')),
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

  List<Map<String, dynamic>> _filterPosts(List<Map<String, dynamic>> posts) {
    if (selectedCategory == "All") {
      return posts;
    }
    return posts.where((post) => post['flair'] == selectedCategory).toList();
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

  Future<void> _handleVote(String postId, String voteType) async {
    // Reddit-style voting: anyone can vote
    // Use auth user ID if logged in, otherwise generate anonymous device ID
    String voterId;
    final authUser = supabase.auth.currentUser;
    
    if (authUser != null) {
      voterId = authUser.id;
    } else {
      // Generate persistent device ID for anonymous users
      // In production, use shared_preferences to persist this across sessions
      _deviceId ??= 'anon_${uuid.v4()}';
      voterId = _deviceId!;
    }

    // ⚡ INSTANT UPDATE: Update UI immediately (optimistic update)
    final String? previousVote = userVotes[postId];
    setState(() {
      if (previousVote == voteType) {
        // Unvote - remove the vote
        userVotes.remove(postId);
      } else {
        // Vote or change vote
        userVotes[postId] = voteType;
      }
    });
    
    // Only add to stream if not closed
    if (!_votesStreamController.isClosed) {
      _votesStreamController.add(userVotes);
    }

    try {
      if (previousVote == voteType) {
        // Unvote - remove the vote from database
        await supabase.from('votes').delete().match({
          'user_id': voterId,
          'post_id': postId,
        });
      } else {
        // Use upsert to insert or update - prevents duplicate key errors
        await supabase.from('votes').upsert({
          'user_id': voterId,
          'post_id': postId,
          'vote_type': voteType,
        }, onConflict: 'user_id,post_id');
      }
      // Real-time trigger will update the post counts
      print('✅ Vote saved: $voteType on post $postId');
    } catch (e) {
      print('❌ Error voting: $e');
      
      // ❌ If error, revert the optimistic update
      setState(() {
        if (previousVote == null) {
          userVotes.remove(postId);
        } else {
          userVotes[postId] = previousVote;
        }
      });
      
      // Only add to stream if not closed
      if (!_votesStreamController.isClosed) {
        _votesStreamController.add(userVotes);
      }
      
      if (mounted) {
        // Only show error if it's not a duplicate key error (which we now prevent)
        if (!e.toString().contains('duplicate key')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('Failed to vote. Please try again.'),
                ],
              ),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleSavePost(String postId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save posts')),
      );
      return;
    }

    // ⚡ INSTANT UPDATE: Update UI immediately (optimistic update)
    final bool wasSaved = savedPosts.contains(postId);
    setState(() {
      if (wasSaved) {
        savedPosts.remove(postId);
      } else {
        savedPosts.add(postId);
      }
    });
    
    // Only add to stream if not closed
    if (!_savedPostsStreamController.isClosed) {
      _savedPostsStreamController.add(savedPosts);
    }

    try {
      if (wasSaved) {
        // Remove from database
        await supabase.from('saved_posts').delete().match({
          'user_id': userId,
          'post_id': postId,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.bookmark_remove, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Post removed from saved'),
                ],
              ),
              backgroundColor: Colors.grey[800],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Add to database
        await supabase.from('saved_posts').insert({
          'user_id': userId,
          'post_id': postId,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.bookmark_added, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Post saved!'),
                ],
              ),
              backgroundColor: Colors.amber[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // ❌ If error, revert the optimistic update
      setState(() {
        if (wasSaved) {
          savedPosts.add(postId);
        } else {
          savedPosts.remove(postId);
        }
      });
      
      // Only add to stream if not closed
      if (!_savedPostsStreamController.isClosed) {
        _savedPostsStreamController.add(savedPosts);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _openComments(Map<String, dynamic> post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommentsPage(post: post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Modern Logo with Gradient
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.shade400,
                    Colors.green.shade600,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.eco,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Modern Title
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Colors.green.shade700,
                      Colors.green.shade500,
                    ],
                  ).createShader(bounds),
                  child: const Text(
                    "EcoThreads",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  "Sustainable Community",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Modern Notification Bell with StreamBuilder for badge
          StreamBuilder<int>(
            stream: _notificationCountStreamController.stream,
            initialData: 0,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationPage()),
                    );
                    _loadUnreadNotificationCount();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: count > 0 
                          ? Colors.red.shade50 
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: count > 0 
                            ? Colors.red.shade200 
                            : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          count > 0 
                              ? Icons.notifications_active_rounded 
                              : Icons.notifications_none_rounded,
                          color: count > 0 
                              ? Colors.red.shade700 
                              : Colors.grey.shade700,
                          size: 24,
                        ),
                        if (count > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.red.shade600, Colors.red.shade700],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.4),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: Column(
        children: [
          // Modern Category Tabs with Icons
          Container(
            height: 56,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final bool isSelected = category == selectedCategory;
                final categoryColor = _getFlairColor(category);
                final categoryIcon = _getFlairIcon(category);

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selectedCategory = category;
                      });
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: [categoryColor, categoryColor.withOpacity(0.7)],
                              )
                            : null,
                        color: isSelected ? null : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isSelected ? categoryColor : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: categoryColor.withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            categoryIcon,
                            size: 18,
                            color: isSelected ? Colors.white : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey.shade700,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Posts Feed with StreamBuilder
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _postsStreamController.stream,
              initialData: _currentPosts, // Show cached posts immediately
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return _buildSkeletonLoader();
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchPosts,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final allPosts = snapshot.data ?? [];
                final filteredPosts = _filterPosts(allPosts);

                if (filteredPosts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.green.shade100, Colors.green.shade50],
                            ),
                          ),
                          child: Icon(Icons.eco_outlined, size: 80, color: Colors.green.shade400),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No posts yet',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Be the first to share something eco-friendly!',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            // Navigate to create post
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Create Post'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _fetchPosts,
                  child: StreamBuilder<Map<String, String>>(
                    stream: _votesStreamController.stream,
                    initialData: userVotes,
                    builder: (context, votesSnapshot) {
                      final currentVotes = votesSnapshot.data ?? userVotes;
                      
                      return StreamBuilder<Set<String>>(
                        stream: _savedPostsStreamController.stream,
                        initialData: savedPosts,
                        builder: (context, savedSnapshot) {
                          final currentSaved = savedSnapshot.data ?? savedPosts;
                          
                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: filteredPosts.length,
                            itemBuilder: (context, index) {
                              final post = filteredPosts[index];
                              return _buildPostCard(post, currentVotes, currentSaved);
                            },
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Get color for each flair category
  Color _getFlairColor(String flair) {
    switch (flair) {
      case "Repair Tips":
        return Colors.blue;
      case "Upcycling":
        return Colors.purple;
      case "Recycling Centers":
        return Colors.teal;
      case "Composting":
        return Colors.brown;
      case "DIY Projects":
        return Colors.orange;
      case "Ask Eco":
        return Colors.pink;
      default:
        return Colors.green;
    }
  }

  // Get icon for each flair
  IconData _getFlairIcon(String flair) {
    switch (flair) {
      case "Repair Tips":
        return Icons.build;
      case "Upcycling":
        return Icons.autorenew;
      case "Recycling Centers":
        return Icons.recycling;
      case "Composting":
        return Icons.spa;
      case "DIY Projects":
        return Icons.construction;
      case "Ask Eco":
        return Icons.help_outline;
      default:
        return Icons.eco;
    }
  }

  // Skeleton Loader for initial loading state
  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ShimmerBox(width: 48, height: 48, borderRadius: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ShimmerBox(width: 150, height: 14, borderRadius: 4),
                            const SizedBox(height: 6),
                            _ShimmerBox(width: 100, height: 12, borderRadius: 4),
                          ],
                        ),
                      ),
                      _ShimmerBox(width: 80, height: 28, borderRadius: 14),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ShimmerBox(width: double.infinity, height: 16, borderRadius: 4),
                  const SizedBox(height: 8),
                  _ShimmerBox(width: 200, height: 14, borderRadius: 4),
                  const SizedBox(height: 16),
                  _ShimmerBox(width: double.infinity, height: 200, borderRadius: 16),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _ShimmerBox(width: double.infinity, height: 40, borderRadius: 12)),
                      const SizedBox(width: 8),
                      Expanded(child: _ShimmerBox(width: double.infinity, height: 40, borderRadius: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPostCard(
    Map<String, dynamic> post,
    Map<String, String> currentVotes,
    Set<String> currentSaved,
  ) {
    final String title = post["title"] ?? "";
    final String content = post["content"] ?? "";
    final String? imageUrl = post["image_url"];
    final String flair = post["flair"] ?? "All";
    final String userName = post["user_name"] ?? "EcoThreads User";
    final String? userAvatar = post["user_avatar"];
    final String postUserId = post["user_id"] ?? "";
    final String currentUserId = supabase.auth.currentUser?.id ?? "";
    final bool isOwnPost = postUserId == currentUserId;
    final String timeAgo = _timeAgo(post["created_at"]);
    final Color flairColor = _getFlairColor(flair);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 2,
        shadowColor: Colors.black12,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey.shade50,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Info Row with Modern Design
                Row(
                  children: [
                    // Animated Avatar
                    GestureDetector(
                      onTap: () {
                        if (postUserId.isNotEmpty && postUserId != currentUserId) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(userId: postUserId),
                            ),
                          );
                        }
                      },
                      child: Hero(
                        tag: 'avatar_$postUserId',
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [flairColor.withOpacity(0.3), flairColor.withOpacity(0.1)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: flairColor.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.transparent,
                            backgroundImage: (userAvatar != null && userAvatar.isNotEmpty)
                                ? NetworkImage(userAvatar)
                                : null,
                            child: (userAvatar == null || userAvatar.isEmpty)
                                ? Text(
                                    userName.isNotEmpty ? userName[0].toUpperCase() : 'E',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: flairColor,
                                      fontSize: 18,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (postUserId.isNotEmpty && postUserId != currentUserId) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfilePage(userId: postUserId),
                              ),
                            );
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  timeAgo,
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
                    ),
                    // Modern Flair Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [flairColor, flairColor.withOpacity(0.7)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: flairColor.withOpacity(0.3),
                            blurRadius: 6,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getFlairIcon(flair), size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            flair,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isOwnPost)
                      PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editPost(post);
                                  } else if (value == 'delete') {
                                    _deletePost(post['id'], imageUrl);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 20, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'report') {
                                    _reportPost(post);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'report',
                                    child: Row(
                                      children: [
                                        Icon(Icons.flag, size: 20, color: Colors.orange),
                                        SizedBox(width: 8),
                                        Text('Report'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                  ],
                ),
                const SizedBox(height: 16),

                // Post Title with Modern Typography
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                    letterSpacing: 0.2,
                  ),
                ),
                
                // Post Content with Better Readability
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    content,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],

                // Image with Hero Animation
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Hero(
                    tag: 'post_image_${post['id']}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 200,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.grey.shade200,
                                    Colors.grey.shade100,
                                    Colors.grey.shade200,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                  valueColor: AlwaysStoppedAnimation<Color>(flairColor),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.grey.shade300, Colors.grey.shade200],
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Modern Action Bar with Animated Buttons
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // Upvote with Animation
                      Expanded(
                        child: _AnimatedVoteButton(
                          icon: Icons.arrow_upward_rounded,
                          count: post["upvotes"] ?? 0,
                          label: 'Upvote',
                          isActive: currentVotes[post['id']] == 'upvote',
                          activeColor: Colors.green,
                          onTap: () => _handleVote(post['id'], 'upvote'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Downvote with Animation
                      Expanded(
                        child: _AnimatedVoteButton(
                          icon: Icons.arrow_downward_rounded,
                          count: post["downvotes"] ?? 0,
                          label: 'Downvote',
                          isActive: currentVotes[post['id']] == 'downvote',
                          activeColor: Colors.red,
                          onTap: () => _handleVote(post['id'], 'downvote'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Comments and Save Row
                Row(
                  children: [
                    // Comments Button
                    Expanded(
                      child: InkWell(
                        onTap: () => _openComments(post),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.comment_rounded, size: 20, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                '${post["comments_count"] ?? 0}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Comments',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Save/Bookmark Button
                    InkWell(
                      onTap: () => _toggleSavePost(post['id']),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: currentSaved.contains(post['id'])
                              ? Colors.amber.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          currentSaved.contains(post['id'])
                              ? Icons.bookmark
                              : Icons.bookmark_border_rounded,
                          color: currentSaved.contains(post['id'])
                              ? Colors.amber.shade700
                              : Colors.grey.shade600,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Custom Animated Vote Button Widget
class _AnimatedVoteButton extends StatefulWidget {
  final IconData icon;
  final int count;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _AnimatedVoteButton({
    required this.icon,
    required this.count,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_AnimatedVoteButton> createState() => _AnimatedVoteButtonState();
}

class _AnimatedVoteButtonState extends State<_AnimatedVoteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void didUpdateWidget(_AnimatedVoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger animation when count changes
    if (oldWidget.count != widget.count) {
      _controller.forward(from: 0.0).then((_) => _controller.reverse());
    }
    // Also trigger animation when active state changes
    if (oldWidget.isActive != widget.isActive) {
      _controller.forward(from: 0.0).then((_) => _controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0.0).then((_) => _controller.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: widget.isActive
              ? widget.activeColor.withOpacity(0.15)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isActive
                ? widget.activeColor.withOpacity(0.5)
                : Colors.grey.shade300,
            width: 1.5,
          ),
          boxShadow: widget.isActive
              ? [
                  BoxShadow(
                    color: widget.activeColor.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Icon(
                widget.icon,
                color: widget.isActive ? widget.activeColor : Colors.grey.shade600,
                size: 20,
              ),
            ),
            const SizedBox(width: 6),
            ScaleTransition(
              scale: _bounceAnimation,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w600,
                  color: widget.isActive ? widget.activeColor : Colors.grey.shade700,
                ),
                child: Text('${widget.count}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shimmer Loading Box Widget
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.grey.shade300,
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
                Colors.grey.shade300,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              transform: GradientRotation(_animation.value),
            ),
          ),
        );
      },
    );
  }
}