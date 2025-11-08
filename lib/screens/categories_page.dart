import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'comments_page.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  String? selectedCategory;
  List<Map<String, dynamic>> categoryPosts = [];
  bool isLoadingPosts = false;
  late AnimationController _animationController;
  bool _isSearching = false;
  String _searchQuery = '';
  
  final categories = [
    {
      "icon": Icons.build_circle,
      "title": "Repair Tips",
      "subtitle": "Fix devices & extend their lifespan",
      "badge": "",
      "badgeColor": const Color(0xFF00897B),
      "gradient": [const Color(0xFF00897B), const Color(0xFF26A69A)],
    },
    {
      "icon": Icons.auto_awesome,
      "title": "Upcycling",
      "subtitle": "Creative ways to repurpose old tech",
      "badge": "Popular",
      "badgeColor": const Color(0xFF43A047),
      "gradient": [const Color(0xFF43A047), const Color(0xFF66BB6A)],
    },
    {
      "icon": Icons.location_city,
      "title": "Recycling Centers",
      "subtitle": "Find local e-waste drop-off points",
      "badge": "",
      "badgeColor": const Color(0xFF1E88E5),
      "gradient": [const Color(0xFF1E88E5), const Color(0xFF42A5F5)],
    },
    {
      "icon": Icons.eco,
      "title": "Composting",
      "subtitle": "Organic waste management tips",
      "badge": "",
      "badgeColor": const Color(0xFF7CB342),
      "gradient": [const Color(0xFF7CB342), const Color(0xFF9CCC65)],
    },
    {
      "icon": Icons.construction,
      "title": "DIY Projects",
      "subtitle": "Build sustainable solutions",
      "badge": "Trending",
      "badgeColor": const Color(0xFFFB8C00),
      "gradient": [const Color(0xFFFB8C00), const Color(0xFFFFB74D)],
    },
    {
      "icon": Icons.help_outline,
      "title": "Ask Eco",
      "subtitle": "Get answers from the community",
      "badge": "",
      "badgeColor": const Color(0xFF8E24AA),
      "gradient": [const Color(0xFF8E24AA), const Color(0xFFAB47BC)],
    },
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
    _loadCategoryStats();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategoryStats() async {
    try {
      for (var category in categories) {
        final categoryTitle = category['title'] as String;
        final response = await supabase
            .from('posts')
            .select('id')
            .eq('flair', categoryTitle);
        
        final count = response.length;
        
        if (mounted) {
          setState(() {
            if (count > 0) {
              category['badge'] = '$count posts';
            }
          });
        }
      }
    } catch (e) {
      print('Error loading category stats: $e');
    }
  }

  Future<void> _loadCategoryPosts(String categoryTitle) async {
    setState(() {
      isLoadingPosts = true;
      selectedCategory = categoryTitle;
    });

    try {
      final response = await supabase
          .from('posts')
          .select()
          .eq('flair', categoryTitle)
          .order('created_at', ascending: false);

      setState(() {
        categoryPosts = List<Map<String, dynamic>>.from(response);
        isLoadingPosts = false;
      });
    } catch (e) {
      print('Error loading posts: $e');
      setState(() {
        isLoadingPosts = false;
      });
    }
  }

  void _onCategoryTap(Map<String, dynamic> category) {
    _loadCategoryPosts(category['title'] as String);
  }

  void _clearSelection() {
    setState(() {
      selectedCategory = null;
      categoryPosts = [];
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _searchQuery = query;
      isLoadingPosts = true;
      selectedCategory = 'Search Results';
    });

    try {
      if (query.isEmpty) {
        setState(() {
          categoryPosts = [];
          isLoadingPosts = false;
          selectedCategory = null;
        });
        return;
      }

      final response = await supabase
          .from('posts')
          .select()
          .or('title.ilike.%$query%,content.ilike.%$query%')
          .order('created_at', ascending: false);

      setState(() {
        categoryPosts = List<Map<String, dynamic>>.from(response);
        isLoadingPosts = false;
      });
    } catch (e) {
      print('Error searching posts: $e');
      setState(() {
        isLoadingPosts = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          SliverAppBar(
            expandedHeight: _isSearching ? 140 : 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(
                left: 20,
                bottom: _isSearching ? 60 : 16,
              ),
              title: _isSearching
                  ? null
                  : const Text(
                      'Explore Categories',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFF00897B).withOpacity(0.05),
                    ],
                  ),
                ),
                child: _isSearching
                    ? Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: const Color(0xFF00897B), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'Search posts...',
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF00897B)),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.grey),
                                        onPressed: () {
                                          _searchController.clear();
                                          _performSearch('');
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              onChanged: (value) {
                                setState(() {});
                                if (value.isEmpty) {
                                  _performSearch('');
                                }
                              },
                              onSubmitted: _performSearch,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: Colors.black87,
                ),
                onPressed: _toggleSearch,
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Selected Category Banner
          if (selectedCategory != null && selectedCategory != 'Search Results')
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: categories
                        .firstWhere((c) => c['title'] == selectedCategory)['gradient'] as List<Color>,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      categories.firstWhere((c) => c['title'] == selectedCategory)['icon'] as IconData,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedCategory!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${categoryPosts.length} posts',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _clearSelection,
                    ),
                  ],
                ),
              ),
            )
          else if (selectedCategory == 'Search Results')
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Search Results',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _searchQuery.isNotEmpty 
                                ? '${categoryPosts.length} results for "$_searchQuery"'
                                : '${categoryPosts.length} posts found',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        _clearSelection();
                        _toggleSearch();
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Categories Grid or Posts List
          if (selectedCategory == null)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 175,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final category = categories[index];
                    return _buildCategoryCard(category);
                  },
                  childCount: categories.length,
                ),
              ),
            )
          else if (isLoadingPosts)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (categoryPosts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No posts in this category yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final post = categoryPosts[index];
                  return _buildPostCard(post);
                },
                childCount: categoryPosts.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    return GestureDetector(
      onTap: () => _onCategoryTap(category),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: category['gradient'] as List<Color>,
          ),
          boxShadow: [
            BoxShadow(
              color: (category['gradient'] as List<Color>)[0].withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background Pattern
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                category['icon'] as IconData,
                size: 120,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      category['icon'] as IconData,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    category['title'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Flexible(
                    child: Text(
                      category['subtitle'] as String,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  if ((category['badge'] as String).isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        category['badge'] as String,
                        style: TextStyle(
                          color: (category['gradient'] as List<Color>)[0],
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CommentsPage(post: post),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author Info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF00897B),
                      backgroundImage: post['user_avatar'] != null
                          ? NetworkImage(post['user_avatar'])
                          : null,
                      child: post['user_avatar'] == null
                          ? Text(
                              (post['user_name'] ?? 'U')[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post['user_name'] ?? 'EcoThreads User',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _getTimeAgo(post['created_at']),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Post Title
                Text(
                  post['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (post['content'] != null && post['content'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post['content'],
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                // Stats Row
                Row(
                  children: [
                    _buildStatChip(
                      Icons.arrow_upward,
                      (post['upvotes'] ?? 0).toString(),
                      const Color(0xFF00897B),
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      Icons.arrow_downward,
                      (post['downvotes'] ?? 0).toString(),
                      Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      Icons.comment_outlined,
                      (post['comments_count'] ?? 0).toString(),
                      const Color(0xFF1E88E5),
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

  Widget _buildStatChip(IconData icon, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            count,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp.toString());
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }
}
