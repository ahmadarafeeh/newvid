import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/models/user.dart' as model;
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/services/api_service.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/flutter_rating_bar.dart';
import 'package:Ratedly/widgets/postshare.dart';
import 'package:Ratedly/widgets/blocked_content_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui';
import 'dart:async';
import 'package:Ratedly/widgets/verified_username_widget.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

void unawaited(Future<void> future) {}

class VideoManager {
  static final VideoManager _instance = VideoManager._internal();
  factory VideoManager() => _instance;
  VideoManager._internal();

  VideoPlayerController? _currentPlayingController;
  String? _currentPostId;

  // 🎯 ADDED: Track all active video controllers
  final Map<String, VideoPlayerController> _activeControllers = {};

  static void pauseAllVideos() {
    _instance._pauseAllVideos();
  }

  void playVideo(VideoPlayerController controller, String postId) {
    if (_currentPlayingController != null &&
        _currentPlayingController != controller) {
      _currentPlayingController!.pause();
    }

    _currentPlayingController = controller;
    _currentPostId = postId;
    _activeControllers[postId] = controller;
    controller.play();
  }

  void pauseVideo(VideoPlayerController controller) {
    if (_currentPlayingController == controller) {
      controller.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }
    _activeControllers.removeWhere((key, value) => value == controller);
  }

  void disposeController(VideoPlayerController controller, String postId) {
    if (_currentPlayingController == controller) {
      _currentPlayingController = null;
      _currentPostId = null;
    }
    _activeControllers.remove(postId);
    controller.pause();
    controller.dispose();
  }

  bool isCurrentlyPlaying(VideoPlayerController controller) {
    return _currentPlayingController == controller;
  }

  void onPostInvisible(String postId) {
    if (_currentPostId == postId && _currentPlayingController != null) {
      _currentPlayingController!.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }
    _activeControllers.remove(postId);
  }

  String? get currentPlayingPostId => _currentPostId;

  void pauseCurrentVideo() {
    if (_currentPlayingController != null) {
      _currentPlayingController!.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }
  }

  // 🎯 ADDED: New method to pause ALL active videos
  void _pauseAllVideos() {
    // Pause the current playing video
    if (_currentPlayingController != null) {
      _currentPlayingController!.pause();
      _currentPlayingController = null;
      _currentPostId = null;
    }

    // Pause all other active video controllers
    _activeControllers.forEach((postId, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
      }
    });

    // Clear the active controllers map
    _activeControllers.clear();
  }
}

class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color skeletonColor;
  final Color progressIndicatorColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.skeletonColor,
    required this.progressIndicatorColor,
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
          progressIndicatorColor: Colors.white70,
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
          progressIndicatorColor: Colors.grey[700]!,
        );
}

class PostCard extends StatefulWidget {
  final Map<String, dynamic> snap;
  final Function(Map<String, dynamic>)? onRateUpdate;
  final bool isVisible;
  final VoidCallback? onCommentTap;
  final VoidCallback? onPostSeen;

  const PostCard({
    Key? key,
    required this.snap,
    this.onRateUpdate,
    this.isVisible = true,
    this.onCommentTap,
    this.onPostSeen,
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with AutomaticKeepAliveClientMixin<PostCard>, WidgetsBindingObserver {
  late int _commentCount;
  bool _isBlocked = false;
  bool _viewRecorded = false;
  late RealtimeChannel _postChannel;
  bool _isLoadingRatings = true;
  int _totalRatingsCount = 0;
  double _averageRating = 0.0;
  double? _userRating;
  bool _showSlider = true;

  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoLoading = false;
  bool _isMuted = false;

  bool _isCaptionExpanded = false;
  bool _hasBeenSeen = false;

  late List<Map<String, dynamic>> _localRatings;
  final ApiService _apiService = ApiService();
  final VideoManager _videoManager = VideoManager();
  final SupabasePostsMethods _postsMethods = SupabasePostsMethods();

  final List<String> _reportReasons = [
    'I just don\'t like it',
    'Discriminatory content (e.g., religion, race, gender, or other)',
    'Bullying or harassment',
    'Violence, hate speech, or harmful content',
    'Selling prohibited items',
    'Pornography or nudity',
    'Scam or fraudulent activity',
    'Spam',
    'Misinformation',
  ];

  String get _postId => widget.snap['postId']?.toString() ?? '';

  bool get _isVideo {
    final url = (widget.snap['postUrl']?.toString() ?? '').toLowerCase();
    return url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.endsWith('.mkv') ||
        url.contains('video');
  }

  // 🎯 FIXED: Use getter from VideoManager instead of local state variable
  bool get _isVideoPlaying =>
      _videoController != null &&
      _videoManager.isCurrentlyPlaying(_videoController!);

  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _localRatings = [];
    if (widget.snap['ratings'] != null) {
      _localRatings = (widget.snap['ratings'] as List<dynamic>)
          .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
          .toList();
    }

    _commentCount = (widget.snap['commentsCount'] ?? 0).toInt();
    _setupRealtime();
    _checkBlockStatus();
    _recordView();
    _fetchInitialRatings();
    _fetchCommentsCount();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkImageCacheStatus();
    });

    if (_isVideo) {
      unawaited(_initializeVideoPlayer());
    }
  }

