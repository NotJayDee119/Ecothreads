import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  bool _isFollowing = false;
  bool _isFriend = false;
  
  Map<String, dynamic>? _userStats;
  Map<String, dynamic>? _streakData;
  List<Map<String, dynamic>> userPosts = [];
  
  String userName = 'Loading...';
  String? userAvatarUrl;
  int followerCount = 0;
  int followingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    supabase.removeAllChannels();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    // Listen to posts table for this user's posts changes
    supabase
        .channel('user_profile_posts_channel_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('📝 User profile post event detected: ${payload.eventType}');
            _loadUserProfileInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 User profile posts channel subscription status: $status');
          if (error != null) {
            print('❌ User profile posts subscription error: $error');
          }
        });

    // Listen to user_stats table for this user's stats updates
    supabase
        .channel('user_profile_stats_channel_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_stats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('📊 User profile stats event detected: ${payload.eventType}');
            _loadUserProfileInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 User profile stats channel subscription status: $status');
          if (error != null) {
            print('❌ User profile stats subscription error: $error');
          }
        });

    // Listen to user_streaks table for this user's streak updates
    supabase
        .channel('user_profile_streak_channel_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_streaks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            
            print('🔥 User profile streak event detected: ${payload.eventType}');
            _loadUserProfileInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 User profile streak channel subscription status: $status');
          if (error != null) {
            print('❌ User profile streak subscription error: $error');
          }
        });

    // Listen to user_follows table for follow/unfollow changes
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId != null) {
      supabase
          .channel('user_profile_follows_channel_${widget.userId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'user_follows',
            callback: (payload) {
              if (!mounted) return;
              
              final followerId = payload.newRecord['follower_id'] ?? payload.oldRecord['follower_id'];
              final followingId = payload.newRecord['following_id'] ?? payload.oldRecord['following_id'];
              
              // Update if current user follows/unfollows this user OR this user follows/unfollows current user
              if ((followerId == currentUserId && followingId == widget.userId) ||
                  (followerId == widget.userId && followingId == currentUserId)) {
                print('👥 User profile follow event detected: ${payload.eventType}');
                _loadUserProfileInBackground();
              }
            },
          )
          .subscribe((status, [error]) {
            print('🔌 User profile follows channel subscription status: $status');
            if (error != null) {
              print('❌ User profile follows subscription error: $error');
            }
          });
    }

    // Listen to votes table for vote changes on this user's posts
    supabase
        .channel('user_profile_votes_channel_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'votes',
          callback: (payload) {
            if (!mounted) return;
            
            print('🗳️ User profile vote event detected: ${payload.eventType}');
            _loadUserProfileInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 User profile votes channel subscription status: $status');
          if (error != null) {
            print('❌ User profile votes subscription error: $error');
          }
        });

    // Listen to comments table for comment changes on this user's posts
    supabase
        .channel('user_profile_comments_channel_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          callback: (payload) {
            if (!mounted) return;
            
            print('💬 User profile comment event detected: ${payload.eventType}');
            _loadUserProfileInBackground();
          },
        )
        .subscribe((status, [error]) {
          print('🔌 User profile comments channel subscription status: $status');
          if (error != null) {
            print('❌ User profile comments subscription error: $error');
          }
        });
  }

  Future<void> _loadUserProfileInBackground() async {
    if (!mounted) return;
    
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get user stats
      Map<String, dynamic>? statsResponse;
      try {
        statsResponse = await supabase
            .from('user_stats')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle();
      } catch (e) {
        print('Stats not available: $e');
      }

      // Get user name and avatar
      Map<String, dynamic>? postsForUserInfo;
      try {
        postsForUserInfo = await supabase
            .from('posts')
            .select('user_name, user_avatar')
            .eq('user_id', widget.userId)
            .limit(1)
            .maybeSingle();
      } catch (e) {
        print('User info not available: $e');
      }

      // Get user's posts
      List<dynamic> userPostsList = [];
      try {
        userPostsList = await supabase
            .from('posts')
            .select('id')
            .eq('user_id', widget.userId);
      } catch (e) {
        print('Posts count not available: $e');
      }

      // Get streak data
      Map<String, dynamic>? streakResponse;
      try {
        streakResponse = await supabase
            .from('user_streaks')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle();
      } catch (e) {
        print('Streak data not available: $e');
      }

      // Check if current user follows this user
      bool isFollowing = false;
      bool isFriend = false;
      try {
        final followCheck = await supabase
            .from('user_follows')
            .select()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId)
            .maybeSingle();
        
        isFollowing = followCheck != null;

        if (isFollowing) {
          final friendCheck = await supabase
              .from('user_follows')
              .select()
              .eq('follower_id', widget.userId)
              .eq('following_id', currentUserId)
              .maybeSingle();
          
          isFriend = friendCheck != null;
        }
      } catch (e) {
        print('Follow status not available: $e');
      }

      // Get user's posts for display
      List<dynamic> postsResponse = [];
      try {
        postsResponse = await supabase
            .from('posts')
            .select('*, upvotes, downvotes, comments_count')
            .eq('user_id', widget.userId)
            .order('created_at', ascending: false)
            .limit(20);
      } catch (e) {
        print('Posts not available: $e');
      }

      if (mounted) {
        setState(() {
          userName = postsForUserInfo?['user_name'] ?? 'EcoThreads User';
          userAvatarUrl = postsForUserInfo?['user_avatar'];
          _userStats = statsResponse ?? {
            'xp_points': 0,
            'total_posts': userPostsList.length,
            'total_comments': 0,
            'follower_count': 0,
            'following_count': 0,
          };
          followerCount = statsResponse?['follower_count'] ?? 0;
          followingCount = statsResponse?['following_count'] ?? 0;
          _streakData = streakResponse;
          _isFollowing = isFollowing;
          _isFriend = isFriend;
          userPosts = List<Map<String, dynamic>>.from(postsResponse);
        });
      }
    } catch (e) {
      print('❌ Error loading user profile in background: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    setState(() => _loading = true);
    
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Refresh user stats first to get latest counts
      try {
        await supabase.rpc('refresh_user_stats', params: {'p_user_id': widget.userId});
      } catch (e) {
        print('Note: refresh_user_stats not available: $e');
      }

      // Get user stats (wrapped in try-catch)
      Map<String, dynamic>? statsResponse;
      try {
        statsResponse = await supabase
            .from('user_stats')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle();
      } catch (e) {
        print('Stats not available: $e');
      }

      // Get user name and avatar from their posts
      Map<String, dynamic>? postsForUserInfo;
      try {
        postsForUserInfo = await supabase
            .from('posts')
            .select('user_name, user_avatar')
            .eq('user_id', widget.userId)
            .limit(1)
            .maybeSingle();
      } catch (e) {
        print('User info not available from posts: $e');
      }

      // Get user's posts to count them accurately
      List<dynamic> userPostsList = [];
      try {
        userPostsList = await supabase
            .from('posts')
            .select('id')
            .eq('user_id', widget.userId);
      } catch (e) {
        print('Posts count not available: $e');
      }

      // If no stats exist for this user, create initial stats entry
      if (statsResponse == null && userPostsList.isNotEmpty) {
        try {
          await supabase.from('user_stats').insert({
            'user_id': widget.userId,
            'total_posts': userPostsList.length,
            'total_comments': 0,
            'total_upvotes_received': 0,
            'total_downvotes_received': 0,
            'xp_points': userPostsList.length * 50, // 50 XP per post
            'follower_count': 0,
            'following_count': 0,
          });
          
          // Fetch the newly created stats
          statsResponse = await supabase
              .from('user_stats')
              .select()
              .eq('user_id', widget.userId)
              .maybeSingle();
        } catch (e) {
          print('Could not create initial stats: $e');
        }
      }

      setState(() {
        userName = postsForUserInfo?['user_name'] ?? 'EcoThreads User';
        userAvatarUrl = postsForUserInfo?['user_avatar'];
        // Use stats from database for accurate real-time counts
        _userStats = statsResponse ?? {
          'xp_points': 0,
          'total_posts': userPostsList.length, // Fallback to actual count
          'total_comments': 0,
          'follower_count': 0,
          'following_count': 0,
        };
        // Ensure we use database stats if available
        followerCount = statsResponse?['follower_count'] ?? 0;
        followingCount = statsResponse?['following_count'] ?? 0;
      });

      // Get streak data (wrapped in try-catch)
      try {
        final streakResponse = await supabase
            .from('user_streaks')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle();
        
        setState(() {
          _streakData = streakResponse;
        });
      } catch (e) {
        print('Streak data not available: $e');
      }

      // Check if current user follows this user (wrapped in try-catch)
      try {
        final followCheck = await supabase
            .from('user_follows')
            .select()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId)
            .maybeSingle();
        
        setState(() {
          _isFollowing = followCheck != null;
        });

        // Check if they are friends (mutual follow)
        if (_isFollowing) {
          final friendCheck = await supabase
              .from('user_follows')
              .select()
              .eq('follower_id', widget.userId)
              .eq('following_id', currentUserId)
              .maybeSingle();
          
          setState(() {
            _isFriend = friendCheck != null;
          });
        }
      } catch (e) {
        print('Follow status not available: $e');
      }

      // Get user's posts
      try {
        final postsResponse = await supabase
            .from('posts')
            .select('*, upvotes, downvotes, comments_count')
            .eq('user_id', widget.userId)
            .order('created_at', ascending: false)
            .limit(20);

        setState(() {
          userPosts = List<Map<String, dynamic>>.from(postsResponse);
          _loading = false;
        });
      } catch (e) {
        print('Posts not available: $e');
        setState(() {
          userPosts = [];
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

  Future<void> _toggleFollow() async {
    try {
      final currentUserId = supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      if (_isFollowing) {
        // Unfollow
        await supabase
            .from('user_follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId);
        
        setState(() {
          _isFollowing = false;
          _isFriend = false;
          followerCount = (followerCount - 1).clamp(0, 999999);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unfollowed successfully')),
          );
        }
      } else {
        // Follow
        await supabase.from('user_follows').insert({
          'follower_id': currentUserId,
          'following_id': widget.userId,
        });
        
        // Check if now friends
        final friendCheck = await supabase
            .from('user_follows')
            .select()
            .eq('follower_id', widget.userId)
            .eq('following_id', currentUserId)
            .maybeSingle();
        
        final nowFriends = friendCheck != null;
        
        setState(() {
          _isFollowing = true;
          _isFriend = nowFriends;
          followerCount++;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(nowFriends ? 'You are now friends! 🎉' : 'Followed successfully'),
              backgroundColor: nowFriends ? Colors.green : null,
            ),
          );
        }
      }
      
      // Wait a moment for the trigger to update stats, then refresh
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Refresh stats for BOTH users to get updated counts
      try {
        // Refresh the profile owner's stats
        await supabase.rpc('refresh_user_stats', params: {'p_user_id': widget.userId});
        
        // Also refresh current user's stats (follower)
        await supabase.rpc('refresh_user_stats', params: {'p_user_id': currentUserId});
        
        // Get updated stats from database
        final statsResponse = await supabase
            .from('user_stats')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle();
        
        if (statsResponse != null && mounted) {
          setState(() {
            followerCount = statsResponse['follower_count'] ?? followerCount;
            followingCount = statsResponse['following_count'] ?? followingCount;
            // Update the entire stats object with fresh data
            _userStats = statsResponse;
          });
        }
      } catch (e) {
        print('Could not refresh stats: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _getLevelName() {
    if (_userStats != null) {
      final xp = _userStats!['xp_points'] ?? 0;
      if (xp < 1000) return 'Eco Apprentice';
      if (xp < 3000) return 'Eco Builder';
      if (xp < 6000) return 'Eco Innovator';
      if (xp < 10000) return 'Eco Champion';
      return 'Eco Legend';
    }
    return 'Eco Apprentice';
  }

  double _getProgressToNextLevel() {
    if (_userStats == null) return 0.0;
    final xp = _userStats!['xp_points'] ?? 0;
    
    int currentLevelXp;
    int nextLevelXp;
    
    if (xp < 1000) {
      currentLevelXp = 0;
      nextLevelXp = 1000;
    } else if (xp < 3000) {
      currentLevelXp = 1000;
      nextLevelXp = 3000;
    } else if (xp < 6000) {
      currentLevelXp = 3000;
      nextLevelXp = 6000;
    } else if (xp < 10000) {
      currentLevelXp = 6000;
      nextLevelXp = 10000;
    } else {
      // Max level - show full progress
      return 1.0;
    }
    
    final progress = (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);
    return progress.clamp(0.0, 1.0);
  }

  String _getProgressText() {
    if (_userStats == null) return '0 / 1,000 XP to next level';
    final xp = _userStats!['xp_points'] ?? 0;
    
    if (xp < 1000) {
      return '$xp / 1,000 XP to Eco Builder';
    } else if (xp < 3000) {
      return '$xp / 3,000 XP to Eco Innovator';
    } else if (xp < 6000) {
      return '$xp / 6,000 XP to Eco Champion';
    } else if (xp < 10000) {
      return '$xp / 10,000 XP to Eco Legend';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Profile',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
        ),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.teal.shade400],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                userName,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.black87, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
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
                      if (_isFriend)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.pink.shade400, Colors.red.shade400],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.pink.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.favorite, color: Colors.white, size: 18),
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
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getLevelName(),
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_isFriend)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white.withOpacity(0.3), Colors.white.withOpacity(0.2)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Friends',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  
                  // Follow Button
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: _isFollowing
                          ? null
                          : LinearGradient(
                              colors: [Colors.white, Colors.white.withOpacity(0.9)],
                            ),
                      color: _isFollowing ? Colors.white.withOpacity(0.3) : null,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isFollowing ? Colors.white.withOpacity(0.5) : Colors.white,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: _isFollowing ? Colors.white : Colors.green.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(
                        _isFollowing ? Icons.person_remove : Icons.person_add,
                        size: 22,
                      ),
                      label: Text(
                        _isFollowing ? 'Unfollow' : 'Follow',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onPressed: _toggleFollow,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Stats Row
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
                        _buildStat('Posts', '${_userStats?['total_posts'] ?? 0}', Icons.article),
                        _buildStat('XP', '${_userStats?['xp_points'] ?? 0}', Icons.star, highlight: true),
                        _buildStat('Followers', '$followerCount', Icons.people),
                        _buildStat('Following', '$followingCount', Icons.person_add),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // XP Progress Bar
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
                          '${_userStats?['xp_points'] ?? 0} XP',
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

            // Streak Section
            if (_streakData != null && _streakData!['current_streak'] > 0)
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
                            '${_streakData!['current_streak']} Day Streak 🔥',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Longest: ${_streakData!['longest_streak']} days',
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
              ),

            const SizedBox(height: 20),

            // User's Posts
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.article,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Posts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade400, Colors.teal.shade400],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${userPosts.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (userPosts.isEmpty)
              Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.post_add,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No posts yet',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This user hasn\'t posted anything',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
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

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(16),
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
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
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
                          ),
                        ],
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          content,
                          style: const TextStyle(color: Colors.black54, fontSize: 13),
                          maxLines: 3,
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
                          // Upvote container
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Text('🟢', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_upward, size: 14, color: Colors.green),
                                const SizedBox(width: 2),
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
                          // Downvote container
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Text('🔴', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_downward, size: 14, color: Colors.red),
                                const SizedBox(width: 2),
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
                          const SizedBox(width: 8),
                          // Comments
                          const Text('💬', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            commentsCount.toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            timeAgo,
                            style: const TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, {bool highlight = false}) {
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
