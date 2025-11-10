// lib/screens/feed/feed_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/global_variable.dart';
import 'package:Ratedly/screens/feed/post_card.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/widgets/guidelines_popup.dart';
import 'package:Ratedly/widgets/feedmessages.dart';
import 'package:Ratedly/services/ads.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color skeletonColor;
  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.skeletonColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          skeletonColor: const Color(0xFF333333).withOpacity(0.6),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
          skeletonColor: Colors.grey[300]!.withOpacity(0.6),
        );
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({Key? key}) : super(key: key);

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late String currentUserId;
  int _selectedTab = 1;

  late PageController _followingPageController;
  late PageController _forYouPageController;

  List<Map<String, dynamic>> _followingPosts = [];
  List<Map<String, dynamic>> _forYouPosts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _offsetFollowing = 0;
  int _offsetForYou = 0;
  bool _hasMoreFollowing = true;
  bool _hasMoreForYou = true;

  Timer? _guidelinesTimer;
  bool _isPopupShown = false;
  List<String> _blockedUsers = [];
  List<String> _followingIds = [];
  bool _viewRecordingScheduled = false;
  final Set<String> _pendingViews = {};

  int _currentForYouPage = 0;
  int _currentFollowingPage = 0;
  final Map<String, bool> _postVisibility = {};
  String? _currentPlayingPostId;

  final Map<String, Map<String, dynamic>> _postCache = {};
  final Map<String, List<Map<String, dynamic>>> _preloadedPosts = {};
  static const int _preloadCount = 2;

  InterstitialAd? _interstitialAd;
  int _postViewCount = 0;
  DateTime? _lastInterstitialAdTime;

  Stream<int>? _unreadCountStream;
  StreamController<int>? _unreadCountController;
  Timer? _unreadCountTimer;

  final Map<String, Map<String, dynamic>> _userCache = {};
  static final Map<String, List<String>> _blockedUsersCache = {};
  static DateTime? _lastBlockedUsersCacheTime;

  // 🎯 CACHE KEYS: For tracking seen posts and caching UNSEEN posts
  static const String _cachedPostsKey = 'cached_feed_posts';
  static const String _cachedPostsTimestampKey = 'cached_posts_timestamp';
  static const String _cachedPostsTypeKey = 'cached_posts_type';
  static const String _seenPostsKey = 'seen_posts';
  static const Duration _cacheValidityDuration = Duration(hours: 4);

  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  dynamic _unwrapResponse(dynamic res) {
    if (res == null) return null;
    if (res is Map && res.containsKey('data')) return res['data'];
    return res;
  }

  void _pauseCurrentVideo() {
    VideoManager.pauseAllVideos();
    _currentPlayingPostId = null;
  }

  void _cachePost(Map<String, dynamic> post) {
    final postId = post['postId']?.toString();
    if (postId != null && postId.isNotEmpty) {
      _postCache[postId] = Map<String, dynamic>.from(post);
    }
  }

  Map<String, dynamic>? _getCachedPost(String postId) {
    return _postCache[postId];
  }

  void _preloadNextPosts(
      List<Map<String, dynamic>> posts, int currentIndex, bool isForYou) {
    final tabKey = isForYou ? 'for_you' : 'following';
    _preloadedPosts[tabKey] = [];
    for (int i = 1; i <= _preloadCount; i++) {
      final nextIndex = currentIndex + i;
      if (nextIndex < posts.length) {
        _preloadedPosts[tabKey]?.add(posts[nextIndex]);
        _cachePost(posts[nextIndex]);
      }
    }
  }

  Future<Map<String, dynamic>> _getPostWithCache(String postId) async {
    final cachedPost = _getCachedPost(postId);
    if (cachedPost != null) {
      return cachedPost;
    }
    try {
      final response = await _supabase
          .from('posts')
          .select()
          .eq('postId', postId)
          .single()
          .timeout(const Duration(seconds: 3));
      final post = _unwrapResponse(response);
      if (post != null) {
        _cachePost(post);
        return post;
      }
    } catch (e) {}
    return {};
  }

  // 🎯 TRACK SEEN POSTS: To avoid showing them again
  Future<Set<String>> _getSeenPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPostsList =
          prefs.getStringList('$_seenPostsKey$currentUserId') ?? [];
      return Set<String>.from(seenPostsList);
    } catch (e) {
      return <String>{};
    }
  }

  // 🎯 MARK POST AS SEEN: When user views a post
  Future<void> _markPostAsSeen(String postId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPosts = await _getSeenPosts();
      seenPosts.add(postId);

      // Keep only last 1000 seen posts to avoid storage issues
      final trimmedSeenPosts = seenPosts.toList();
      if (trimmedSeenPosts.length > 1000) {
        trimmedSeenPosts.removeRange(0, trimmedSeenPosts.length - 1000);
      }

      await prefs.setStringList(
          '$_seenPostsKey$currentUserId', trimmedSeenPosts);
    } catch (e) {
      debugPrint('Error marking post as seen: $e');
    }
  }

  // 🎯 CACHE UNSEEN POSTS: Only cache posts user hasn't seen yet
  Future<void> _cachePosts(
      List<Map<String, dynamic>> posts, String feedType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenPosts = await _getSeenPosts();

      // Filter out posts user has already seen
      final unseenPosts = posts.where((post) {
        final postId = post['postId']?.toString() ?? '';
        return postId.isNotEmpty && !seenPosts.contains(postId);
      }).toList();

      // Cache the first 2 UNSEEN posts from the 5-post batch
      if (unseenPosts.length >= 2) {
        final postsToCache = unseenPosts.take(2).toList();

        final cacheData = {
          'posts': postsToCache,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'feedType': feedType,
          'userId': currentUserId,
        };

        await prefs.setString(_cachedPostsKey, jsonEncode(cacheData));
        debugPrint(
            '✅ Cached ${postsToCache.length} UNSEEN posts for $feedType feed');

        // Mark these cached posts as seen so we don't show them again
        for (final post in postsToCache) {
          final postId = post['postId']?.toString() ?? '';
          if (postId.isNotEmpty) {
            await _markPostAsSeen(postId);
          }
        }
      } else if (unseenPosts.isNotEmpty) {
        // If we have only 1 unseen post, still cache it
        final cacheData = {
          'posts': unseenPosts,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'feedType': feedType,
          'userId': currentUserId,
        };

        await prefs.setString(_cachedPostsKey, jsonEncode(cacheData));
        debugPrint(
            '✅ Cached ${unseenPosts.length} UNSEEN post for $feedType feed');

        for (final post in unseenPosts) {
          final postId = post['postId']?.toString() ?? '';
          if (postId.isNotEmpty) {
            await _markPostAsSeen(postId);
          }
        }
      } else {
        debugPrint('🔄 No UNSEEN posts to cache for $feedType feed');
        await _clearCache();
      }
    } catch (e) {
      debugPrint('❌ Failed to cache posts: $e');
    }
  }

  // 🎯 LOAD CACHED UNSEEN POSTS: Only return posts user hasn't seen
  Future<List<Map<String, dynamic>>?> _loadCachedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cachedPostsKey);

      if (cachedData != null) {
        final Map<String, dynamic> data = jsonDecode(cachedData);
        final timestamp = data['timestamp'] as int;
        final cachedUserId = data['userId'] as String;
        final feedType = data['feedType'] as String;

        // Check if cache is valid (same user, same feed type, and within time limit)
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
        final isValid = cachedUserId == currentUserId &&
            feedType == (_selectedTab == 1 ? 'for_you' : 'following') &&
            cacheAge < _cacheValidityDuration.inMilliseconds;

        if (isValid) {
          final List<dynamic> postsData = data['posts'];
          final cachedPosts = postsData.map<Map<String, dynamic>>((post) {
            return Map<String, dynamic>.from(post);
          }).toList();

          // Double-check that cached posts haven't been seen in the meantime
          final seenPosts = await _getSeenPosts();
          final validCachedPosts = cachedPosts.where((post) {
            final postId = post['postId']?.toString() ?? '';
            return postId.isNotEmpty && !seenPosts.contains(postId);
          }).toList();

          if (validCachedPosts.isNotEmpty) {
            debugPrint(
                '✅ Loaded ${validCachedPosts.length} UNSEEN cached posts from $feedType feed');
            return validCachedPosts;
          } else {
            debugPrint('🔄 All cached posts have been seen, clearing cache');
            await _clearCache();
          }
        } else {
          debugPrint('🕒 Cache expired or invalid, clearing...');
          await _clearCache();
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to load cached posts: $e');
      await _clearCache();
    }
    return null;
  }

  // 🎯 CLEAR CACHE: Remove old cached posts
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedPostsKey);
      debugPrint('🗑️ Cleared post cache');
    } catch (e) {
      debugPrint('❌ Failed to clear cache: $e');
    }
  }

  // 🎯 CHECK AND CLEAR OLD CACHE: On app start
  Future<void> _checkAndClearOldCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cachedPostsKey);

      if (cachedData != null) {
        final Map<String, dynamic> data = jsonDecode(cachedData);
        final timestamp = data['timestamp'] as int;
        final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;

        if (cacheAge > _cacheValidityDuration.inMilliseconds) {
          await _clearCache();
        }
      }
    } catch (e) {
      // Ignore errors in cache checking
    }
  }

  void _scheduleViewRecording(String postId) {
    _pendingViews.add(postId);
    if (!_viewRecordingScheduled) {
      _viewRecordingScheduled = true;
      Future.delayed(const Duration(seconds: 1), _recordPendingViews);
    }
  }

  Future<void> _recordPendingViews() async {
    if (_pendingViews.isEmpty || !mounted) {
      _viewRecordingScheduled = false;
      return;
    }
    final viewsToRecord = _pendingViews.toList();
    _pendingViews.clear();
    try {
      await _supabase.from('user_post_views').upsert(
            viewsToRecord
                .map((postId) => {
                      'user_id': currentUserId,
                      'post_id': postId,
                      'viewed_at': DateTime.now().toUtc().toIso8601String(),
                    })
                .toList(),
          );
      setState(() {
        _postViewCount += viewsToRecord.length;
      });
      if (_postViewCount >= 10) {
        _showInterstitialAd();
        _postViewCount = 0;
      }
    } catch (e) {
    } finally {
      _viewRecordingScheduled = false;
    }
  }

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _followingPageController = PageController();
    _forYouPageController = PageController();
    _unreadCountStream = _createUnreadCountStream();

    // Clear old cache on app start
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndClearOldCache();
    });

    _loadInitialData();
    _startGuidelinesTimer();
    _loadInterstitialAd();
  }

  Stream<int> _createUnreadCountStream() {
    _unreadCountController = StreamController<int>.broadcast();
    if (currentUserId.isEmpty) {
      _unreadCountController!.add(0);
      return _unreadCountController!.stream;
    }
    _unreadCountTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final data = await _supabase
            .from('messages')
            .select('id')
            .eq('receiver_id', currentUserId)
            .eq('is_read', false);
        final int count = (data is List) ? data.length : 0;
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(count);
        }
      } catch (e) {
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(0);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final data = await _supabase
            .from('messages')
            .select('id')
            .eq('receiver_id', currentUserId)
            .eq('is_read', false);
        final int count = (data is List) ? data.length : 0;
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(count);
        }
      } catch (e) {
        if (_unreadCountController != null &&
            !_unreadCountController!.isClosed) {
          _unreadCountController!.add(0);
        }
      }
    });
    return _unreadCountController!.stream;
  }

  Future<void> _bulkFetchUsers(List<Map<String, dynamic>> posts) async {
    final Set<String> userIds = {};
    for (final post in posts) {
      final userId = post['uid']?.toString() ?? '';
      if (userId.isNotEmpty && !_userCache.containsKey(userId)) {
        userIds.add(userId);
      }
    }
    if (userIds.isEmpty) return;
    try {
      final response = await _supabase
          .from('users')
          .select('uid, username, photoUrl')
          .inFilter('uid', userIds.toList());
      if (response.isNotEmpty) {
        for (final user in response) {
          final userMap = Map<String, dynamic>.from(user);
          _userCache[userMap['uid']] = userMap;
        }
      }
    } catch (e) {}
  }

  void _updatePostVisibility(
      int page, List<Map<String, dynamic>> posts, bool isForYou) {
    if (!mounted || posts.isEmpty) return;
    final previouslyPlayingPostId = _currentPlayingPostId;
    setState(() {
      for (final post in posts) {
        final postId = post['postId']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _postVisibility[postId] = false;
        }
      }
      if (page < posts.length) {
        final currentPost = posts[page];
        final postId = currentPost['postId']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _postVisibility[postId] = true;
          _currentPlayingPostId = postId;
          _scheduleViewRecording(postId);

          // 🎯 MARK POST AS SEEN when it becomes visible
          _markPostAsSeen(postId);
        }
      }
      if (page > 0) {
        final previousPost = posts[page - 1];
        final previousPostId = previousPost['postId']?.toString() ?? '';
        if (previousPostId.isNotEmpty) {
          _postVisibility[previousPostId] = true;
        }
      }
      if (page < posts.length - 1) {
        final nextPost = posts[page + 1];
        final nextPostId = nextPost['postId']?.toString() ?? '';
        if (nextPostId.isNotEmpty) {
          _postVisibility[nextPostId] = true;
        }
      }
      if (page < posts.length - 1) {
        _preloadNextPosts(posts, page, isForYou);
      }
    });
    if (previouslyPlayingPostId != null &&
        previouslyPlayingPostId != _currentPlayingPostId) {}
  }

  void _onPageChanged(int page, bool isForYou) {
    if (isForYou) {
      _currentForYouPage = page;
      _updatePostVisibility(page, _forYouPosts, true);
    } else {
      _currentFollowingPage = page;
      _updatePostVisibility(page, _followingPosts, false);
    }
    final currentPosts = isForYou ? _forYouPosts : _followingPosts;
    final hasMore = isForYou ? _hasMoreForYou : _hasMoreFollowing;
    if (page >= currentPosts.length - 3 && hasMore && !_isLoadingMore) {
      _loadData(loadMore: true);
    }
  }

  void _openComments(BuildContext context, Map<String, dynamic> post) {
    final postId = post['postId']?.toString() ?? '';
    final isVideo = post['isVideo'] == true;
    final postImage = post['postUrl']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
      isDismissible: true,
      enableDrag: true,
      builder: (context) => CommentsBottomSheet(
        postId: postId,
        postImage: postImage,
        isVideo: isVideo,
        onClose: () {},
      ),
    );
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdHelper.feedInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd ad, AdError error) {
              ad.dispose();
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          Future.delayed(const Duration(seconds: 30), () {
            _loadInterstitialAd();
          });
        },
      ),
    );
  }

  void _showInterstitialAd() {
    final now = DateTime.now();
    if (_lastInterstitialAdTime != null &&
        now.difference(_lastInterstitialAdTime!) <
            const Duration(minutes: 10)) {
      return;
    }
    if (_interstitialAd != null) {
      _interstitialAd!.show();
      _lastInterstitialAdTime = now;
    } else {
      _loadInterstitialAd();
    }
  }

  void _startGuidelinesTimer() {
    _guidelinesTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isPopupShown) {
        _checkAndShowGuidelines();
      }
    });
  }

  void _checkAndShowGuidelines() async {
    final prefs = await SharedPreferences.getInstance();
    final bool agreed =
        prefs.getBool('agreed_to_guidelines_$currentUserId') ?? false;
    final bool dontShow =
        prefs.getBool('dont_show_again_$currentUserId') ?? false;
    if (!(agreed && dontShow)) {
      _showGuidelinesPopup();
    } else {
      _guidelinesTimer?.cancel();
    }
  }

  Future<void> _loadBlockedUsers() async {
    final now = DateTime.now();
    if (_blockedUsersCache[currentUserId] != null &&
        _lastBlockedUsersCacheTime != null &&
        now.difference(_lastBlockedUsersCacheTime!) < Duration(minutes: 5)) {
      _blockedUsers = _blockedUsersCache[currentUserId]!;
      return;
    }
    try {
      final userResponseRaw = await _supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', currentUserId)
          .maybeSingle();
      final userResponse = _unwrapResponse(userResponseRaw);
      if (userResponse != null && userResponse is Map) {
        final blocked = userResponse['blockedUsers'];
        if (blocked is List) {
          _blockedUsers = blocked.map((e) => e.toString()).toList();
        } else if (blocked is String) {
          try {
            final parsed = jsonDecode(blocked) as List;
            _blockedUsers = parsed.map((e) => e.toString()).toList();
          } catch (_) {
            _blockedUsers = [];
          }
        } else {
          _blockedUsers = [];
        }
      } else {
        _blockedUsers = [];
      }
      _blockedUsersCache[currentUserId] = _blockedUsers;
      _lastBlockedUsersCacheTime = now;
    } catch (e) {
      _blockedUsers = [];
    }
  }

  Future<void> _loadFollowingIds() async {
    try {
      final followingResponseRaw = await _supabase
          .from('user_following')
          .select('following_id')
          .eq('user_id', currentUserId);
      final followingResponse = _unwrapResponse(followingResponseRaw);
      if (followingResponse is List) {
        _followingIds = followingResponse
            .map((row) => row['following_id'].toString())
            .toList();
      } else {
        _followingIds = [];
      }
    } catch (e) {
      _followingIds = [];
    }
  }

  // 🎯 LOAD INITIAL DATA: Show cached UNSEEN posts immediately
  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (currentUserId.isEmpty) {
        _blockedUsers = [];
        _followingIds = [];
        await _loadData();
        return;
      }

      // 🎯 STEP 1: Try to load cached UNSEEN posts IMMEDIATELY
      final cachedPosts = await _loadCachedPosts();
      if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
        setState(() {
          if (_selectedTab == 1) {
            _forYouPosts = cachedPosts;
          } else {
            _followingPosts = cachedPosts;
          }
        });

        // Preload users for cached posts
        await _bulkFetchUsers(cachedPosts);

        // Update visibility for cached posts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            if (currentPosts.isNotEmpty) {
              _updatePostVisibility(0, currentPosts, _selectedTab == 1);
            }
          }
        });
      }

      // 🎯 STEP 2: Load fresh data in background
      await Future.wait([
        _loadBlockedUsers(),
        _loadFollowingIds(),
      ]);

      await _loadData();
    } catch (e) {
      debugPrint('Initial data loading error: $e');
    }
  }

  void _showGuidelinesPopup() {
    if (!mounted) return;
    setState(() => _isPopupShown = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GuidelinesPopup(
        userId: currentUserId,
        onAgreed: () {},
      ),
    ).then((_) {
      if (mounted) setState(() => _isPopupShown = false);
    });
  }

  // 🎯 LOAD DATA: Cache only UNSEEN posts from the 5-post batch
  Future<void> _loadData({bool loadMore = false}) async {
    if ((_selectedTab == 1 && !_hasMoreForYou && loadMore) ||
        (_selectedTab == 0 && !_hasMoreFollowing && loadMore) ||
        _isLoadingMore) {
      return;
    }

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      List<Map<String, dynamic>> newPosts = [];
      final excludedUsers = [..._blockedUsers, currentUserId];

      if (_selectedTab == 0) {
        if (_followingIds.isEmpty) {
          setState(() {
            _hasMoreFollowing = false;
            _isLoadingMore = false;
          });
          return;
        }
        final responseRaw = await _supabase.rpc('get_following_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': excludedUsers,
          'following_ids': _followingIds,
          'page_offset': _offsetFollowing,
          'page_limit': 5,
        });
        final response = _unwrapResponse(responseRaw);
        if (response is List) {
          newPosts = response.map<Map<String, dynamic>>((post) {
            final Map<String, dynamic> convertedPost = {};
            (post as Map).forEach((key, value) {
              convertedPost[key.toString()] = value;
            });
            convertedPost['postId'] = convertedPost['postId']?.toString();
            return convertedPost;
          }).toList();
        } else {
          newPosts = [];
        }
        _offsetFollowing += newPosts.length;
        _hasMoreFollowing = newPosts.length == 5;
      } else {
        // FOR YOU FEED - Use your collaborative algorithm
        final responseRaw =
            await _supabase.rpc('get_collaborative_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': excludedUsers,
          'page_offset': _offsetForYou,
          'page_limit': 5,
        });

        final response = _unwrapResponse(responseRaw);

        if (response is List) {
          newPosts = response.map<Map<String, dynamic>>((post) {
            final Map<String, dynamic> convertedPost = {};
            (post as Map).forEach((key, value) {
              if (key.toString() == 'postScore') {
                convertedPost['score'] = value;
              } else {
                convertedPost[key.toString()] = value;
              }
            });
            convertedPost['postId'] = convertedPost['postId']?.toString();
            return convertedPost;
          }).toList();
        } else {
          newPosts = [];
        }

        _offsetForYou += newPosts.length;
        _hasMoreForYou = newPosts.length == 5;
      }

      for (final post in newPosts) {
        _cachePost(post);
      }

      await _bulkFetchUsers(newPosts);

      if (mounted) {
        setState(() {
          if (_selectedTab == 0) {
            _followingPosts =
                loadMore ? [..._followingPosts, ...newPosts] : newPosts;
          } else {
            _forYouPosts = loadMore ? [..._forYouPosts, ...newPosts] : newPosts;
          }
          _isLoadingMore = false;
        });

        // 🎯 CACHE THE FIRST 2 UNSEEN POSTS from the 5-post batch
        if (!loadMore && newPosts.isNotEmpty) {
          final feedType = _selectedTab == 1 ? 'for_you' : 'following';
          await _cachePosts(newPosts, feedType);
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !loadMore) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            _preloadNextPosts(currentPosts, currentPage, _selectedTab == 1);
          }
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            _updatePostVisibility(currentPage, currentPosts, _selectedTab == 1);
          }
        });
      }
    } catch (e, stack) {
      if (mounted)
        setState(() {
          _isLoadingMore = false;
        });
      debugPrint('Load data error: $e\n$stack');
    }
  }

  // 🎯 SWITCH TABS: Use cached UNSEEN posts when switching
  void _switchTab(int index) {
    if (_selectedTab == index) return;
    _pauseCurrentVideo();
    _currentPlayingPostId = null;

    setState(() {
      _selectedTab = index;
    });

    // Try to load cached UNSEEN posts for the new tab immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cachedPosts = await _loadCachedPosts();
      if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
        setState(() {
          if (index == 1) {
            _forYouPosts = cachedPosts;
          } else {
            _followingPosts = cachedPosts;
          }
        });

        await _bulkFetchUsers(cachedPosts);

        if (mounted && cachedPosts.isNotEmpty) {
          _updatePostVisibility(0, cachedPosts, index == 1);
        }
      }
    });

    if (index == 0) {
      _offsetFollowing = 0;
      _followingPosts.clear();
      _hasMoreFollowing = true;
      _currentFollowingPage = 0;
    } else {
      _offsetForYou = 0;
      _forYouPosts.clear();
      _hasMoreForYou = true;
      _currentForYouPage = 0;
    }

    _loadData();
  }

  @override
  void dispose() {
    _pauseCurrentVideo();
    _currentPlayingPostId = null;
    _followingPageController.dispose();
    _forYouPageController.dispose();
    _guidelinesTimer?.cancel();
    _interstitialAd?.dispose();
    _unreadCountTimer?.cancel();
    _unreadCountController?.close();
    super.dispose();
  }

  bool _shouldPostPlayVideo(String postId) {
    return postId == _currentPlayingPostId;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: Stack(
        children: [
          _buildFeedBody(colors),
          if (width <= webScreenSize) _buildOverlayTabs(colors),
          if (width <= webScreenSize) _buildOverlayMessageButton(colors),
        ],
      ),
    );
  }

  Widget _buildOverlayTabs(_ColorSet colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTabItem(1, 'For You', colors),
            const SizedBox(width: 40),
            _buildTabItem(0, 'Following', colors),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, _ColorSet colors) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _switchTab(index);
        _showInterstitialAd();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 60,
              decoration: BoxDecoration(
                color:
                    _selectedTab == index ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayMessageButton(_ColorSet colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 16,
      child: GestureDetector(
        onTap: _navigateToMessages,
        child: StreamBuilder<int>(
          stream: _unreadCountStream,
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            final formattedCount = _formatMessageCount(count);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Material(
                  color: Colors.transparent,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: Icon(
                      Icons.message,
                      color: colors.iconColor,
                      size: 24,
                    ),
                    onPressed: _navigateToMessages,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      decoration: BoxDecoration(
                        color: colors.cardColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          formattedCount,
                          style: TextStyle(
                            color: colors.textColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeedBody(_ColorSet colors) {
    return SizedBox.expand(
      child: _selectedTab == 1
          ? _buildForYouFeed(colors)
          : _buildFollowingFeed(colors),
    );
  }

  Widget _buildFollowingFeed(_ColorSet colors) {
    if (_followingIds.isEmpty) {
      return _buildNoFollowingMessage(colors);
    }
    return _buildPostsPageView(
        _followingPosts, _followingPageController, colors, false);
  }

  Widget _buildForYouFeed(_ColorSet colors) {
    // 🎯 SHOW CACHED UNSEEN POSTS IMMEDIATELY
    return _buildPostsPageView(
        _forYouPosts, _forYouPageController, colors, true);
  }

  Widget _buildNoFollowingMessage(_ColorSet colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          "Follow users to see their posts here!",
          style: TextStyle(
            color: colors.textColor.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPostsPageView(
    List<Map<String, dynamic>> posts,
    PageController controller,
    _ColorSet colors,
    bool isForYou,
  ) {
    // 🎯 Show cached UNSEEN posts immediately
    if (posts.isEmpty) {
      return _buildSkeletonFeed(colors);
    }

    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      itemCount: posts.length + (_isLoadingMore ? 1 : 0),
      onPageChanged: (page) => _onPageChanged(page, isForYou),
      itemBuilder: (ctx, index) {
        if (index >= posts.length) {
          return _buildLoadingIndicator(colors);
        }

        final post = posts[index];
        final postId = post['postId']?.toString() ?? '';

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: colors.backgroundColor,
          child: PostCard(
            snap: post,
            isVisible: _shouldPostPlayVideo(postId),
            onCommentTap: () => _openComments(context, post),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonFeed(_ColorSet colors) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 3,
      itemBuilder: (ctx, index) {
        return Container(
          color: colors.backgroundColor,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: colors.skeletonColor,
                  margin: EdgeInsets.all(8),
                ),
              ),
              Container(
                height: 50,
                color: colors.cardColor,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingIndicator(_ColorSet colors) {
    return Center(
      child: CircularProgressIndicator(color: colors.textColor),
    );
  }

  String _formatMessageCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 10000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    } else {
      return '${(count ~/ 1000)}k';
    }
  }

  void _navigateToMessages() {
    VideoManager.pauseAllVideos();

    if (currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to view messages')),
      );
      return;
    }

    Future.delayed(Duration(milliseconds: 50), () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FeedMessages(currentUserId: currentUserId),
        ),
      );
    });
  }
}
