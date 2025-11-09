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

// Define color schemes for both themes at top level
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

  // Replace ScrollControllers with PageControllers for TikTok-style vertical scrolling
  late PageController _followingPageController;
  late PageController _forYouPageController;

  List<Map<String, dynamic>> _followingPosts = [];
  List<Map<String, dynamic>> _forYouPosts = [];
  bool _isLoading =
      false; // 🚀 CHANGED: Start with false to show content immediately
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

  // Track current page for each tab
  int _currentForYouPage = 0;
  int _currentFollowingPage = 0;
  final Map<String, bool> _postVisibility = {};
  String? _currentPlayingPostId;

  // NEW: Caching system for posts
  final Map<String, Map<String, dynamic>> _postCache = {};
  final Map<String, List<Map<String, dynamic>>> _preloadedPosts = {};
  static const int _preloadCount = 2; // Cache 2 posts ahead

  // Ad-related variables
  InterstitialAd? _interstitialAd;
  int _postViewCount = 0;
  DateTime? _lastInterstitialAdTime;

  Stream<int>? _unreadCountStream;
  StreamController<int>? _unreadCountController;
  Timer? _unreadCountTimer;

  // FAST CACHING: Similar to search screen
  final Map<String, Map<String, dynamic>> _userCache = {};
  static final Map<String, List<String>> _blockedUsersCache = {};
  static DateTime? _lastBlockedUsersCacheTime;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  // FAST UNWRAP: Same as search screen
  dynamic _unwrapResponse(dynamic res) {
    if (res == null) return null;
    if (res is Map && res.containsKey('data')) return res['data'];
    return res;
  }

  void _pauseCurrentVideo() {
    // Simple pause method - you can implement this based on your VideoManager
    _currentPlayingPostId = null;
  }

  // NEW: Cache post data
  void _cachePost(Map<String, dynamic> post) {
    final postId = post['postId']?.toString();
    if (postId != null && postId.isNotEmpty) {
      _postCache[postId] = Map<String, dynamic>.from(post);
    }
  }

  // NEW: Get cached post or null if not cached
  Map<String, dynamic>? _getCachedPost(String postId) {
    return _postCache[postId];
  }

  // NEW: Preload next posts for smooth scrolling
  void _preloadNextPosts(
      List<Map<String, dynamic>> posts, int currentIndex, bool isForYou) {
    final tabKey = isForYou ? 'for_you' : 'following';

    // Clear old preloaded posts for this tab
    _preloadedPosts[tabKey] = [];

    // Preload next _preloadCount posts
    for (int i = 1; i <= _preloadCount; i++) {
      final nextIndex = currentIndex + i;
      if (nextIndex < posts.length) {
        _preloadedPosts[tabKey]?.add(posts[nextIndex]);
        _cachePost(posts[nextIndex]);
      }
    }
  }

  // NEW: Check if post is in cache and return it, otherwise fetch from API
  Future<Map<String, dynamic>> _getPostWithCache(String postId) async {
    // Return cached post if available
    final cachedPost = _getCachedPost(postId);
    if (cachedPost != null) {
      return cachedPost;
    }

    // Fetch from API if not in cache
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
    } catch (e) {
      // If fetch fails, return empty map
    }

    return {};
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
      // Handle error silently
    } finally {
      _viewRecordingScheduled = false;
    }
  }

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    print('🚀 FeedScreen initState - currentUserId: $currentUserId');

    // Initialize PageControllers for TikTok-style vertical scrolling
    _followingPageController = PageController();
    _forYouPageController = PageController();
    _unreadCountStream = _createUnreadCountStream();

    // 🚀 CHANGED: Load data without setting loading state
    _loadInitialData();
    _startGuidelinesTimer();
    _loadInterstitialAd();
  }

  // FIXED STREAM: Using broadcast stream to prevent multiple listeners error
  Stream<int> _createUnreadCountStream() {
    _unreadCountController = StreamController<int>.broadcast();

    if (currentUserId.isEmpty) {
      _unreadCountController!.add(0);
      return _unreadCountController!.stream;
    }

    // Start periodic updates
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

    // Initial data
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

  // FAST USER BULK FETCH: Similar to search screen
  Future<void> _bulkFetchUsers(List<Map<String, dynamic>> posts) async {
    final Set<String> userIds = {};

    // Collect all unique user IDs from posts
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
      // Clear all visibility first
      for (final post in posts) {
        final postId = post['postId']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _postVisibility[postId] = false;
        }
      }

      // Set current page as the ONLY truly visible post for video playback
      if (page < posts.length) {
        final currentPost = posts[page];
        final postId = currentPost['postId']?.toString() ?? '';
        if (postId.isNotEmpty) {
          _postVisibility[postId] = true;
          _currentPlayingPostId = postId;
          _scheduleViewRecording(postId);
        }
      }

      // Set adjacent posts as "visible" only for preloading content
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

      // NEW: Preload next posts when user is viewing current post
      if (page < posts.length - 1) {
        _preloadNextPosts(posts, page, isForYou);
      }
    });

    // If we changed the playing post, pause the previous one
    if (previouslyPlayingPostId != null &&
        previouslyPlayingPostId != _currentPlayingPostId) {
      // You can implement this if you have a VideoManager with this method
      // VideoManager().onPostInvisible(previouslyPlayingPostId);
    }
  }

  void _onPageChanged(int page, bool isForYou) {
    if (isForYou) {
      _currentForYouPage = page;
      _updatePostVisibility(page, _forYouPosts, true);
    } else {
      _currentFollowingPage = page;
      _updatePostVisibility(page, _followingPosts, false);
    }

    // Load more data when approaching the end
    final currentPosts = isForYou ? _forYouPosts : _followingPosts;
    final hasMore = isForYou ? _hasMoreForYou : _hasMoreFollowing;
    if (page >= currentPosts.length - 3 && hasMore && !_isLoadingMore) {
      _loadData(loadMore: true);
    }
  }

  // Method to open comments with transparent overlay
  void _openComments(BuildContext context, Map<String, dynamic> post) {
    final postId = post['postId']?.toString() ?? '';
    final isVideo = post['isVideo'] == true;
    final postImage = post['postUrl']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor:
          Colors.black.withOpacity(0.4), // Reduced opacity for more visibility
      isDismissible: true,
      enableDrag: true,
      builder: (context) => CommentsBottomSheet(
        postId: postId,
        postImage: postImage,
        isVideo: isVideo,
        onClose: () {},
        // The videoController will be passed from PostCard
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

  // FAST BLOCKED USERS: Using cache like search screen
  Future<void> _loadBlockedUsers() async {
    print('🔍 _loadBlockedUsers called');
    final now = DateTime.now();
    // Check cache first
    if (_blockedUsersCache[currentUserId] != null &&
        _lastBlockedUsersCacheTime != null &&
        now.difference(_lastBlockedUsersCacheTime!) < Duration(minutes: 5)) {
      _blockedUsers = _blockedUsersCache[currentUserId]!;
      print('💾 Using cached blocked users: ${_blockedUsers.length} users');
      return;
    }

    try {
      print('📡 Fetching blocked users from database...');
      final userResponseRaw = await _supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', currentUserId)
          .maybeSingle();

      print('📨 Blocked users response: $userResponseRaw');
      final userResponse = _unwrapResponse(userResponseRaw);
      print('📦 Unwrapped blocked users response: $userResponse');

      if (userResponse != null && userResponse is Map) {
        final blocked = userResponse['blockedUsers'];
        print('🚫 Raw blocked data: $blocked, type: ${blocked.runtimeType}');

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
        print('✅ Loaded blocked users: ${_blockedUsers.length} users');
      } else {
        print('❌ No user response or not a Map');
        _blockedUsers = [];
      }

      // Update cache
      _blockedUsersCache[currentUserId] = _blockedUsers;
      _lastBlockedUsersCacheTime = now;
    } catch (e) {
      print('❌ ERROR loading blocked users: $e');
      _blockedUsers = [];
    }
  }

  // FAST FOLLOWING: Minimal query
  Future<void> _loadFollowingIds() async {
    print('🔍 _loadFollowingIds called');
    try {
      print('📡 Fetching following IDs from database...');
      final followingResponseRaw = await _supabase
          .from('user_following')
          .select('following_id')
          .eq('user_id', currentUserId);

      print('📨 Following response: $followingResponseRaw');
      final followingResponse = _unwrapResponse(followingResponseRaw);
      print('📦 Unwrapped following response: $followingResponse');

      if (followingResponse is List) {
        _followingIds = followingResponse
            .map((row) => row['following_id'].toString())
            .toList();
        print('✅ Loaded following IDs: ${_followingIds.length} users');
      } else {
        print('❌ Following response is not a List');
        _followingIds = [];
      }
    } catch (e) {
      print('❌ ERROR loading following IDs: $e');
      _followingIds = [];
    }
  }

  // FAST INITIAL LOAD: No loading state - show content immediately
  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      print('👤 Current user ID: $currentUserId');

      if (currentUserId.isEmpty) {
        print('⚠️  No current user ID, loading without user context');
        _blockedUsers = [];
        _followingIds = [];
        await _loadData();
        return;
      }

      // PARALLEL LOADING: Same pattern as search screen
      print('🔄 Starting parallel data loading...');
      await Future.wait([
        _loadBlockedUsers(),
        _loadFollowingIds(),
      ]);

      print('✅ Parallel loading complete, loading feed data...');
      await _loadData();
    } catch (e) {
      print('❌ ERROR in _loadInitialData: $e');
      // Handle error silently - don't set loading states
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

  // FAST DATA LOADING: Using RPC calls and bulk user fetch
  Future<void> _loadData({bool loadMore = false}) async {
    print(
        '🔍 _loadData called - Tab: ${_selectedTab == 1 ? "For You" : "Following"}, loadMore: $loadMore');

    if ((_selectedTab == 1 && !_hasMoreForYou && loadMore) ||
        (_selectedTab == 0 && !_hasMoreFollowing && loadMore) ||
        _isLoadingMore) {
      print('⏸️  Skipping load - no more data or already loading');
      return;
    }

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      List<Map<String, dynamic>> newPosts = [];
      final excludedUsers = [..._blockedUsers, currentUserId];

      print('📊 Current state:');
      print('   - currentUserId: $currentUserId');
      print('   - blockedUsers count: ${_blockedUsers.length}');
      print('   - followingIds count: ${_followingIds.length}');
      print('   - excludedUsers count: ${excludedUsers.length}');
      print(
          '   - offsetForYou: $_offsetForYou, offsetFollowing: $_offsetFollowing');

      if (_selectedTab == 0) {
        print('🎯 Loading FOLLOWING feed...');
        if (_followingIds.isEmpty) {
          print('❌ No following IDs found, skipping');
          setState(() {
            _hasMoreFollowing = false;
            _isLoadingMore = false;
          });
          return;
        }

        print('📡 Calling get_following_feed RPC...');
        final responseRaw = await _supabase.rpc('get_following_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': excludedUsers,
          'following_ids': _followingIds,
          'page_offset': _offsetFollowing,
          'page_limit': 5,
        });

        print(
            '📨 Following feed RPC response type: ${responseRaw.runtimeType}');
        final response = _unwrapResponse(responseRaw);
        print('📦 Unwrapped response type: ${response.runtimeType}');

        if (response is List) {
          print('✅ Following feed returned ${response.length} posts');
          newPosts = response.map<Map<String, dynamic>>((post) {
            final Map<String, dynamic> convertedPost = {};
            (post as Map).forEach((key, value) {
              convertedPost[key.toString()] = value;
            });
            convertedPost['postId'] = convertedPost['postId']?.toString();
            return convertedPost;
          }).toList();
        } else {
          print('❌ Following feed response is not a List: $response');
          newPosts = [];
        }

        _offsetFollowing += newPosts.length;
        _hasMoreFollowing = newPosts.length == 5;
        print(
            '📈 Following feed update - offset: $_offsetFollowing, hasMore: $_hasMoreFollowing');
      } else {
        print('🎯 Loading FOR YOU (collaborative) feed...');
        print('📡 Calling get_collaborative_feed RPC with params:');
        print('   - current_user_id: $currentUserId');
        print('   - excluded_users: $excludedUsers');
        print('   - page_offset: $_offsetForYou');
        print('   - page_limit: 5');

        final responseRaw =
            await _supabase.rpc('get_collaborative_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': excludedUsers,
          'page_offset': _offsetForYou,
          'page_limit': 5,
        });

        print('📨 Collaborative feed RPC response: $responseRaw');
        print('📨 Response type: ${responseRaw.runtimeType}');

        final response = _unwrapResponse(responseRaw);
        print('📦 Unwrapped response: $response');
        print('📦 Unwrapped response type: ${response.runtimeType}');

        if (response is List) {
          print('✅ Collaborative feed returned ${response.length} posts');
          newPosts = response.map<Map<String, dynamic>>((post) {
            print('📝 Processing post: $post');
            final Map<String, dynamic> convertedPost = {};
            (post as Map).forEach((key, value) {
              if (key.toString() == 'postScore') {
                convertedPost['score'] = value;
              } else {
                convertedPost[key.toString()] = value;
              }
            });
            convertedPost['postId'] = convertedPost['postId']?.toString();
            print('🔄 Converted post ID: ${convertedPost['postId']}');
            return convertedPost;
          }).toList();
        } else {
          print('❌ Collaborative feed response is not a List: $response');
          newPosts = [];
        }

        _offsetForYou += newPosts.length;
        _hasMoreForYou = newPosts.length == 5;
        print(
            '📈 For You feed update - offset: $_offsetForYou, hasMore: $_hasMoreForYou');
      }

      // NEW: Cache all new posts
      print('💾 Caching ${newPosts.length} new posts');
      for (final post in newPosts) {
        _cachePost(post);
      }

      // FAST USER BULK FETCH: Fetch all users at once
      print('👥 Bulk fetching users for ${newPosts.length} posts');
      await _bulkFetchUsers(newPosts);

      if (mounted) {
        print('🔄 Updating UI state');
        setState(() {
          if (_selectedTab == 0) {
            _followingPosts =
                loadMore ? [..._followingPosts, ...newPosts] : newPosts;
            print('📊 Following posts now: ${_followingPosts.length}');
          } else {
            _forYouPosts = loadMore ? [..._forYouPosts, ...newPosts] : newPosts;
            print('📊 For You posts now: ${_forYouPosts.length}');
          }
          _isLoadingMore = false;
        });

        // NEW: Preload initial posts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !loadMore) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            print('🔮 Preloading posts for page $currentPage');
            _preloadNextPosts(currentPosts, currentPage, _selectedTab == 1);
          }
        });

        // Update visibility after new posts are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            print('👀 Updating visibility for page $currentPage');
            _updatePostVisibility(currentPage, currentPosts, _selectedTab == 1);
          }
        });
      }
    } catch (e, stack) {
      print('❌ ERROR in _loadData: $e');
      print('📋 Stack trace: $stack');
      if (mounted)
        setState(() {
          _isLoadingMore = false;
        });
    }
  }

  void _switchTab(int index) {
    if (_selectedTab == index) return;

    print('🔄 Switching tab from $_selectedTab to $index');
    // Pause any currently playing video when switching tabs
    _pauseCurrentVideo();
    _currentPlayingPostId = null;

    setState(() {
      _selectedTab = index;
    });

    if (index == 0) {
      _offsetFollowing = 0;
      _followingPosts.clear();
      _hasMoreFollowing = true;
      _currentFollowingPage = 0;
      print('📊 Reset Following feed state');
    } else {
      _offsetForYou = 0;
      _forYouPosts.clear();
      _hasMoreForYou = true;
      _currentForYouPage = 0;
      print('📊 Reset For You feed state');
    }

    _loadData();
  }

  @override
  void dispose() {
    print('♻️  FeedScreen dispose');
    _pauseCurrentVideo();
    _currentPlayingPostId = null;
    _followingPageController.dispose();
    _forYouPageController.dispose();
    _guidelinesTimer?.cancel();
    _interstitialAd?.dispose();
    // Clean up stream resources
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
          // 🚀 MAIN FEED CONTENT - ALWAYS VISIBLE (no loading overlay)
          _buildFeedBody(colors),

          // Overlay tabs at the top - ALWAYS VISIBLE
          if (width <= webScreenSize) _buildOverlayTabs(colors),

          // Overlay message button at top right - ALWAYS VISIBLE
          if (width <= webScreenSize) _buildOverlayMessageButton(colors),

          // TEMPORARY: Debug button
          _buildDebugButton(),
        ],
      ),
    );
  }

  // TEMPORARY: Debug button for testing
  Widget _buildDebugButton() {
    return Positioned(
      bottom: 100,
      right: 16,
      child: FloatingActionButton(
        onPressed: () {
          print('🔄 MANUAL RELOAD TRIGGERED');
          _loadData();
        },
        child: Icon(Icons.refresh),
        backgroundColor: Colors.red,
        mini: true,
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
            // For You tab with text label
            _buildTabItem(1, 'For You', colors),
            const SizedBox(width: 40),
            // Following tab with text label
            _buildTabItem(0, 'Following', colors),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, _ColorSet colors) {
    return GestureDetector(
      behavior: HitTestBehavior
          .translucent, // This ensures the entire area is tappable
      onTap: () {
        _switchTab(index);
        _showInterstitialAd();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: 8, horizontal: 16), // Added padding for larger tap area
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
    // 🚀 REMOVED loading check - always show content
    if (_followingIds.isEmpty) {
      print('📊 Following feed: No following IDs, showing empty message');
      return _buildNoFollowingMessage(colors);
    }
    print('📊 Following feed: ${_followingPosts.length} posts');
    return _buildPostsPageView(
        _followingPosts, _followingPageController, colors, false);
  }

  Widget _buildForYouFeed(_ColorSet colors) {
    // 🚀 REMOVED loading check - always show content
    print('📊 For You feed: ${_forYouPosts.length} posts');
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
    // 🚀 SHOW SKELETON WHILE LOADING INSTEAD OF SPINNER
    if (posts.isEmpty) {
      print('📊 PostsPageView: No posts, showing skeleton');
      return _buildSkeletonFeed(colors);
    }

    print('📊 PostsPageView: ${posts.length} posts, isForYou: $isForYou');
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

  // 🎯 SKELETON FEED (Like TikTok/Instagram)
  Widget _buildSkeletonFeed(_ColorSet colors) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 3, // Show 3 skeleton posts
      itemBuilder: (ctx, index) {
        return Container(
          color: colors.backgroundColor,
          child: Column(
            children: [
              // Skeleton for post content
              Expanded(
                child: Container(
                  color: colors.skeletonColor,
                  margin: EdgeInsets.all(8),
                ),
              ),
              // Skeleton for action buttons
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
    _pauseCurrentVideo();
    if (currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to view messages')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeedMessages(currentUserId: currentUserId),
      ),
    );
  }
}