  void _markPostAsSeenIfVisible() {
    if (widget.isVisible && !_hasBeenSeen && widget.onPostSeen != null) {
      _hasBeenSeen = true;
      widget.onPostSeen!();
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isVisible && !_hasBeenSeen && widget.onPostSeen != null) {
      _markPostAsSeenIfVisible();
    }

    // 🎯 FIXED: Simplified video visibility logic
    if (oldWidget.isVisible != widget.isVisible && _isVideo) {
      if (widget.isVisible) {
        // Only play if video is initialized and not already playing
        if (_isVideoInitialized && !_isVideoPlaying) {
          _playVideo();
        } else if (!_isVideoInitialized && !_isVideoLoading) {
          // Initialize if not already loading
          unawaited(_initializeVideoPlayer());
        }
      } else {
        // Only pause if currently playing - don't interfere with manual pauses
        if (_isVideoInitialized && _isVideoPlaying) {
          _pauseVideo();
        }
      }
    }
  }

  Future<void> _checkImageCacheStatus() async {
    if (_isVideo) return;

    final imageUrl = widget.snap['postUrl']?.toString() ?? '';
    if (imageUrl.isEmpty) return;

    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(imageUrl);
      // Cache check completed silently
    } catch (e) {
      // Error checking cache
    }
  }

  void _warmImageCache(String imageUrl, String postId) {
    if (_isVideo) return;
    if (imageUrl.isEmpty) return;

    unawaited(DefaultCacheManager().getSingleFile(imageUrl).then((file) {
      // Cache warmed successfully
    }).catchError((e) {
      // Silent fail - image will load on demand next time
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVideoController();
    _postChannel.unsubscribe();

    if (_videoController != null && _isVideoPlaying) {
      _videoManager.pauseVideo(_videoController!);
    }

    super.dispose();
  }

  void _disposeVideoController() {
    if (_videoController != null) {
      _videoController!.removeListener(_videoListener);
      _videoManager.disposeController(_videoController!, _postId);
      _videoController = null;
    }
    _isVideoInitialized = false;
    _isVideoLoading = false;
  }

  // 🎯 FIXED: Improved video listener with better state management
  void _videoListener() {
    if (!mounted) return;

    // Handle video looping
    if (_videoController != null &&
        _videoController!.value.position == _videoController!.value.duration &&
        _videoController!.value.duration != Duration.zero) {
      _videoController!.seekTo(Duration.zero);
      if (widget.isVisible && !_isVideoPlaying) {
        _videoController!.play();
      }
    }

    // 🎯 ADDED: Sync playing state with VideoManager
    if (_videoController != null && _isVideoInitialized) {
      final isActuallyPlaying = _videoController!.value.isPlaying;
      final shouldBePlaying =
          _videoManager.isCurrentlyPlaying(_videoController!);

      if (isActuallyPlaying != shouldBePlaying && widget.isVisible) {
        if (shouldBePlaying && !isActuallyPlaying) {
          _videoController!.play();
        } else if (!shouldBePlaying && isActuallyPlaying) {
          _videoController!.pause();
        }
      }
    }
  }

  Future<void> _initializeVideoPlayer() async {
    if (_isVideoLoading || _isVideoInitialized) {
      return;
    }

    setState(() => _isVideoLoading = true);

    try {
      final videoUrl = widget.snap['postUrl']?.toString() ?? '';
      if (videoUrl.isEmpty) {
        throw Exception('Empty video URL');
      }

      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      _videoController!.addListener(_videoListener);

      await _videoController!.initialize().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Video loading timeout');
        },
      );

      _videoController!.setLooping(true);

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isVideoLoading = false;
        });

        if (widget.isVisible) {
          _playVideo();
        } else {
          _pauseVideo();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    }
  }

  void _playVideo() {
    if (_videoController != null &&
        _isVideoInitialized &&
        mounted &&
        widget.isVisible) {
      _videoManager.playVideo(_videoController!, _postId);

      // 🎯 FIXED: Ensure UI updates immediately
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _pauseVideo() {
    if (_videoController != null && _isVideoInitialized && mounted) {
      _videoManager.pauseVideo(_videoController!);

      // 🎯 FIXED: Ensure UI updates immediately
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _toggleMute() {
    if (_videoController != null && _isVideoInitialized && mounted) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      });
    }
  }

  // 🎯 FIXED: Improved video toggle with proper state sync
  void _toggleVideoPlayback() {
    if (!_isVideoInitialized || _videoController == null) return;

    if (_isVideoPlaying) {
      _pauseVideo();
    } else {
      _playVideo();
    }

    // 🎯 Ensure UI updates immediately
    if (mounted) {
      setState(() {});
    }
  }

  int _countItems(dynamic value) {
    try {
      if (value == null) return 0;
      if (value is List) return value.length;
      if (value is Iterable) return value.length;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _fetchCommentsCount() async {
    try {
      final commentsResponse = await Supabase.instance.client
          .from('comments')
          .select('id')
          .eq('postid', widget.snap['postId']);

      final repliesResponse = await Supabase.instance.client
          .from('replies')
          .select('id')
          .eq('postid', widget.snap['postId']);

      final int commentsCount = _countItems(commentsResponse);
      final int repliesCount = _countItems(repliesResponse);
      final int totalCount = commentsCount + repliesCount;

      if (mounted) {
        setState(() {
          _commentCount = totalCount;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _commentCount = (widget.snap['commentsCount'] ?? 0).toInt();
        });
      }
    }
  }

  void _setupRealtime() {
    _postChannel =
        Supabase.instance.client.channel('post_${widget.snap['postId']}');

    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'post_rating',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.snap['postId'],
      ),
      callback: (payload) {
        _handleRatingUpdate(payload);
      },
    );

    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'comments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.snap['postId'],
      ),
      callback: (payload) {
        _fetchCommentsCount();
      },
    );

    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'replies',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.snap['postId'],
      ),
      callback: (payload) {
        _fetchCommentsCount();
      },
    );

    _postChannel.subscribe();
  }

  Future<void> _fetchInitialRatings() async {
    setState(() => _isLoadingRatings = true);

    try {
      final countResponse = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.snap['postId']);

      final avgResponse = await Supabase.instance.client
          .from('post_rating')
          .select('rating')
          .eq('postid', widget.snap['postId']);

      final user = Provider.of<UserProvider>(context, listen: false).user;
      dynamic userRatingRes;
      if (user != null) {
        userRatingRes = await Supabase.instance.client
            .from('post_rating')
            .select('rating')
            .eq('postid', widget.snap['postId'])
            .eq('userid', user.uid)
            .maybeSingle();
      }

      final allRatings = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.snap['postId']);

      if (mounted) {
        setState(() {
          _totalRatingsCount = countResponse.length;

          if (avgResponse.isNotEmpty) {
            final ratings = avgResponse
                .map<double>((r) => (r['rating'] as num).toDouble())
                .toList();
            _averageRating = ratings.reduce((a, b) => a + b) / ratings.length;
          } else {
            _averageRating = 0.0;
          }

          if (userRatingRes != null) {
            _userRating = (userRatingRes['rating'] as num).toDouble();
            _showSlider = false;
          } else {
            _userRating = null;
            _showSlider = true;
          }

          _localRatings = (allRatings as List<dynamic>)
              .map<Map<String, dynamic>>((r) => r as Map<String, dynamic>)
              .toList();

          _isLoadingRatings = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRatings = false);
      }
    }
  }

  void _handleRatingUpdate(PostgresChangePayload payload) {
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;
    final eventType = payload.eventType;

    setState(() {
      switch (eventType) {
        case PostgresChangeEvent.insert:
          if (newRecord != null) {
            _localRatings.insert(0, newRecord);
            _totalRatingsCount++;
            _updateAverageRating();

            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && newRecord['userid'] == user.uid) {
              _showSlider = false;
              _userRating = (newRecord['rating'] as num).toDouble();
            }
          }
          break;
        case PostgresChangeEvent.update:
          if (oldRecord != null && newRecord != null) {
            final index = _localRatings.indexWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
            if (index != -1) _localRatings[index] = newRecord;
            _updateAverageRating();

            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && newRecord['userid'] == user.uid) {
              _userRating = (newRecord['rating'] as num).toDouble();
            }
          }
          break;
        case PostgresChangeEvent.delete:
          if (oldRecord != null) {
            _localRatings.removeWhere(
              (r) => r['userid'] == oldRecord['userid'],
            );
            _totalRatingsCount--;
            _updateAverageRating();

            final user = Provider.of<UserProvider>(context, listen: false).user;
            if (user != null && oldRecord['userid'] == user.uid) {
              _showSlider = true;
              _userRating = null;
            }
          }
          break;
        default:
          break;
      }
    });

    if (widget.onRateUpdate != null) {
      final updatedPost = {
        ...widget.snap,
        'userRating': _userRating,
        'averageRating': _averageRating,
        'totalRatingsCount': _totalRatingsCount,
        'ratings': _localRatings,
        'showSlider': _showSlider,
      };
      widget.onRateUpdate!(updatedPost);
    }
  }

  void _updateAverageRating() {
    if (_localRatings.isEmpty) {
      setState(() => _averageRating = 0.0);
      return;
    }

    final total = _localRatings.fold(
        0.0, (sum, r) => sum + (r['rating'] as num).toDouble());

    final newAverage = total / _localRatings.length;
    setState(() => _averageRating = newAverage);
  }

  Future<void> _checkBlockStatus() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    final isBlocked = await _apiService.isMutuallyBlocked(
      user.uid,
      widget.snap['uid'],
    );

    if (mounted) setState(() => _isBlocked = isBlocked);
  }

  Future<void> _recordView() async {
    if (_viewRecorded) return;

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user != null) {
      await _apiService.recordPostView(
        widget.snap['postId'],
        user.uid,
      );
      if (mounted) setState(() => _viewRecorded = true);
    }
  }

  void _handleRatingSubmitted(double rating) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    final double? oldUserRating = _userRating;
    final bool isUpdatingExistingRating = oldUserRating != null;

    setState(() {
      _userRating = rating;
      _showSlider = false;

      final currentTotalRating = _averageRating * _totalRatingsCount;

      if (isUpdatingExistingRating) {
        final newTotal = currentTotalRating - oldUserRating! + rating;
        _averageRating = newTotal / _totalRatingsCount;
      } else {
        final newTotal = currentTotalRating + rating;
        _totalRatingsCount++;
        _averageRating = newTotal / _totalRatingsCount;
      }

      final userRatingIndex = _localRatings.indexWhere(
        (r) => r['userid'] == user.uid,
      );

      if (userRatingIndex != -1) {
        _localRatings[userRatingIndex]['rating'] = rating;
        _localRatings[userRatingIndex]['timestamp'] =
            DateTime.now().toIso8601String();
      } else {
        _localRatings.add({
          'userid': user.uid,
          'postid': widget.snap['postId'],
          'rating': rating,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });

    if (widget.onRateUpdate != null) {
      final updatedPost = {
        ...widget.snap,
        'userRating': rating,
        'averageRating': _averageRating,
        'totalRatingsCount': _totalRatingsCount,
        'ratings': _localRatings,
        'showSlider': false,
      };
      widget.onRateUpdate!(updatedPost);
    }

    try {
      final success = await _postsMethods.ratePost(
        widget.snap['postId'],
        user.uid,
        rating,
      );

      if (success != 'success' && mounted) {
        _fetchInitialRatings();
      }
    } catch (e) {
      if (mounted) {
        _fetchInitialRatings();
      }
    }
  }

  void _handleEditRating() {
    setState(() {
      _showSlider = true;
    });
  }

  Widget _buildCaptionWithVisibility(_ColorSet colors) {
    final caption = widget.snap['description'].toString();
    final bool needsTruncation = caption.length > 80;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
      ),
      child: _isCaptionExpanded
          ? GestureDetector(
              onTap: () {
                setState(() {
                  _isCaptionExpanded = false;
                });
              },
              child: Text(
                caption,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                  shadows: [
                    Shadow(
                      offset: Offset(1.0, 1.0),
                      blurRadius: 3.0,
                      color: Colors.black.withOpacity(0.8),
                    ),
                    Shadow(
                      offset: Offset(-1.0, -1.0),
                      blurRadius: 3.0,
                      color: Colors.black.withOpacity(0.8),
                    ),
                  ],
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isCaptionExpanded = true;
                      });
                    },
                    child: Text(
                      caption,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Inter',
                        shadows: [
                          Shadow(
                            offset: Offset(1.0, 1.0),
                            blurRadius: 3.0,
                            color: Colors.black.withOpacity(0.8),
                          ),
                          Shadow(
                            offset: Offset(-1.0, -1.0),
                            blurRadius: 3.0,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (needsTruncation) const SizedBox(width: 4),
                if (needsTruncation)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isCaptionExpanded = true;
                      });
                    },
                    child: Text(
                      'more',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        shadows: [
                          Shadow(
                            offset: Offset(1.0, 1.0),
                            blurRadius: 3.0,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildCommentButton(_ColorSet colors) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.comment_outlined, color: Colors.white, size: 28),
          onPressed: () {
            widget.onCommentTap?.call();
          },
        ),
        if (_commentCount > 0)
          Positioned(
            top: -6,
            left: -6,
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
                  _commentCount.toString(),
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
  }

  Widget _buildRightActionButtons(_ColorSet colors) {
    return Column(
      children: [
        GestureDetector(
          onTap: _navigateToProfile,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: widget.snap['profImage'] != null &&
                    widget.snap['profImage'] != "default"
                ? CircleAvatar(
                    radius: 21,
                    backgroundImage: NetworkImage(widget.snap['profImage']),
                  )
                : Icon(Icons.account_circle, size: 42, color: colors.iconColor),
          ),
        ),
        const SizedBox(height: 20),
        _buildCommentButton(colors),
        const SizedBox(height: 8),
        IconButton(
          icon: Icon(Icons.send, color: Colors.white, size: 28),
          onPressed: () => _navigateToShare(colors),
        ),
        const SizedBox(height: 8),
        if (_isVideo && _isVideoInitialized)
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
              size: 24,
            ),
            onPressed: _toggleMute,
          ),
      ],
    );
  }

  Widget _buildBottomOverlay(model.AppUser user, _ColorSet colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RatingBar(
            initialRating: _userRating ?? 5.0,
            hasRated: _userRating != null,
            userRating: _userRating ?? 0.0,
            onRatingEnd: _handleRatingSubmitted,
            showSlider: _showSlider,
            onEditRating: _handleEditRating,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _navigateToProfile,
                      child: VerifiedUsernameWidget(
                        username:
                            widget.snap['username']?.toString() ?? 'Unknown',
                        uid: widget.snap['uid']?.toString() ?? '',
                        countryCode: widget.snap['country']
                            ?.toString(), // Add country code
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          shadows: [
                            Shadow(
                              offset: Offset(1.0, 1.0),
                              blurRadius: 3.0,
                              color: Colors.black.withOpacity(0.8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: _isLoadingRatings
                    ? Container(
                        width: 120,
                        height: 20,
                        color: colors.skeletonColor,
                      )
                    : _totalRatingsCount == 0
                        ? Text(
                            'No ratings yet',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : Text(
                            'Rated ${_averageRating.toStringAsFixed(1)} by $_totalRatingsCount ${_totalRatingsCount == 1 ? 'voter' : 'voters'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.snap['description']?.toString().isNotEmpty ?? false)
            _buildCaptionWithVisibility(colors),
        ],
      ),
    );
  }

  void _showReportDialog(_ColorSet colors) {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.cardColor,
          title: Text('Report Post', style: TextStyle(color: colors.textColor)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thank you for helping keep our community safe.\n\nPlease let us know the reason for reporting this content.',
                  style: TextStyle(color: colors.textColor.withOpacity(0.7)),
                ),
                const SizedBox(height: 16),
                ..._reportReasons
                    .map((reason) => RadioListTile<String>(
                          title: Text(reason,
                              style: TextStyle(color: colors.textColor)),
                          value: reason,
                          groupValue: selectedReason,
                          activeColor: colors.textColor,
                          onChanged: (value) =>
                              setState(() => selectedReason = value),
                        ))
                    .toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: colors.textColor)),
            ),
            TextButton(
              onPressed: selectedReason != null
                  ? () => _submitReport(selectedReason!)
                  : null,
              child: Text('Submit', style: TextStyle(color: colors.textColor)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    Navigator.pop(context);
    try {
      await _apiService.reportPost(widget.snap['postId'], reason);
      showSnackBar(context, 'Report submitted successfully');
    } catch (e) {
      showSnackBar(
          context, 'Please try again or contact us at ratedly9@gmail.com');
    }
  }

  Future<void> _deletePost() async {
    try {
      await _apiService.deletePost(widget.snap['postId']);
      showSnackBar(context, 'Post deleted successfully');
    } catch (e) {
      showSnackBar(
          context, 'Please try again or contact us at ratedly9@gmail.com');
    }
  }

  // 🎯 FIXED: Video player with reliable play button
  Widget _buildVideoPlayer(_ColorSet colors) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isVideoInitialized)
            GestureDetector(
              onTap: _toggleVideoPlayback,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              ),
            )
          else if (_isVideoLoading)
            Container(
              color: Colors.black,
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[800]!.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                  child: CircularProgressIndicator(
                    color: Colors.grey[300]!,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam, size: 50, color: Colors.grey[300]!),
                    SizedBox(height: 8),
                    Text(
                      'Video not available',
                      style: TextStyle(color: Colors.grey[300]!),
                    ),
                  ],
                ),
              ),
            ),

          // 🎯 FIXED: Show play button only when video is NOT playing
          if (_isVideoInitialized && !_isVideoPlaying)
            GestureDetector(
              onTap: _playVideo, // Direct call to play, not toggle
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: Duration(milliseconds: 200),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markPostAsSeenIfVisible();
    });

    if (_isBlocked) {
      return const BlockedContentMessage(
        message: 'Post unavailable due to blocking',
      );
    }

    final user = Provider.of<UserProvider>(context).user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildMediaContent(colors),
          Positioned(
            bottom: 260,
            right: 16,
            child: _buildRightActionButtons(colors),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: _buildBottomOverlay(user, colors),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(_ColorSet colors) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: _isVideo
          ? _buildVideoPlayer(colors)
          : _buildCachedNetworkImage(colors),
    );
  }

  Widget _buildCachedNetworkImage(_ColorSet colors) {
    final imageUrl = widget.snap['postUrl']?.toString() ?? '';
    final postId = widget.snap['postId']?.toString() ?? '';

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) {
        return Container(
          color: Colors.black,
          child: Center(
            child: Icon(Icons.photo, size: 32, color: Colors.grey[700]!),
          ),
        );
      },
      errorWidget: (context, url, error) {
        return Container(
          color: Colors.black,
          child: Center(
            child: Icon(Icons.photo, size: 48, color: Colors.grey[300]!),
          ),
        );
      },
      cacheKey: postId,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      filterQuality: FilterQuality.medium,
      imageBuilder: (context, imageProvider) {
        _warmImageCache(imageUrl, postId);
        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(_ColorSet colors) {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    final isCurrentUserPost = user != null && widget.snap['uid'] == user.uid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.cardColor,
        title: Text('Delete Post', style: TextStyle(color: colors.textColor)),
        content: Text('Are you sure you want to delete this post?',
            style: TextStyle(color: colors.textColor.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _navigateToProfile() {
    // 🎯 FIXED: Ensure video is properly paused before navigation
    if (_isVideo && _isVideoInitialized) {
      _pauseVideo();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(uid: widget.snap['uid']),
      ),
    );
  }

  void _openCommentsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsBottomSheet(
        postId: widget.snap['postId'],
        postImage: widget.snap['postUrl'],
        isVideo: _isVideo,
        onClose: () {},
        videoController: _videoController,
      ),
    ).then((_) {
      unawaited(_fetchCommentsCount());
    });
  }

  void _navigateToShare(_ColorSet colors) {
    // 🎯 FIXED: Ensure video is properly paused before showing share dialog
    if (_isVideo && _isVideoInitialized) {
      _pauseVideo();
    }
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => PostShare(
        currentUserId: user.uid,
        postId: widget.snap['postId'],
      ),
    );
  }
}
