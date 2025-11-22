import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

void unawaited(Future<void> future) {
  // Helper for fire-and-forget futures
}

class FeedCacheService {
  static const String _cachedForYouPostsKey = 'cached_for_you_posts_v17';
  static const String _seenPostsKey = 'seen_posts';
  static const Duration _cacheValidityDuration = Duration(hours: 24);
  static const String _mediaPreloadedKey = 'media_preloaded_v1';
  static const String _cacheUsedInSessionKey = 'cache_used_in_session';
  static const String _currentSessionIdKey = 'current_session_id';
  static const String _currentSessionHiddenKey = 'current_session_hidden';

  // Store session ID for the current app session
  static String? _currentSessionId;

  static Future<String> _getCurrentSessionId() async {
    if (_currentSessionId != null) return _currentSessionId!;

    final prefs = await SharedPreferences.getInstance();
    _currentSessionId = prefs.getString(_currentSessionIdKey);

    if (_currentSessionId == null) {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString(_currentSessionIdKey, _currentSessionId!);
    }

    return _currentSessionId!;
  }

  static Future<void> cacheForYouPosts(
      List<Map<String, dynamic>> posts, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Cache only 2 posts
      final postsToCache = posts.take(2).toList();

      if (postsToCache.isNotEmpty) {
        final currentSessionId = await _getCurrentSessionId();

        // CRITICAL FIX: Mark posts as hidden BEFORE caching them
        await _markPostsAsHiddenInCurrentSession(postsToCache, userId);

        final cacheData = {
          'posts': postsToCache,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'userId': userId,
          'sessionId': currentSessionId,
        };
        await prefs.setString(_cachedForYouPostsKey, jsonEncode(cacheData));

        // Mark that we have fresh cache for FUTURE sessions only
        await prefs.setBool(_cacheUsedInSessionKey, false);

        // Media preloading
        unawaited(_preloadMediaForPosts(postsToCache));

        if (kDebugMode) {
          final postIds = postsToCache
              .map((post) => post['postId']?.toString() ?? 'no-id')
              .toList();
          print(
              '✅ Cached ${postsToCache.length} posts for FUTURE sessions: $postIds');
          print(
              '🚫 IMMEDIATELY marked ${postsToCache.length} posts as hidden in CURRENT session');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error caching posts: $e');
      }
    }
  }

