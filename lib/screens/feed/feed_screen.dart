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
import 'package:Ratedly/services/feed_cache_service.dart';
import 'package:flutter/foundation.dart';

// PRELOADER CLASS FOR ULTRA-FAST DATA ACCESS
class FeedDataPreloader {
  static final Map<String, List<String>> _preloadedBlockedUsers = {};

  static Future<void> preloadBlockedUsers(String userId) async {
    if (_preloadedBlockedUsers[userId] != null) return;

    try {
      final supabase = Supabase.instance.client;
      final userResponse = await supabase
          .from('users')
          .select('blockedUsers')
          .eq('uid', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));

      if (userResponse != null) {
        final blocked = userResponse['blockedUsers'];
        if (blocked is List) {
          _preloadedBlockedUsers[userId] =
              blocked.map((e) => e.toString()).toList();
        } else if (blocked is String) {
          try {
            final parsed = jsonDecode(blocked) as List;
            _preloadedBlockedUsers[userId] =
                parsed.map((e) => e.toString()).toList();
          } catch (_) {
            _preloadedBlockedUsers[userId] = [];
          }
        } else {
          _preloadedBlockedUsers[userId] = [];
        }
      } else {
        _preloadedBlockedUsers[userId] = [];
      }
    } catch (e) {
      _preloadedBlockedUsers[userId] = [];
    }
  }

  static List<String>? getPreloadedBlockedUsers(String userId) {
    return _preloadedBlockedUsers[userId];
  }

  static void clearCache() {
    _preloadedBlockedUsers.clear();
  }
}

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
  final List<Map<String, dynamic>>? preloadedPosts;

  const FeedScreen({Key? key, this.preloadedPosts}) : super(key: key);

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  bool _rebuildPending = false;
  void _scheduleRebuild() {
    if (!_rebuildPending && mounted) {
      _rebuildPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildPending = false;
        setState(() {});
      });
    }
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  late String currentUserId;
  int _selectedTab = 1;

  late PageController _followingPageController;
  late PageController _forYouPageController;
  bool _controllersInitialized = false;

  List<Map<String, dynamic>> _forYouPosts = [];
  List<Map<String, dynamic>> _followingPosts = [];
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

  bool _essentialUiReady = false;
  bool _cachedPostsLoaded = false;
  bool _essentialDataLoaded = false;
  bool _hasFreshData = false;
  bool _hasUserScrolledPastCached = false;
  List<Map<String, dynamic>> _backgroundFreshPosts = [];

  bool _showOverlay = true;
  double _lastScrollOffset = 0;

  late _ColorSet _colors;
  double? _cachedWidth;

  void unawaited(Future<void> future) {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _colors = _getColors(themeProvider);
    _cachedWidth = MediaQuery.of(context).size.width;
  }

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

  Future<Set<String>> _getSeenPosts() async {
    return await FeedCacheService.getSeenPosts(currentUserId);
  }

  Future<void> _markPostAsSeen(String postId) async {
    await FeedCacheService.markPostAsSeen(postId, currentUserId);
  }

  void _loadCachedPostsLightningFast() {
    if (currentUserId.isEmpty) {
      _cachedPostsLoaded = true;
      _essentialUiReady = true;
      _scheduleRebuild();
      return;
    }

    if (widget.preloadedPosts != null && widget.preloadedPosts!.isNotEmpty) {
      _forYouPosts = widget.preloadedPosts!;
      _cachedPostsLoaded = true;
      _essentialUiReady = true;
      _scheduleRebuild();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final seenPosts = await _getSeenPosts();
        final unseenCachedPosts = _forYouPosts.where((post) {
          final postId = post['postId']?.toString() ?? '';
          return postId.isNotEmpty && !seenPosts.contains(postId);
        }).toList();

        if (mounted && unseenCachedPosts.isNotEmpty) {
          _forYouPosts = unseenCachedPosts;
          _scheduleRebuild();
          await _bulkFetchUsers(unseenCachedPosts);
          if (mounted && _forYouPosts.isNotEmpty) {
            _updatePostVisibilityWithoutRebuild(0, _forYouPosts, true);
          }
        }
      });
      return;
    }

    Future.microtask(() async {
      try {
        final results = await Future.wait([
          FeedCacheService.loadCachedForYouPosts(currentUserId),
          _getSeenPosts(),
          FeedCacheService.isMediaPreloaded(),
        ]);

        final cachedPosts = results[0] as List<Map<String, dynamic>>?;
        final seenPosts = results[1] as Set<String>;
        final isMediaPreloaded = results[2] as bool;

        if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
          final unseenCachedPosts = cachedPosts.where((post) {
            final postId = post['postId']?.toString() ?? '';
            return postId.isNotEmpty && !seenPosts.contains(postId);
          }).toList();

          if (unseenCachedPosts.length >= 2) {
            if (mounted) {
              _forYouPosts = unseenCachedPosts;
              _cachedPostsLoaded = true;
              _essentialUiReady = true;
              _scheduleRebuild();

              if (kDebugMode) {}
            }

            _bulkFetchUsers(unseenCachedPosts).then((_) {
              if (mounted && _forYouPosts.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updatePostVisibilityWithoutRebuild(0, _forYouPosts, true);
                });
              }
            });
          } else {
            _cachedPostsLoaded = true;
            _essentialUiReady = true;
            _scheduleRebuild();
          }
        } else {
          _cachedPostsLoaded = true;
          _essentialUiReady = true;
          _scheduleRebuild();
        }
      } catch (e) {
        _cachedPostsLoaded = true;
        _essentialUiReady = true;
        _scheduleRebuild();
      }
    });
  }

  void _initializeHeavyComponents() {
    _followingPageController = PageController();
    _forYouPageController = PageController();
    _controllersInitialized = true;

    _unreadCountStream = _createUnreadCountStream();
    _startGuidelinesTimer();
    _loadEssentialDataInBackground();

    _scheduleBackgroundAdLoading();
  }

  void _scheduleBackgroundAdLoading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _loadInterstitialAd();
        }
      });
    });
  }

  Future<void> _loadEssentialDataInBackground() async {
    if (currentUserId.isEmpty) {
      _essentialDataLoaded = true;
      _scheduleRebuild();
      return;
    }

    try {
      unawaited(_loadBlockedUsers().then((_) {
        _essentialDataLoaded = true;
        _scheduleRebuild();

        if (!_cachedPostsLoaded || _forYouPosts.length < 2) {
          unawaited(_loadData().catchError((e) {}));
        } else {
          unawaited(_loadFreshDataInBackground());
        }
      }).catchError((e) {
        _blockedUsers = [];
        _essentialDataLoaded = true;
        _scheduleRebuild();
      }));
    } catch (e) {
      _essentialDataLoaded = true;
      _scheduleRebuild();
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
      _postViewCount += viewsToRecord.length;
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

    WidgetsBinding.instance.addObserver(this);

    currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    _loadCachedPostsLightningFast();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeHeavyComponents();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseCurrentVideo();
    _currentPlayingPostId = null;
    if (_controllersInitialized) {
      _followingPageController.dispose();
      _forYouPageController.dispose();
    }
    _guidelinesTimer?.cancel();
    _interstitialAd?.dispose();
    _unreadCountTimer?.cancel();
    _unreadCountController?.close();
    super.dispose();
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

    Future.microtask(() async {
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
    if (userIds.isEmpty) {
      return;
    }

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
    if (!mounted || posts.isEmpty || !_controllersInitialized) return;

    final previouslyPlayingPostId = _currentPlayingPostId;

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

    _scheduleRebuild();

    if (previouslyPlayingPostId != null &&
        previouslyPlayingPostId != _currentPlayingPostId) {}
  }

  void _updatePostVisibilityWithoutRebuild(
      int page, List<Map<String, dynamic>> posts, bool isForYou) {
    if (!mounted || posts.isEmpty || !_controllersInitialized) return;

    final previouslyPlayingPostId = _currentPlayingPostId;

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

    if (previouslyPlayingPostId != null &&
        previouslyPlayingPostId != _currentPlayingPostId) {}
  }

  void _onPageChanged(int page, bool isForYou) {
    if (!_controllersInitialized) return;

    final currentPosts = isForYou ? _forYouPosts : _followingPosts;
    if (page >= currentPosts.length) return;

    if (isForYou) {
      _currentForYouPage = page;
      _updatePostVisibility(page, _forYouPosts, true);

      if (page > 0 && _interstitialAd == null) {
        _loadInterstitialAd();
      }

      if (_hasFreshData &&
          !_hasUserScrolledPastCached &&
          page >= _forYouPosts.length - 1) {
        _hasUserScrolledPastCached = true;
        _replaceWithFreshData();
      }
    } else {
      _currentFollowingPage = page;
      _updatePostVisibility(page, _followingPosts, false);

      if (page > 0 && _interstitialAd == null) {
        _loadInterstitialAd();
      }
    }

    final hasMore = isForYou ? _hasMoreForYou : _hasMoreFollowing;
    if (page >= currentPosts.length - 3 && hasMore && !_isLoadingMore) {
      _loadData(loadMore: true);
    }
  }

  void _replaceWithFreshData() {
    if (_backgroundFreshPosts.isNotEmpty && mounted) {
      _forYouPosts = _backgroundFreshPosts;
      _offsetForYou = _backgroundFreshPosts.length;
      _hasMoreForYou = _backgroundFreshPosts.length == 3;
      _scheduleRebuild();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _forYouPosts.isNotEmpty) {
          _updatePostVisibilityWithoutRebuild(0, _forYouPosts, true);
        }
      });

      _backgroundFreshPosts = [];
      _hasFreshData = false;
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
              _scheduleBackgroundAdLoading();
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd ad, AdError error) {
              ad.dispose();
              _scheduleBackgroundAdLoading();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          Future.delayed(const Duration(seconds: 30), () {
            if (mounted) {
              _loadInterstitialAd();
            }
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
    final preloaded = FeedDataPreloader.getPreloadedBlockedUsers(currentUserId);
    if (preloaded != null) {
      _blockedUsers = preloaded;
      return;
    }

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
          .maybeSingle()
          .timeout(const Duration(seconds: 3), onTimeout: () {
        return null;
      });

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
          .eq('user_id', currentUserId)
          .timeout(const Duration(seconds: 3), onTimeout: () {
        return [];
      });

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

  Future<void> _loadFreshDataInBackground() async {
    if (_blockedUsers.isEmpty && currentUserId.isNotEmpty) {
      return;
    }

    try {
      List<Map<String, dynamic>> newPosts = [];
      final excludedUsers = [..._blockedUsers, currentUserId, ..._followingIds];

      final responseRaw = await _supabase.rpc('get_for_you_feed', params: {
        'current_user_id': currentUserId,
        'excluded_users': excludedUsers,
        'page_offset': 0,
        'page_limit': 3,
      }).timeout(const Duration(seconds: 3), onTimeout: () {
        return [];
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
      }

      if (newPosts.isNotEmpty) {
        unawaited(FeedCacheService.cacheForYouPosts(newPosts, currentUserId));
      }

      _backgroundFreshPosts = newPosts;
      _hasFreshData = true;
    } catch (e) {}
  }

  void _showGuidelinesPopup() {
    if (!mounted) return;
    _isPopupShown = true;
    _scheduleRebuild();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GuidelinesPopup(
        userId: currentUserId,
        onAgreed: () {},
      ),
    ).then((_) {
      if (mounted) {
        _isPopupShown = false;
        _scheduleRebuild();
      }
    });
  }

  Future<void> _loadData({bool loadMore = false}) async {
    if ((_selectedTab == 1 && !_hasMoreForYou && loadMore) ||
        (_selectedTab == 0 && !_hasMoreFollowing && loadMore) ||
        _isLoadingMore) {
      return;
    }

    if (mounted) {
      _isLoadingMore = true;
      _scheduleRebuild();
    }

    try {
      List<Map<String, dynamic>> newPosts = [];

      final excludedUsers = [..._blockedUsers, currentUserId];

      if (_selectedTab == 0) {
        if (_followingIds.isEmpty) {
          _hasMoreFollowing = false;
          _isLoadingMore = false;
          _scheduleRebuild();
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
        final forYouExcludedUsers = [...excludedUsers, ..._followingIds];

        final responseRaw = await _supabase.rpc('get_for_you_feed', params: {
          'current_user_id': currentUserId,
          'excluded_users': forYouExcludedUsers,
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
        if (_selectedTab == 0) {
          _followingPosts =
              loadMore ? [..._followingPosts, ...newPosts] : newPosts;
        } else {
          _forYouPosts = loadMore ? [..._forYouPosts, ...newPosts] : newPosts;
        }
        _isLoadingMore = false;

        _scheduleRebuild();

        if (!loadMore && newPosts.isNotEmpty && _selectedTab == 1) {
          await FeedCacheService.cacheForYouPosts(newPosts, currentUserId);
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !loadMore && _controllersInitialized) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            _preloadNextPosts(currentPosts, currentPage, _selectedTab == 1);
          }
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controllersInitialized) {
            final currentPage =
                _selectedTab == 1 ? _currentForYouPage : _currentFollowingPage;
            final currentPosts =
                _selectedTab == 1 ? _forYouPosts : _followingPosts;
            _updatePostVisibilityWithoutRebuild(
                currentPage, currentPosts, _selectedTab == 1);
          }
        });
      }
    } catch (e, stack) {
      if (mounted) {
        _isLoadingMore = false;
        _scheduleRebuild();
      }
    }
  }

  void _switchTab(int index) {
    if (_selectedTab == index || !_controllersInitialized) return;
    _pauseCurrentVideo();
    _currentPlayingPostId = null;

    _hasUserScrolledPastCached = false;
    _backgroundFreshPosts = [];
    _hasFreshData = false;

    _selectedTab = index;
    _showOverlay = true;
    _scheduleRebuild();

    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_cachedPostsLoaded || _forYouPosts.isEmpty) {
          final cachedPosts =
              await FeedCacheService.loadCachedForYouPosts(currentUserId);
          if (cachedPosts != null && cachedPosts.isNotEmpty && mounted) {
            final seenPosts = await _getSeenPosts();
            final unseenCachedPosts = cachedPosts.where((post) {
              final postId = post['postId']?.toString() ?? '';
              return postId.isNotEmpty && !seenPosts.contains(postId);
            }).toList();

            if (unseenCachedPosts.length >= 2) {
              _forYouPosts = unseenCachedPosts;
              _scheduleRebuild();

              await _bulkFetchUsers(unseenCachedPosts);

              if (mounted && unseenCachedPosts.isNotEmpty) {
                _updatePostVisibilityWithoutRebuild(0, unseenCachedPosts, true);
              }
            } else {
              await _loadData();
            }
          } else {
            await _loadData();
          }
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_followingIds.isEmpty) {
          await _loadFollowingIds().catchError((e) {
            _followingIds = [];
          });
        }

        if (!_cachedPostsLoaded || _followingPosts.isEmpty) {
          await _loadData();
        }
      });
    }
  }

  bool _shouldPostPlayVideo(String postId) {
    return postId == _currentPlayingPostId;
  }

  @override
  Widget build(BuildContext context) {
    if (!_essentialUiReady) {
      return _buildMinimalSkeleton(_colors);
    }

    return Scaffold(
      backgroundColor: _colors.backgroundColor,
      body: Stack(
        children: [
          _buildFeedBody(_colors),
          if (_cachedWidth != null && _cachedWidth! <= webScreenSize)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: Duration(milliseconds: 300),
                child: _buildOverlayContent(_colors),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedBody(_ColorSet colors) {
    if (_selectedTab == 1 && _forYouPosts.isNotEmpty) {
      return _buildPostsPageView(
          _forYouPosts, _forYouPageController, colors, true);
    }

    if (_selectedTab == 1 && _forYouPosts.isEmpty && !_essentialDataLoaded) {
      return _buildSkeletonFeed(colors);
    }

    return SizedBox.expand(
      child: _selectedTab == 1
          ? _buildForYouFeed(colors)
          : _buildFollowingFeed(colors),
    );
  }

  Widget _buildMinimalSkeleton(_ColorSet colors) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: 1,
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
            ],
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

  Widget _buildOverlayContent(_ColorSet colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTabItem(1, 'For You', colors),
                const SizedBox(width: 40),
                _buildTabItem(0, 'Following', colors),
              ],
            ),
          ),
          Positioned(
            right: 0,
            child: _buildMessageButton(colors),
          ),
        ],
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

  Widget _buildMessageButton(_ColorSet colors) {
    return GestureDetector(
      onTap: _navigateToMessages,
      child: StreamBuilder<int>(
        stream: _unreadCountStream,
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          final formattedCount = _formatMessageCount(count);
          return Stack(
            clipBehavior: Clip.hardEdge,
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
    if (posts.isEmpty || !_controllersInitialized) {
      return _buildSkeletonFeed(colors);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo is ScrollUpdateNotification) {
          final currentOffset = scrollInfo.metrics.pixels;
          final scrollDifference = currentOffset - _lastScrollOffset;

          if (scrollDifference > 5 && _showOverlay) {
            _showOverlay = false;
            _scheduleRebuild();
          } else if (scrollDifference < -5 && !_showOverlay) {
            _showOverlay = true;
            _scheduleRebuild();
          }

          _lastScrollOffset = currentOffset;
        }
        return false;
      },
      child: PageView.builder(
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
      ),
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
