import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/feed_page.dart';
import '../screens/categories_page.dart';
import '../screens/create_post_page.dart';
import '../screens/leaderboard_page.dart';
import '../screens/profile_page.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  int _feedRefreshKey = 0;
  int _categoriesRefreshKey = 0;
  int _leaderboardRefreshKey = 0;
  int _profileRefreshKey = 0;

  List<Widget> get _pages => [
    FeedPage(key: ValueKey(_feedRefreshKey)),
    CategoriesPage(key: ValueKey(_categoriesRefreshKey)),
    const SizedBox(), // placeholder for Create
    LeaderboardPage(key: ValueKey(_leaderboardRefreshKey)),
    ProfilePage(key: ValueKey(_profileRefreshKey)),
  ];

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      });
    }
  }

  void _onItemTapped(int index) async {
    if (index == 2) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreatePostPage()),
      );

      // Refresh all pages after creating a post
      if (result == true || result == "feed") {
        setState(() {
          _selectedIndex = 0;
          _feedRefreshKey++; // Refresh the feed page
          _categoriesRefreshKey++; // Refresh categories
          _leaderboardRefreshKey++; // Refresh leaderboard
          _profileRefreshKey++; // Refresh profile to show updated stats
        });
      }
    } else {
      setState(() {
        _selectedIndex = index;
        // Auto-refresh the current tab to show real-time data
        switch (index) {
          case 0:
            _feedRefreshKey++;
            break;
          case 1:
            _categoriesRefreshKey++;
            break;
          case 3:
            _leaderboardRefreshKey++;
            break;
          case 4:
            _profileRefreshKey++;
            break;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, "Feed"),
                _buildNavItem(1, Icons.category_rounded, "Categories"),
                _buildCreateButton(),
                _buildNavItem(3, Icons.emoji_events_rounded, "Leaderboard"),
                _buildNavItem(4, Icons.person_rounded, "Profile"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [Colors.green.shade400, Colors.teal.shade400],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? null : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return GestureDetector(
      onTap: () => _onItemTapped(2),
      child: Container(
        width: 50,
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.teal.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}