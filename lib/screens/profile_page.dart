import 'package:flutter/material.dart';
import 'login_page.dart';
import 'edit_profile_page.dart';
import 'user_profile_page.dart';
import 'comments_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  String userName = 'Loading...';
  String userEmail = '';
  String? userAvatarUrl;
  int totalPosts = 0;
  int followerCount = 0;
  int followingCount = 0;
  int xpPoints = 0;
  int currentStreak = 0;
  bool _loading = true;
  List<Map<String, dynamic>> userPosts = [];
  List<Map<String, dynamic>> savedPosts = [];
  String _currentTab = 'posts'; // 'posts' or 'saved'
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    supabase.removeAllChannels();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Listen to posts table for user's posts changes
    supabase
        .channel('profile_posts_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('📝 Profile post event detected: ${payload.eventType}');
            _loadUserDataInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Profile posts channel subscription status: $status');
          if (error != null) {
            print('❌ Profile posts subscription error: $error');
          }
        });

    // Listen to user_stats table for stats updates
    supabase
        .channel('profile_stats_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_stats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('📊 Profile stats event detected: ${payload.eventType}');
            _loadUserDataInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Profile stats channel subscription status: $status');
          if (error != null) {
            print('❌ Profile stats subscription error: $error');
          }
        });

    // Listen to saved_posts table for saved posts changes
    supabase
        .channel('profile_saved_channel')
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
            
            print('🔖 Saved posts event detected: ${payload.eventType}');
            _loadUserDataInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Profile saved channel subscription status: $status');
          if (error != null) {
            print('❌ Profile saved subscription error: $error');
          }
        });

    // Listen to user_streaks table for streak updates
    supabase
        .channel('profile_streak_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_streaks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('🔥 Profile streak event detected: ${payload.eventType}');
            _loadUserDataInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Profile streak channel subscription status: $status');
          if (error != null) {
            print('❌ Profile streak subscription error: $error');
          }
        });

    // Listen to votes table for realtime vote updates on user's posts
    supabase
        .channel('profile_votes_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'votes',
          callback: (payload) {
            if (!mounted) return;
            
            print('👍 Profile votes event detected: ${payload.eventType}');
            _loadUserDataInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Profile votes channel subscription status: $status');
          if (error != null) {
            print('❌ Profile votes subscription error: $error');
          }
        });

    // Listen to comments table for realtime comment updates
    supabase
        .channel('profile_comments_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          callback: (payload) {
            if (!mounted) return;
            
            print('💬 Profile comments event detected: ${payload.eventType}');
            _loadUserDataInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Profile comments channel subscription status: $status');
          if (error != null) {
            print('❌ Profile comments subscription error: $error');
          }
        });
  }

  Future<void> _loadUserDataInBackground() async {
    if (!mounted) return;
    
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Get user stats
        Map<String, dynamic>? statsResponse;
        try {
          statsResponse = await supabase
              .from('user_stats')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();
        } catch (e) {
          print('Stats not available: $e');
        }
        
        // Get streak data
        Map<String, dynamic>? streakResponse;
        try {
          streakResponse = await supabase
              .from('user_streaks')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();
        } catch (e) {
          print('Streak data not available: $e');
        }
        
        // Get user's posts
        final postsResponse = await supabase
            .from('posts')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
        
        // Get saved posts
        List<dynamic> savedPostsResponse = [];
        try {
          savedPostsResponse = await supabase
              .from('saved_posts')
              .select('post_id, posts(*, user_name, user_avatar, comments_count, upvotes, downvotes)')
              .eq('user_id', user.id)
              .order('created_at', ascending: false);
        } catch (e) {
          print('Saved posts not available: $e');
        }
        
        final List<Map<String, dynamic>> savedPostsList = [];
        for (var item in savedPostsResponse) {
          if (item['posts'] != null) {
            final post = item['posts'] as Map<String, dynamic>;
            if (!post.containsKey('comments_count')) post['comments_count'] = 0;
            if (!post.containsKey('upvotes')) post['upvotes'] = 0;
            if (!post.containsKey('downvotes')) post['downvotes'] = 0;
            savedPostsList.add(post);
          }
        }
        
        if (mounted) {
          setState(() {
            totalPosts = statsResponse?['total_posts'] ?? postsResponse.length;
            followerCount = statsResponse?['follower_count'] ?? 0;
            followingCount = statsResponse?['following_count'] ?? 0;
            xpPoints = statsResponse?['xp_points'] ?? 0;
            currentStreak = streakResponse?['current_streak'] ?? 0;
            userPosts = List<Map<String, dynamic>>.from(postsResponse);
            savedPosts = savedPostsList;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user data in background: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh when app comes to foreground
    if (state == AppLifecycleState.resumed && _hasLoadedOnce) {
      _loadUserData();
    }
  }

  // Public method to refresh profile data (can be called from parent widgets)
  void refreshProfile() {
    if (mounted) {
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    
    _hasLoadedOnce = true;
    setState(() => _loading = true);
    
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Refresh user stats to get latest follower counts (wrapped in try-catch)
        try {
          await supabase.rpc('refresh_user_stats', params: {'p_user_id': user.id});
        } catch (e) {
          print('Note: refresh_user_stats function not available yet: $e');
        }
        
        // Get user name from metadata
        final name = user.userMetadata?['name'] ?? user.email?.split('@')[0] ?? 'EcoThreads User';
        final email = user.email ?? '';
        final avatarUrl = user.userMetadata?['avatar_url'];
        
        // Get user stats with latest follower counts (wrapped in try-catch)
        Map<String, dynamic>? statsResponse;
        try {
          statsResponse = await supabase
              .from('user_stats')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();
        } catch (e) {
          print('Stats not available: $e');
        }
        
        // Get streak data (wrapped in try-catch)
        Map<String, dynamic>? streakResponse;
        try {
          streakResponse = await supabase
              .from('user_streaks')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();
        } catch (e) {
          print('Streak data not available: $e');
        }
        
        // Get user's posts for display
        final postsResponse = await supabase
            .from('posts')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
        
        // Get saved posts with full post details (wrapped in try-catch)
        List<dynamic> savedPostsResponse = [];
        try {
          print('DEBUG: Fetching saved posts for user: ${user.id}');
          savedPostsResponse = await supabase
              .from('saved_posts')
              .select('post_id, posts(*, user_name, user_avatar, comments_count, upvotes, downvotes)')
              .eq('user_id', user.id)
              .order('created_at', ascending: false);
          print('DEBUG: Saved posts response: ${savedPostsResponse.length} items');
          print('DEBUG: Raw saved posts data: $savedPostsResponse');
        } catch (e) {
          print('ERROR: Saved posts not available: $e');
        }
        
        // Extract the posts from saved_posts with all details
        final List<Map<String, dynamic>> savedPostsList = [];
        for (var item in savedPostsResponse) {
          print('DEBUG: Processing saved post item: $item');
          if (item['posts'] != null) {
            final post = item['posts'] as Map<String, dynamic>;
            // Ensure all required fields exist
            if (!post.containsKey('comments_count')) {
              post['comments_count'] = 0;
            }
            if (!post.containsKey('upvotes')) {
              post['upvotes'] = 0;
            }
            if (!post.containsKey('downvotes')) {
              post['downvotes'] = 0;
            }
            savedPostsList.add(post);
            print('DEBUG: Added post to savedPostsList: ${post['title']}');
          } else {
            print('DEBUG: Post data is null for item: $item');
          }
        }
        print('DEBUG: Total saved posts loaded: ${savedPostsList.length}');
        
        // If no stats exist yet, create initial stats entry
        if (statsResponse == null) {
          try {
            await supabase.from('user_stats').insert({
              'user_id': user.id,
              'total_posts': postsResponse.length,
              'total_comments': 0,
              'total_upvotes_received': 0,
              'total_downvotes_received': 0,
              'xp_points': postsResponse.length * 50, // 50 XP per post
              'follower_count': 0,
              'following_count': 0,
            });
            
            // Fetch the newly created stats
            statsResponse = await supabase
                .from('user_stats')
                .select()
                .eq('user_id', user.id)
                .maybeSingle();
          } catch (e) {
            print('Could not create initial stats: $e');
          }
        }
        
        setState(() {
          userName = name;
          userEmail = email;
          userAvatarUrl = avatarUrl;
          // Use stats from user_stats table for accurate counts
          totalPosts = statsResponse?['total_posts'] ?? postsResponse.length;
          followerCount = statsResponse?['follower_count'] ?? 0;
          followingCount = statsResponse?['following_count'] ?? 0;
          xpPoints = statsResponse?['xp_points'] ?? 0;
          currentStreak = streakResponse?['current_streak'] ?? 0;
          userPosts = List<Map<String, dynamic>>.from(postsResponse);
          savedPosts = savedPostsList;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
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

      // Delete post from database
      await supabase.from('posts').delete().eq('id', postId);

      // Refresh user stats to update post count and XP immediately
      try {
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          await supabase.rpc('refresh_user_stats', params: {'p_user_id': userId});
        }
      } catch (e) {
        print('Note: refresh_user_stats not available: $e');
      }

      // Refresh user data
      _loadUserData();

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

  Future<void> _unsavePost(String postId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('saved_posts').delete().match({
        'user_id': userId,
        'post_id': postId,
      });

      // Refresh user data to update saved posts list
      _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post removed from saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing saved post: $e')),
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

      _loadUserData();

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

  String _getLevelName() {
    if (xpPoints < 1000) return 'Eco Apprentice';
    if (xpPoints < 3000) return 'Eco Builder';
    if (xpPoints < 6000) return 'Eco Innovator';
    if (xpPoints < 10000) return 'Eco Champion';
    return 'Eco Legend';
  }

  double _getProgressToNextLevel() {
    int currentLevelXp;
    int nextLevelXp;
    
    if (xpPoints < 1000) {
      currentLevelXp = 0;
      nextLevelXp = 1000;
    } else if (xpPoints < 3000) {
      currentLevelXp = 1000;
      nextLevelXp = 3000;
    } else if (xpPoints < 6000) {
      currentLevelXp = 3000;
      nextLevelXp = 6000;
    } else if (xpPoints < 10000) {
      currentLevelXp = 6000;
      nextLevelXp = 10000;
    } else {
      // Max level - show full progress
      return 1.0;
    }
    
    final progress = (xpPoints - currentLevelXp) / (nextLevelXp - currentLevelXp);
    return progress.clamp(0.0, 1.0);
  }

  String _getProgressText() {
    if (xpPoints < 1000) {
      return '$xpPoints / 1,000 XP to Eco Builder';
    } else if (xpPoints < 3000) {
      return '$xpPoints / 3,000 XP to Eco Innovator';
    } else if (xpPoints < 6000) {
      return '$xpPoints / 6,000 XP to Eco Champion';
    } else if (xpPoints < 10000) {
      return '$xpPoints / 10,000 XP to Eco Legend';
    } else {
      return 'Max Level Reached! 🏆';
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

  Future<void> _navigateToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(
          username: userName,
          bio: 'Eco Innovator',
          email: userEmail,
          portfolio: '',
          location: '',
          showEcoImpact: true,
          avatarUrl: userAvatarUrl,
        ),
      ),
    );

    if (result != null) {
      // Update the user metadata in Supabase
      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'name': result['username'],
            },
          ),
        );
        
        // Update all existing posts with the new name
        await supabase
            .from('posts')
            .update({'user_name': result['username']})
            .eq('user_id', supabase.auth.currentUser!.id);
        
        // Reload profile data
        _loadUserData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating profile: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade500),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading profile...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      // Removed bottomNavigationBar here
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.teal.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.white.withOpacity(0.8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[100],
                          backgroundImage: (userAvatarUrl != null && userAvatarUrl!.isNotEmpty)
                              ? NetworkImage(userAvatarUrl!)
                              : null,
                          child: (userAvatarUrl == null || userAvatarUrl!.isEmpty)
                              ? Text(
                                  userName.isNotEmpty ? userName[0].toUpperCase() : 'E',
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      GestureDetector(
                        onTap: _navigateToEditProfile,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.blue.shade400, Colors.blue.shade600],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.edit, size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      userEmail,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ProfileStat(label: "Posts", value: totalPosts.toString(), icon: Icons.article),
                        _ProfileStat(label: "XP", value: xpPoints.toString(), highlight: true, icon: Icons.star),
                        _ProfileStat(label: "Followers", value: followerCount.toString(), icon: Icons.people),
                        _ProfileStat(label: "Following", value: followingCount.toString(), icon: Icons.person_add),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Progress Section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, Colors.green.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade400, Colors.teal.shade400],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.trending_up,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getLevelName(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              'Level Progress',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade400, Colors.teal.shade400],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$xpPoints XP',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _getProgressToNextLevel(),
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.emoji_events, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _getProgressText(),
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Achievements Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.emoji_events,
                      color: Colors.amber.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Achievements",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  _AchievementBox(icon: Icons.settings, color: Colors.yellow, label: "Repair"),
                  _AchievementBox(icon: Icons.credit_card, color: Colors.green, label: "Recycle"),
                  _AchievementBox(icon: Icons.autorenew, color: Colors.blue, label: "Upcycle"),
                  _AchievementBox(icon: Icons.build, color: Colors.purple, label: "DIY"),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Streak Section
            if (currentStreak > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.local_fire_department,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$currentStreak Day Streak! 🔥",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "You've been active for $currentStreak days",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.local_fire_department_outlined,
                        color: Colors.grey.shade600,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Start your streak!",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Open the app daily to build your streak",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Tab Switcher (My Posts / Saved Posts)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currentTab = 'posts'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: _currentTab == 'posts'
                              ? LinearGradient(
                                  colors: [Colors.green.shade400, Colors.teal.shade400],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.article,
                              size: 18,
                              color: _currentTab == 'posts' ? Colors.white : Colors.black45,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'My Posts (${userPosts.length})',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _currentTab == 'posts' ? Colors.white : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currentTab = 'saved'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: _currentTab == 'saved'
                              ? LinearGradient(
                                  colors: [Colors.green.shade400, Colors.teal.shade400],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bookmark,
                              size: 18,
                              color: _currentTab == 'saved' ? Colors.white : Colors.black45,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Saved (${savedPosts.length})',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _currentTab == 'saved' ? Colors.white : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Posts List (My Posts or Saved Posts)
            if (_currentTab == 'posts') ...[
              if (userPosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.post_add, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No posts yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create your first post!',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                ...userPosts.map((post) {
                final String title = post["title"] ?? "";
                final String content = post["content"] ?? "";
                final int upvotes = post["upvotes"] ?? 0;
                final int downvotes = post["downvotes"] ?? 0;
                final int commentsCount = post["comments_count"] ?? 0;
                final String? imageUrl = post["image_url"];
                final String flair = post["flair"] ?? "All";
                final String timeAgo = _timeAgo(post["created_at"]);

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CommentsPage(post: post),
                      ),
                    ).then((_) => _loadUserData()); // Refresh when returning
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        flair,
                                        style: const TextStyle(color: Colors.green, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                if (content.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    content,
                                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20),
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
                                    Icon(Icons.edit, size: 18, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 150,
                                color: Colors.grey[300],
                                child: const Center(
                                  child: Icon(Icons.broken_image, size: 30),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Upvote button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_upward, size: 16, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  upvotes.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Downvote button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_downward, size: 16, color: Colors.red),
                                const SizedBox(width: 4),
                                Text(
                                  downvotes.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Comments
                          const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(commentsCount.toString(), style: const TextStyle(fontSize: 12)),
                          const Spacer(),
                          Text(timeAgo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
              }).toList(),
            ],

            // Saved Posts Tab
            if (_currentTab == 'saved') ...[
              if (savedPosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.bookmark_border, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No saved posts yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Save posts to view them here!',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                ...savedPosts.map((post) {
                  final String title = post["title"] ?? "";
                  final String content = post["content"] ?? "";
                  final int upvotes = post["upvotes"] ?? 0;
                  final int downvotes = post["downvotes"] ?? 0;
                  final int commentsCount = post["comments_count"] ?? 0;
                  final String? imageUrl = post["image_url"];
                  final String flair = post["flair"] ?? "All";
                  final String timeAgo = _timeAgo(post["created_at"]);
                  final String userName = post["user_name"] ?? "Unknown";
                  final String? userAvatar = post["user_avatar"];
                  final String? postUserId = post["user_id"];

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CommentsPage(post: post),
                        ),
                      ).then((_) => _loadUserData()); // Refresh when returning
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (postUserId != null && postUserId != supabase.auth.currentUser?.id) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => UserProfilePage(userId: postUserId),
                                    ),
                                  ).then((_) => _loadUserData()); // Refresh when returning
                                }
                              },
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.green[100],
                                backgroundImage: (userAvatar != null && userAvatar.isNotEmpty)
                                    ? NetworkImage(userAvatar)
                                    : null,
                                child: (userAvatar == null || userAvatar.isEmpty)
                                    ? Text(
                                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (postUserId != null && postUserId != supabase.auth.currentUser?.id) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => UserProfilePage(userId: postUserId),
                                      ),
                                    ).then((_) => _loadUserData()); // Refresh when returning
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      timeAgo,
                                      style: const TextStyle(color: Colors.black54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                flair,
                                style: const TextStyle(color: Colors.green, fontSize: 11),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.bookmark_remove, color: Colors.red, size: 20),
                              onPressed: () => _unsavePost(post['id']),
                              tooltip: 'Unsave',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (content.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            content,
                            style: const TextStyle(color: Colors.black54, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 150,
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: Icon(Icons.broken_image, size: 30),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Upvote button
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_upward, size: 16, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    upvotes.toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Downvote button
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_downward, size: 16, color: Colors.red),
                                  const SizedBox(width: 4),
                                  Text(
                                    downvotes.toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Comments
                            const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(commentsCount.toString(), style: const TextStyle(fontSize: 12)),
                            const Spacer(),
                            const Icon(Icons.bookmark, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            const Text('Saved', style: TextStyle(fontSize: 12, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
                }).toList(),
            ],

            const SizedBox(height: 24),

            // Log Out Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.logout, color: Colors.white, size: 22),
                  label: const Text(
                    "Log Out",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  onPressed: () async {
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Log Out'),
                        content: const Text('Are you sure you want to log out?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (shouldLogout == true) {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => const LoginPage()),
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Small reusable widgets
class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final IconData icon;

  const _ProfileStat({
    required this.label,
    required this.value,
    this.highlight = false,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: highlight
                ? LinearGradient(
                    colors: [Colors.green.shade400, Colors.teal.shade400],
                  )
                : null,
            color: highlight ? null : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: highlight ? Colors.white : Colors.grey.shade600,
            size: 20,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: highlight ? Colors.green.shade700 : Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AchievementBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _AchievementBox({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}
