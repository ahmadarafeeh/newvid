import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedCacheService {
  static const String _cachedForYouPostsKey = 'cached_for_you_posts_v3';
  static const String _seenPostsKey = 'seen_posts';
  static const Duration _cacheValidityDuration = Duration(hours: 24);

  static Future<void> cacheForYouPosts(
      List<Map<String, dynamic>> posts, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Cache ALL posts without filtering by seen status
      final postsToCache = posts.take(3).toList(); // Always cache first 3 posts

      if (postsToCache.isNotEmpty) {
        final cacheData = {
          'posts': postsToCache,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'userId': userId,
        };
        await prefs.setString(_cachedForYouPostsKey, jsonEncode(cacheData));
        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) {}
    }
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

          // Return ALL cached posts and let FeedScreen handle seen filtering
          if (cachedPosts.isNotEmpty) {
            if (kDebugMode) {}
            return cachedPosts;
          }
        } else {
          if (kDebugMode) {}
          await _clearCache();
        }
      } else {
        if (kDebugMode) {}
      }
    } catch (e) {
      if (kDebugMode) {}
    }
    return null;
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
      if (kDebugMode) {}
    } catch (e) {
      if (kDebugMode) {}
    }
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

  static Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
    } catch (e) {
      if (kDebugMode) {}
    }
  }
}
