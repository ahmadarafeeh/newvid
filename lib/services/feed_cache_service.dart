import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

void unawaited(Future<void> future) {
  // Helper for fire-and-forget futures
}

class FeedCacheService {
  static const String _cachedForYouPostsKey = 'cached_for_you_posts_v4';
  static const String _seenPostsKey = 'seen_posts';
  static const Duration _cacheValidityDuration = Duration(hours: 24);
  static const String _mediaPreloadedKey = 'media_preloaded_v1';

  static Future<void> cacheForYouPosts(
      List<Map<String, dynamic>> posts, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Cache ALL posts without filtering by seen status
      final postsToCache = posts.take(3).toList();

      if (postsToCache.isNotEmpty) {
        final cacheData = {
          'posts': postsToCache,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'userId': userId,
        };
        await prefs.setString(_cachedForYouPostsKey, jsonEncode(cacheData));

        // Preload media for cached posts in background
        unawaited(_preloadMediaForPosts(postsToCache));
      }
    } catch (e) {}
  }

  static Future<void> _preloadMediaForPosts(
      List<Map<String, dynamic>> posts) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (final post in posts) {
        final mediaUrl = post['postUrl']?.toString();
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          try {
            // Preload to cache manager - works for both images and videos
            await DefaultCacheManager().getSingleFile(mediaUrl);
          } catch (e) {}
        }
      }

      await prefs.setBool(_mediaPreloadedKey, true);
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

        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isValid = cachedUserId == userId &&
            cacheAge < _cacheValidityDuration.inMilliseconds;

        if (isValid) {
          final List<dynamic> postsData = data['posts'];
          final cachedPosts = postsData.map<Map<String, dynamic>>((post) {
            return Map<String, dynamic>.from(post);
          }).toList();

          if (cachedPosts.isNotEmpty) {
            return cachedPosts;
          }
        } else {
          await _clearCache();
        }
      } else {}
    } catch (e) {}
    return null;
  }

  static Future<bool> isMediaPreloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mediaPreloadedKey) ?? false;
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
      await prefs.remove(_mediaPreloadedKey);

      await DefaultCacheManager().emptyCache();
    } catch (e) {}
  }

  static Future<Set<String>> getSeenPosts(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPostsList = prefs.getStringList('$_seenPostsKey$userId') ?? [];
      return Set<String>.from(seenPostsList);
    } catch (e) {
      return <String>{};
    }
  }

  static Future<void> markPostAsSeen(String postId, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPosts = await getSeenPosts(userId);
      seenPosts.add(postId);

      final trimmedSeenPosts = seenPosts.toList();
      if (trimmedSeenPosts.length > 500) {
        trimmedSeenPosts.removeRange(0, trimmedSeenPosts.length - 500);
      }

      await prefs.setStringList('$_seenPostsKey$userId', trimmedSeenPosts);
    } catch (e) {}
  }

  static Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
      await prefs.remove(_mediaPreloadedKey);
    } catch (e) {}
  }
}
