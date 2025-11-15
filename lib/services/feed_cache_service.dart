// feed_cache_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FeedCacheService {
  static const String _cachedForYouPostsKey = 'cached_for_you_posts_v2';
  static const String _seenPostsKey = 'seen_posts';
  static const Duration _cacheValidityDuration =
      Duration(hours: 2); // Shorter cache for freshness

  static Future<void> cacheForYouPosts(
      List<Map<String, dynamic>> posts, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPosts = await _getSeenPosts(userId);

      // Filter out seen posts and take only first 3 for instant load
      final unseenPosts = posts
          .where((post) {
            final postId = post['postId']?.toString() ?? '';
            return postId.isNotEmpty && !seenPosts.contains(postId);
          })
          .take(3)
          .toList(); // Only cache 3 posts for instant display

      if (unseenPosts.isNotEmpty) {
        final cacheData = {
          'posts': unseenPosts,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'userId': userId,
        };
        await prefs.setString(_cachedForYouPostsKey, jsonEncode(cacheData));
      }
    } catch (e) {}
  }

  static Future<List<Map<String, dynamic>>?> loadCachedForYouPosts(
      String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cachedForYouPostsKey);

      if (cachedData != null) {
        final Map<String, dynamic> data = jsonDecode(cachedData);
        final timestamp = data['timestamp'] as int;
        final cachedUserId = data['userId'] as String;

        // Check cache validity
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isValid = cachedUserId == userId &&
            cacheAge < _cacheValidityDuration.inMilliseconds;

        if (isValid) {
          final List<dynamic> postsData = data['posts'];
          final cachedPosts = postsData.map<Map<String, dynamic>>((post) {
            return Map<String, dynamic>.from(post);
          }).toList();

          // Double-check posts haven't been seen
          final seenPosts = await _getSeenPosts(userId);
          final validCachedPosts = cachedPosts.where((post) {
            final postId = post['postId']?.toString() ?? '';
            return postId.isNotEmpty && !seenPosts.contains(postId);
          }).toList();

          return validCachedPosts.isNotEmpty ? validCachedPosts : null;
        }
      }
    } catch (e) {}
    return null;
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
    } catch (e) {}
  }

  static Future<Set<String>> _getSeenPosts(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPostsList = prefs.getStringList('$_seenPostsKey$userId') ?? [];
      return Set<String>.from(seenPostsList);
    } catch (e) {
      return <String>{};
    }
  }
}
