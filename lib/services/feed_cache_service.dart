// services/feed_cache_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedCacheService {
  static const String _cachedForYouPostsKey = 'cached_for_you_posts_v2';
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
        if (kDebugMode) {
          debugPrint(
              '🔄 FeedCacheService: Cached ${postsToCache.length} posts for 24 hours');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Feed cache error: $e');
      }
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
            if (kDebugMode) {
              debugPrint(
                  '✅ FeedCacheService: Loaded ${cachedPosts.length} cached posts (${(cacheAge / 1000 / 60 / 60).toStringAsFixed(1)} hours old)');
            }
            return cachedPosts;
          }
        } else {
          if (kDebugMode) {
            debugPrint(
                '⏰ FeedCacheService: Cache expired (${(cacheAge / 1000 / 60 / 60).toStringAsFixed(1)} hours old)');
          }
          await _clearCache();
        }
      } else {
        if (kDebugMode) {
          debugPrint('📭 FeedCacheService: No cached posts found');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Feed cache load error: $e');
      }
    }
    return null;
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
      if (kDebugMode) {
        debugPrint('🗑️ FeedCacheService: Cache cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Feed cache clear error: $e');
      }
    }
  }

  static Future<Map<String, dynamic>?> getCacheInfo(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cachedForYouPostsKey);

      if (cachedData != null) {
        final Map<String, dynamic> data = jsonDecode(cachedData);
        final timestamp = data['timestamp'] as int;
        final cachedUserId = data['userId'] as String;
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isValid = cachedUserId == userId &&
            cacheAge < _cacheValidityDuration.inMilliseconds;

        return {
          'hasCache': true,
          'userId': cachedUserId,
          'timestamp': timestamp,
          'cacheAgeHours': (cacheAge / 1000 / 60 / 60),
          'isValid': isValid,
          'postsCount': (data['posts'] as List).length,
          'expiresInHours': (_cacheValidityDuration.inMilliseconds - cacheAge) /
              1000 /
              60 /
              60,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Cache info error: $e');
      }
    }
    return {'hasCache': false};
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
      if (kDebugMode) {
        debugPrint('❌ Cache clear error: $e');
      }
    }
  }
}
