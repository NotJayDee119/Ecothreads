import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_profile_page.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final supabase = Supabase.instance.client;
  String _currentTab = 'global'; // 'global' or 'friends'
  bool _loading = true;
  List<Map<String, dynamic>> _leaderboardData = [];
  Map<String, dynamic>? _currentUserRank;
  Map<String, dynamic>? _streakData;

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
    _setupRealtimeSubscriptions();
  }

  @override
  void dispose() {
    supabase.removeAllChannels();
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    // Listen to user_stats table for real-time leaderboard updates
    supabase
        .channel('leaderboard_stats_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_stats',
          callback: (payload) {
            if (!mounted) return;
            
            print('📊 User stats event detected: ${payload.eventType}');
            
            // Any change in user_stats should refresh the leaderboard
            if (payload.eventType == PostgresChangeEvent.insert ||
                payload.eventType == PostgresChangeEvent.update ||
                payload.eventType == PostgresChangeEvent.delete) {
              print('🔄 Leaderboard data changed, refreshing...');
              _loadLeaderboardInBackground();
            }
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Leaderboard stats channel subscription status: $status');
          if (error != null) {
            print('❌ Leaderboard stats subscription error: $error');
          }
        });

    // Also listen to user_follows table for friend leaderboard updates
    supabase
        .channel('leaderboard_follows_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_follows',
          callback: (payload) {
            if (!mounted) return;
            
            print('👥 User follows event detected: ${payload.eventType}');
            
            // Refresh leaderboard when follows change (affects friend leaderboard)
            if (_currentTab == 'friends') {
              print('🔄 Friends list changed, refreshing...');
              _loadLeaderboardInBackground();
            }
          },
        )
        .subscribe((status, [error]) {
          print('🔌 Leaderboard follows channel subscription status: $status');
          if (error != null) {
            print('❌ Leaderboard follows subscription error: $error');
          }
        });

    // Listen to user_streaks table for real-time streak updates
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      supabase
          .channel('leaderboard_streak_channel')
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
              
              print('🔥 Streak event detected: ${payload.eventType}');
              
              if (payload.eventType == PostgresChangeEvent.update ||
                  payload.eventType == PostgresChangeEvent.insert) {
                _updateStreakInBackground();
              }
            },
          )
          .subscribe((status, [error]) {
            print('🔌 Leaderboard streak channel subscription status: $status');
            if (error != null) {
              print('❌ Leaderboard streak subscription error: $error');
            }
          });
    }
  }

  Future<void> _updateStreakInBackground() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase.rpc(
        'update_user_streak',
        params: {'p_user_id': userId},
      );

      if (mounted) {
        setState(() {
          _streakData = response as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      print('❌ Error updating streak in background: $e');
    }
  }

  Future<void> _loadLeaderboardInBackground() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      List<Map<String, dynamic>> statsData = [];

      if (_currentTab == 'global') {
        final statsResponse = await supabase
            .from('user_stats')
            .select()
            .order('xp_points', ascending: false)
            .limit(100);
        statsData = List<Map<String, dynamic>>.from(statsResponse);
      } else {
        final friendsResponse = await supabase
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', userId);

        final followingIds = friendsResponse
            .map((e) => e['following_id'])
            .toList();

        if (followingIds.isEmpty) {
          if (mounted) {
            setState(() {
              _leaderboardData = [];
              _currentUserRank = null;
            });
          }
          return;
        }

        final mutualFollowsResponse = await supabase
            .from('user_follows')
            .select('follower_id')
            .eq('following_id', userId)
            .inFilter('follower_id', followingIds);

        final friendIds = mutualFollowsResponse
            .map((e) => e['follower_id'])
            .toList();
        friendIds.add(userId);

        final statsResponse = await supabase
            .from('user_stats')
            .select()
            .inFilter('user_id', friendIds)
            .order('xp_points', ascending: false);

        statsData = List<Map<String, dynamic>>.from(statsResponse);
      }

      if (statsData.isEmpty) {
        if (mounted) {
          setState(() {
            _leaderboardData = [];
            _currentUserRank = null;
          });
        }
        return;
      }

      final userIds = statsData.map((s) => s['user_id'].toString()).toList();
      final profilesResponse = await supabase
          .from('posts')
          .select('user_id, user_name, user_avatar')
          .inFilter('user_id', userIds);

      final Map<String, Map<String, dynamic>> userInfoMap = {};
      for (var profile in profilesResponse) {
        final uid = profile['user_id'].toString();
        if (!userInfoMap.containsKey(uid)) {
          userInfoMap[uid] = {
            'user_name': profile['user_name'] ?? 'User',
            'user_avatar': profile['user_avatar'],
          };
        }
      }

      final enrichedData = <Map<String, dynamic>>[];
      int rank = 1;

      for (var stat in statsData) {
        final uid = stat['user_id'].toString();
        final userInfo =
            userInfoMap[uid] ?? {'user_name': 'User', 'user_avatar': null};

        enrichedData.add({
          'user_id': stat['user_id'],
          'user_name': userInfo['user_name'],
          'user_avatar': userInfo['user_avatar'],
          'xp_points': stat['xp_points'] ?? 0,
          'total_posts': stat['total_posts'] ?? 0,
          'total_comments': stat['total_comments'] ?? 0,
          'follower_count': stat['follower_count'] ?? 0,
          'level_info': _getLevelInfo(stat['xp_points'] ?? 0),
          'rank': rank++,
        });
      }

      if (mounted) {
        setState(() {
          _leaderboardData = enrichedData;
          _currentUserRank = enrichedData.firstWhere(
            (user) => user['user_id'] == userId,
            orElse: () => {},
          );
        });
      }
    } catch (e) {
      print('❌ Error loading leaderboard in background: $e');
    }
  }

  Future<void> _initializeAndLoadData() async {
    await _updateStreak();
    await _loadLeaderboard();
  }

  Future<void> _updateStreak() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Call the update_user_streak function
      final response = await supabase.rpc(
        'update_user_streak',
        params: {'p_user_id': userId},
      );

      setState(() {
        _streakData = response as Map<String, dynamic>?;
      });
    } catch (e) {
      print('Error updating streak: $e');
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _loading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Refresh current user's stats (wrapped in try-catch to handle if function doesn't exist)
      try {
        await supabase.rpc('refresh_user_stats', params: {'p_user_id': userId});
      } catch (e) {
        print('Note: refresh_user_stats function not available yet: $e');
      }

      List<Map<String, dynamic>> statsData = [];

      // Try to query user_stats table
      try {
        if (_currentTab == 'global') {
          // Get all user stats, ordered by XP
          final statsResponse = await supabase
              .from('user_stats')
              .select()
              .order('xp_points', ascending: false)
              .limit(100);

          statsData = List<Map<String, dynamic>>.from(statsResponse);
        } else {
          // Get friends' user IDs (mutual follows)
          final friendsResponse = await supabase
              .from('user_follows')
              .select('following_id')
              .eq('follower_id', userId);

          final followingIds = friendsResponse
              .map((e) => e['following_id'])
              .toList();

          if (followingIds.isEmpty) {
            setState(() {
              _leaderboardData = [];
              _currentUserRank = null;
              _loading = false;
            });
            return;
          }

          // Check which ones follow back (mutual follows = friends)
          final mutualFollowsResponse = await supabase
              .from('user_follows')
              .select('follower_id')
              .eq('following_id', userId)
              .inFilter('follower_id', followingIds);

          final friendIds = mutualFollowsResponse
              .map((e) => e['follower_id'])
              .toList();
          friendIds.add(userId); // Include current user

          // Get stats for friends
          final statsResponse = await supabase
              .from('user_stats')
              .select()
              .inFilter('user_id', friendIds)
              .order('xp_points', ascending: false);

          statsData = List<Map<String, dynamic>>.from(statsResponse);
        }
      } catch (tableError) {
        // Tables don't exist yet - show helpful message
        setState(() => _loading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Leaderboard tables not set up yet. Please run the SQL setup in Supabase.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // If no stats data, show empty leaderboard
      if (statsData.isEmpty) {
        setState(() {
          _leaderboardData = [];
          _currentUserRank = null;
          _loading = false;
        });
        return;
      }

      // Get all unique user IDs
      final userIds = statsData.map((s) => s['user_id'].toString()).toList();

      // Fetch user profiles from posts table (contains user info)
      final profilesResponse = await supabase
          .from('posts')
          .select('user_id, user_name, user_avatar')
          .inFilter('user_id', userIds);

      // Create a map of user_id -> user info
      final Map<String, Map<String, dynamic>> userInfoMap = {};
      for (var profile in profilesResponse) {
        final uid = profile['user_id'].toString();
        if (!userInfoMap.containsKey(uid)) {
          userInfoMap[uid] = {
            'user_name': profile['user_name'] ?? 'User',
            'user_avatar': profile['user_avatar'],
          };
        }
      }

      // Enrich stats with user data
      final enrichedData = <Map<String, dynamic>>[];
      int rank = 1;

      for (var stat in statsData) {
        final uid = stat['user_id'].toString();
        final userInfo =
            userInfoMap[uid] ?? {'user_name': 'User', 'user_avatar': null};

        enrichedData.add({
          'user_id': stat['user_id'],
          'user_name': userInfo['user_name'],
          'user_avatar': userInfo['user_avatar'],
          'xp_points': stat['xp_points'] ?? 0,
          'total_posts': stat['total_posts'] ?? 0,
          'total_comments': stat['total_comments'] ?? 0,
          'follower_count': stat['follower_count'] ?? 0,
          'level_info': _getLevelInfo(stat['xp_points'] ?? 0),
          'rank': rank++,
        });
      }

      setState(() {
        _leaderboardData = enrichedData;
        // Find current user's rank
        _currentUserRank = enrichedData.firstWhere(
          (user) => user['user_id'] == userId,
          orElse: () => {},
        );
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading leaderboard: $e')),
        );
      }
    }
  }

  Map<String, dynamic> _getLevelInfo(int xp) {
    int level;
    String levelName;
    int nextLevelXp;

    if (xp < 1000) {
      level = 1;
      levelName = 'Eco Apprentice';
      nextLevelXp = 1000;
    } else if (xp < 3000) {
      level = 2;
      levelName = 'Eco Builder';
      nextLevelXp = 3000;
    } else if (xp < 6000) {
      level = 3;
      levelName = 'Eco Innovator';
      nextLevelXp = 6000;
    } else if (xp < 10000) {
      level = 4;
      levelName = 'Eco Champion';
      nextLevelXp = 10000;
    } else {
      level = 5;
      levelName = 'Eco Legend';
      nextLevelXp = 999999;
    }

    final progress = nextLevelXp == 999999
        ? 100
        : ((xp / nextLevelXp) * 100).toInt();

    return {
      'level': level,
      'level_name': levelName,
      'current_xp': xp,
      'next_level_xp': nextLevelXp,
      'progress': progress,
    };
  }

  @override
  Widget build(BuildContext context) {
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.leaderboard,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "Leaderboard",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ],
        ),
        actions: [
          if (_streakData != null && _streakData!['current_streak'] > 0)
            Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade400, Colors.deepOrange.shade400],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_streakData!['current_streak']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLeaderboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Streak Banner
              if (_streakData != null && _streakData!['current_streak'] > 0)
                Container(
                  margin: const EdgeInsets.all(16),
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
                              _streakData!['message'] ?? 'Keep it up!',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '+${_streakData!['xp_earned']} XP earned today',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Tabs: Global / Friends
              Container(
                margin: const EdgeInsets.all(16),
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
                        onTap: () {
                          setState(() => _currentTab = 'global');
                          _loadLeaderboard();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: _currentTab == 'global'
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
                                Icons.public,
                                size: 18,
                                color: _currentTab == 'global'
                                    ? Colors.white
                                    : Colors.black45,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Global",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _currentTab == 'global'
                                      ? Colors.white
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _currentTab = 'friends');
                          _loadLeaderboard();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: _currentTab == 'friends'
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
                                Icons.people,
                                size: 18,
                                color: _currentTab == 'friends'
                                    ? Colors.white
                                    : Colors.black45,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Friends",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _currentTab == 'friends'
                                      ? Colors.white
                                      : Colors.black54,
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

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                )
              else if (_leaderboardData.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentTab == 'friends'
                            ? 'No friends yet!\nFollow others to see them here.'
                            : 'No users found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              else ...[
                // Top 3 podium
                if (_leaderboardData.length >= 3) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_leaderboardData.length > 1)
                        _buildPodium(
                          _leaderboardData[1]['user_name'] ?? 'User',
                          _getLevelName(_leaderboardData[1]),
                          '${_formatNumber(_leaderboardData[1]['xp_points'] ?? 0)} XP',
                          2,
                          Colors.grey,
                          _leaderboardData[1]['user_avatar'],
                          _leaderboardData[1]['user_id'],
                        ),
                      if (_leaderboardData.isNotEmpty)
                        _buildPodium(
                          _leaderboardData[0]['user_name'] ?? 'User',
                          _getLevelName(_leaderboardData[0]),
                          '${_formatNumber(_leaderboardData[0]['xp_points'] ?? 0)} XP',
                          1,
                          Colors.amber,
                          _leaderboardData[0]['user_avatar'],
                          _leaderboardData[0]['user_id'],
                        ),
                      if (_leaderboardData.length > 2)
                        _buildPodium(
                          _leaderboardData[2]['user_name'] ?? 'User',
                          _getLevelName(_leaderboardData[2]),
                          '${_formatNumber(_leaderboardData[2]['xp_points'] ?? 0)} XP',
                          3,
                          Colors.orange,
                          _leaderboardData[2]['user_avatar'],
                          _leaderboardData[2]['user_id'],
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // Your position card
                if (_currentUserRank != null && _currentUserRank!.isNotEmpty)
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
                      border: Border.all(color: Colors.green.shade300, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: Colors.green[100],
                              backgroundImage:
                                  _currentUserRank!['user_avatar'] != null
                                  ? NetworkImage(
                                      _currentUserRank!['user_avatar'],
                                    )
                                  : null,
                              child: _currentUserRank!['user_avatar'] == null
                                  ? Text(
                                      (_currentUserRank!['user_name'] ?? 'U')[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "You",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _getLevelName(_currentUserRank!),
                                    style: const TextStyle(color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "#${_currentUserRank!['rank']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  "${_formatNumber(_currentUserRank!['xp_points'] ?? 0)} XP",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _getProgress(_currentUserRank!),
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.green.shade600,
                            ),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getProgressText(_currentUserRank!),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // All Rankings
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.format_list_numbered,
                          color: Colors.green.shade700,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        "All Rankings",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // List all users
                ..._leaderboardData.skip(3).map((user) {
                  return _buildRankingItem(
                    user['user_name'] ?? 'User',
                    _getLevelName(user),
                    '${_formatNumber(user['xp_points'] ?? 0)} XP',
                    user['rank'] ?? 0,
                    user['user_avatar'],
                    user['user_id'],
                  );
                }).toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getLevelName(Map<String, dynamic> user) {
    if (user['level_info'] != null && user['level_info'] is Map) {
      return user['level_info']['level_name'] ?? 'Eco Apprentice';
    }
    return 'Eco Apprentice';
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  double _getProgress(Map<String, dynamic> user) {
    if (user['level_info'] != null && user['level_info'] is Map) {
      final currentXp = user['level_info']['current_xp'] ?? 0;
      final nextLevelXp = user['level_info']['next_level_xp'] ?? 1;
      if (nextLevelXp == 999999) return 1.0; // Max level
      return (currentXp / nextLevelXp).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  String _getProgressText(Map<String, dynamic> user) {
    if (user['level_info'] != null && user['level_info'] is Map) {
      final levelInfo = user['level_info'];
      final currentXp = levelInfo['current_xp'] ?? 0;
      final nextLevelXp = levelInfo['next_level_xp'] ?? 0;
      if (nextLevelXp == 999999) {
        return 'Max level reached!';
      }
      final nextLevel = _getNextLevelName(levelInfo['level'] ?? 1);
      return 'Progress to $nextLevel: ${_formatNumber(currentXp)} / ${_formatNumber(nextLevelXp)}';
    }
    return 'Keep going!';
  }

  String _getNextLevelName(int currentLevel) {
    switch (currentLevel) {
      case 1:
        return 'Eco Builder';
      case 2:
        return 'Eco Innovator';
      case 3:
        return 'Eco Champion';
      case 4:
        return 'Eco Legend';
      default:
        return 'Max Level';
    }
  }

  Widget _buildPodium(
    String name,
    String role,
    String xp,
    int rank,
    Color color,
    String? userImage,
    String userId,
  ) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isCurrentUser = userId == currentUserId;

    return GestureDetector(
      onTap: () {
        if (!isCurrentUser) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfilePage(userId: userId),
            ),
          ).then(
            (_) => _loadLeaderboard(),
          ); // Refresh leaderboard when returning
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: rank == 1 ? 40 : 35,
                    backgroundColor: Colors.grey[100],
                    backgroundImage: userImage != null && userImage.isNotEmpty
                        ? NetworkImage(userImage)
                        : null,
                    child: userImage == null || userImage.isEmpty
                        ? Text(
                            name[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: rank == 1 ? 24 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          )
                        : null,
                  ),
                ),
                if (isCurrentUser)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade400, Colors.teal.shade400],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.star,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 100,
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              role,
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              xp,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '#$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingItem(
    String name,
    String role,
    String xp,
    int rank,
    String? userImage,
    String userId,
  ) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isCurrentUser = userId == currentUserId;

    return GestureDetector(
      onTap: () {
        if (!isCurrentUser) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfilePage(userId: userId),
            ),
          ).then((_) => _loadLeaderboard()); // Refresh leaderboard when returning
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isCurrentUser
              ? LinearGradient(
                  colors: [Colors.white, Colors.green.shade50],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isCurrentUser ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isCurrentUser
              ? Border.all(color: Colors.green.shade300, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: isCurrentUser
                  ? Colors.green.withOpacity(0.15)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.green[100],
              backgroundImage: userImage != null && userImage.isNotEmpty
                  ? NetworkImage(userImage)
                  : null,
              child: userImage == null || userImage.isEmpty
                  ? Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    role,
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  xp,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                Text(
                  "#$rank",
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