  static Future<void> _markPostsAsHiddenInCurrentSession(
      List<Map<String, dynamic>> posts, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentSessionHidden = await _getCurrentSessionHiddenPosts(userId);

      for (final post in posts) {
        final postId = post['postId']?.toString();
        if (postId != null && postId.isNotEmpty) {
          currentSessionHidden.add(postId);
          if (kDebugMode) {
            print('   - IMMEDIATELY hiding post: $postId');
          }
        }
      }

      await prefs.setStringList(
          '$_currentSessionHiddenKey$userId', currentSessionHidden.toList());

      if (kDebugMode) {
        print(
            '🚫 Successfully saved ${currentSessionHidden.length} hidden posts to storage');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking posts as hidden in current session: $e');
      }
    }
  }

  static Future<Set<String>> _getCurrentSessionHiddenPosts(
      String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hiddenPostsList =
          prefs.getStringList('$_currentSessionHiddenKey$userId') ?? [];
      return Set<String>.from(hiddenPostsList);
    } catch (e) {
      return <String>{};
    }
  }

  static Future<void> clearCurrentSessionHiddenPosts(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_currentSessionHiddenKey$userId');
      if (kDebugMode) {
        print('🧹 Cleared current session hidden posts');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing current session hidden posts: $e');
      }
    }
  }

  static Future<List<Map<String, dynamic>>> filterOutCurrentSessionHiddenPosts(
      List<Map<String, dynamic>> posts, String userId) async {
    try {
      final currentSessionHidden = await _getCurrentSessionHiddenPosts(userId);
      final filteredPosts = posts.where((post) {
        final postId = post['postId']?.toString() ?? '';
        final isHidden = currentSessionHidden.contains(postId);
        if (kDebugMode && isHidden) {
          print('   - Filtering out hidden post: $postId');
        }
        return postId.isNotEmpty && !isHidden;
      }).toList();

      if (kDebugMode && filteredPosts.length != posts.length) {
        print(
            '🚫 Filtered out ${posts.length - filteredPosts.length} current session hidden posts');
      }

      return filteredPosts;
    } catch (e) {
      return posts;
    }
  }

  static Future<void> _preloadMediaForPosts(
      List<Map<String, dynamic>> posts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int attemptedPreloads = 0;

      for (final post in posts) {
        final mediaUrl = post['postUrl']?.toString();
        if (mediaUrl != null && mediaUrl.isNotEmpty) {
          attemptedPreloads++;
          unawaited(
              DefaultCacheManager().getSingleFile(mediaUrl).catchError((e) {
            if (kDebugMode) {
              print('⚠️ Media preload failed (will load on demand)');
            }
          }));
        }
      }

      await prefs.setBool(_mediaPreloadedKey, true);

      if (kDebugMode) {
        print('🎯 Media preload initiated for $attemptedPreloads posts');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in media preloading: $e');
      }
    }
  }

  static Future<List<Map<String, dynamic>>?> loadCachedForYouPosts(
      String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final currentSessionId = await _getCurrentSessionId();

      final cacheUsedInSession = prefs.getBool(_cacheUsedInSessionKey) ?? false;
      if (cacheUsedInSession) {
        if (kDebugMode) {
          print('🚫 Cache already used in this session - skipping');
        }
        return null;
      }

      final cachedData = prefs.getString(_cachedForYouPostsKey);

      if (cachedData != null) {
        final Map<String, dynamic> data = jsonDecode(cachedData);
        final timestamp = data['timestamp'] as int;
        final cachedUserId = data['userId'] as String;
        final cacheSessionId = data['sessionId'] as String?;

        // Don't show cache from current session
        if (cacheSessionId == currentSessionId) {
          if (kDebugMode) {
            print(
                '🚫 Cache created in current session - skipping to avoid showing cached posts');
          }
          return null;
        }

        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isValid = cachedUserId == userId &&
            cacheAge < _cacheValidityDuration.inMilliseconds;

        if (isValid) {
          final List<dynamic> postsData = data['posts'];
          final cachedPosts = postsData.map<Map<String, dynamic>>((post) {
            return Map<String, dynamic>.from(post);
          }).toList();

          if (cachedPosts.isNotEmpty) {
            // Mark cache as used for this session
            await prefs.setBool(_cacheUsedInSessionKey, true);

            if (kDebugMode) {
              final postIds = cachedPosts
                  .map((post) => post['postId']?.toString() ?? 'no-id')
                  .toList();
              print(
                  '✅ Loaded ${cachedPosts.length} cached posts from PREVIOUS session: $postIds');
            }
            return cachedPosts;
          }
        } else {
          if (kDebugMode) {
            print('🕒 Cache expired or invalid user - clearing cache');
          }
          await _clearCache(userId);
        }
      } else {
        if (kDebugMode) {
          print('📭 No cached posts found');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading cached posts: $e');
      }
    }
    return null;
  }

  static Future<bool> isMediaPreloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mediaPreloadedKey) ?? false;
  }

  static Future<void> clearCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
      await prefs.remove(_mediaPreloadedKey);
      await prefs.remove(_cacheUsedInSessionKey);
      await prefs.remove('$_currentSessionHiddenKey$userId');

      await DefaultCacheManager().emptyCache();

      if (kDebugMode) {
        print('🧹 Cleared all cache, session flags, and hidden posts');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing cache: $e');
      }
    }
  }

  // Session-specific seen posts
  static Future<Set<String>> getSeenPosts(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await _getCurrentSessionId();
      final seenPostsList =
          prefs.getStringList('${_seenPostsKey}_${sessionId}_$userId') ?? [];
      return Set<String>.from(seenPostsList);
    } catch (e) {
      return <String>{};
    }
  }

  // Mark post as seen in current session only
  static Future<void> markPostAsSeen(String postId, String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await _getCurrentSessionId();
      final seenPosts = await getSeenPosts(userId);
      seenPosts.add(postId);

      final trimmedSeenPosts = seenPosts.toList();
      if (trimmedSeenPosts.length > 500) {
        trimmedSeenPosts.removeRange(0, trimmedSeenPosts.length - 500);
      }

      await prefs.setStringList(
          '${_seenPostsKey}_${sessionId}_$userId', trimmedSeenPosts);

      if (kDebugMode) {
        print('👀 Marked post as seen in CURRENT session: $postId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking post as seen: $e');
      }
    }
  }

  // Clear current session seen posts
  static Future<void> clearCurrentSessionSeenPosts(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await _getCurrentSessionId();
      await prefs.remove('${_seenPostsKey}_${sessionId}_$userId');
      if (kDebugMode) {
        print('🧹 Cleared current session seen posts');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing current session seen posts: $e');
      }
    }
  }

  static Future<void> _clearCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedForYouPostsKey);
      await prefs.remove(_mediaPreloadedKey);
      await prefs.remove(_cacheUsedInSessionKey);
      await prefs.remove('$_currentSessionHiddenKey$userId');
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing cache: $e');
      }
    }
  }

  static Future<Map<String, dynamic>> getCacheStatus(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(_cachedForYouPostsKey);
    final mediaPreloadedStatus = await isMediaPreloaded();
    final cacheUsedInSession = prefs.getBool(_cacheUsedInSessionKey) ?? false;
    final currentSessionId = await _getCurrentSessionId();
    final currentSessionHidden = await _getCurrentSessionHiddenPosts(userId);

    Map<String, dynamic> status = {
      'hasCachedPosts': cachedData != null,
      'isMediaPreloaded': mediaPreloadedStatus,
      'cacheUsedInSession': cacheUsedInSession,
      'currentSessionId': currentSessionId,
      'currentSessionHiddenCount': currentSessionHidden.length,
      'cacheAge': null,
      'postCount': 0,
      'cacheFromCurrentSession': false,
    };

    if (cachedData != null) {
      try {
        final data = jsonDecode(cachedData);
        final timestamp = data['timestamp'] as int;
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final posts = data['posts'] as List;
        final cacheSessionId = data['sessionId'] as String?;

        status['cacheAge'] = cacheAge;
        status['postCount'] = posts.length;
        status['isValid'] = cacheAge < _cacheValidityDuration.inMilliseconds;
        status['cacheFromCurrentSession'] = cacheSessionId == currentSessionId;
      } catch (e) {
        status['error'] = e.toString();
      }
    }

    return status;
  }

  static Future<void> resetSessionFlag(String userId) async {
    final prefs = await SharedPreferences.getInstance();

    // Generate new session ID
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    await prefs.setString(_currentSessionIdKey, _currentSessionId!);

    await prefs.setBool(_cacheUsedInSessionKey, false);
    await clearCurrentSessionHiddenPosts(userId);
    await clearCurrentSessionSeenPosts(userId);

    if (kDebugMode) {
      print(
          '🔄 Session flag reset - new session: $_currentSessionId, cache available, hidden & seen posts cleared');
    }
  }
}
