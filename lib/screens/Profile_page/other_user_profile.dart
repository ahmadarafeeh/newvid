import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/screens/messaging_screen.dart';
import 'package:Ratedly/screens/Profile_page/blocked_profile_screen.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/gestures.dart';
import 'package:Ratedly/widgets/verified_username_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:Ratedly/screens/Profile_page/gallery_post_view_screen.dart'; // Changed import

// Define color schemes for both themes at top level
class _OtherProfileColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color progressIndicatorColor;
  final Color avatarBackgroundColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color dividerColor;
  final Color dialogBackgroundColor;
  final Color dialogTextColor;
  final Color errorTextColor;
  final Color radioActiveColor;
  final Color skeletonColor;

  _OtherProfileColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.progressIndicatorColor,
    required this.avatarBackgroundColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.dividerColor,
    required this.dialogBackgroundColor,
    required this.dialogTextColor,
    required this.errorTextColor,
    required this.radioActiveColor,
    required this.skeletonColor,
  });
}

class _OtherProfileDarkColors extends _OtherProfileColorSet {
  _OtherProfileDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          avatarBackgroundColor: const Color(0xFF333333),
          buttonBackgroundColor: const Color(0xFF333333),
          buttonTextColor: const Color(0xFFd9d9d9),
          dividerColor: const Color(0xFF333333),
          dialogBackgroundColor: const Color(0xFF121212),
          dialogTextColor: const Color(0xFFd9d9d9),
          errorTextColor: Colors.grey[600]!,
          radioActiveColor: const Color(0xFFd9d9d9),
          skeletonColor: const Color(0xFF333333).withOpacity(0.6),
        );
}

class _OtherProfileLightColors extends _OtherProfileColorSet {
  _OtherProfileLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          progressIndicatorColor: Colors.grey[700]!,
          avatarBackgroundColor: Colors.grey[300]!,
          buttonBackgroundColor: Colors.grey[300]!,
          buttonTextColor: Colors.black,
          dividerColor: Colors.grey[300]!,
          dialogBackgroundColor: Colors.white,
          dialogTextColor: Colors.black,
          errorTextColor: Colors.grey[600]!,
          radioActiveColor: Colors.black,
          skeletonColor: Colors.grey[300]!.withOpacity(0.6),
        );
}

// Reusable flag widget for consistent flag display
class CountryFlagWidget extends StatelessWidget {
  final String countryCode;
  final double width;
  final double height;
  final double borderRadius;

  const CountryFlagWidget({
    Key? key,
    required this.countryCode,
    this.width = 16,
    this.height = 12,
    this.borderRadius = 2,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool hasCountryFlag =
        countryCode.isNotEmpty && countryCode.length == 2;

    if (!hasCountryFlag) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: CountryFlag.fromCountryCode(
          countryCode,
        ),
      ),
    );
  }
}

class ExpandableBioText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color expandColor;
  final int maxLength;

  const ExpandableBioText({
    Key? key,
    required this.text,
    required this.style,
    required this.expandColor,
    this.maxLength = 115,
  }) : super(key: key);

  @override
  State<ExpandableBioText> createState() => _ExpandableBioTextState();
}

class _ExpandableBioTextState extends State<ExpandableBioText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final shouldTruncate = widget.text.length > widget.maxLength;

    if (!shouldTruncate || _isExpanded) {
      return Text(
        widget.text,
        style: widget.style,
      );
    }

    final truncatedText = widget.text.substring(0, widget.maxLength);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$truncatedText... ',
            style: widget.style,
          ),
          TextSpan(
            text: 'more',
            style: widget.style.copyWith(
              color: widget.expandColor,
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                setState(() {
                  _isExpanded = true;
                });
              },
          ),
        ],
      ),
    );
  }
}

class OtherUserProfileScreen extends StatefulWidget {
  final String uid;
  const OtherUserProfileScreen({Key? key, required this.uid}) : super(key: key);

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  var userData = {};
  int postLen = 0;
  int followers = 0;
  bool isFollowing = false;
  bool isLoading = true;
  bool _isBlockedByMe = false;
  bool _isBlocked = false;
  bool _isBlockedByThem = false;
  bool _isViewerFollower = false;
  bool hasPendingRequest = false;
  List<dynamic> _followersList = [];
  int following = 0;
  bool _isMutualFollow = false;

  // Video player controllers cache
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, bool> _videoControllersInitialized = {};

  // ========== GALLERIES VARIABLES ==========
  List<dynamic> _galleries = [];
  int _selectedTabIndex = 0; // 0 for posts, 1 for galleries
  // =========================================

  // ========== PAGINATION VARIABLES ==========
  List<dynamic> _displayedPosts = []; // Posts currently shown
  int _postsOffset = 0; // Current offset for pagination
  final int _postsLimit = 6; // Fetch 6 posts at a time (changed from 9)
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;
  // ==========================================

  // Add the missing profileReportReasons list
  final List<String> profileReportReasons = [
    'Impersonation (Pretending to be someone else)',
    'Fake Account (Misleading or suspicious profile)',
    'Bullying or Harassment',
    'Hate Speech or Discrimination (e.g., race, religion, gender, sexual orientation)',
    'Scam or Fraud (Deceptive activity, phishing, or financial fraud)',
    'Spam (Unwanted promotions or repetitive content)',
    'Inappropriate Content (Explicit, offensive, or disturbing profile)',
  ];

  // Add these for faster loading
  Timer? _searchDebounce;

  // ========== SCROLL CONTROLLER FOR INFINITE SCROLL ==========
  late ScrollController _scrollController;
  // ===========================================================

  // Helper method to get the appropriate color scheme
  _OtherProfileColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _OtherProfileDarkColors() : _OtherProfileLightColors();
  }

  @override
  void initState() {
    super.initState();

    // ========== INITIALIZE SCROLL CONTROLLER ==========
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    // ==================================================

    _loadDataInParallel();
  }

  // ========== SCROLL LISTENER FOR INFINITE SCROLL ==========
  void _scrollListener() {
    // Check if we've reached the bottom of the scroll
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMorePosts &&
        _selectedTabIndex == 0) {
      // Only for posts tab
      _loadMorePosts();
    }
  }
  // =========================================================

  // -------------------------
  // OPTIMIZED: Parallel data loading like search screen
  // -------------------------
  Future<void> _loadDataInParallel() async {
    setState(() => isLoading = true);

    try {
      await Future.wait([
        _loadUserData(),
        _loadPostsCountAndFirstBatch(),
        _loadGalleriesData(), // ADDED: Load galleries
        _loadBlockStatus(),
      ]);

      if (!_isBlocked && mounted) {
        await _loadRelationshipData();
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final userResponse =
          await _supabase.from('users').select().eq('uid', widget.uid).single();

      if (mounted) {
        setState(() {
          userData = userResponse;
        });
      }
    } catch (e) {
      // User data is essential, so we might want to handle this differently
    }
  }

  // ========== ADDED: Load galleries data ==========
  Future<void> _loadGalleriesData() async {
    try {
      final galleriesResponse = await _supabase.from('galleries').select('''
            *,
            gallery_posts(count),
            posts!cover_post_id(postUrl)
          ''').eq('uid', widget.uid).order('created_at', ascending: false);

      // Pre-initialize video controllers for gallery covers
      for (final gallery in galleriesResponse) {
        final coverImageUrl =
            gallery['posts'] != null ? gallery['posts']['postUrl'] ?? '' : '';
        if (_isVideoFile(coverImageUrl)) {
          _initializeVideoController(coverImageUrl);
        }
      }

      if (mounted) {
        setState(() {
          _galleries = galleriesResponse;
        });
      }
    } catch (e) {
      // Galleries can fail without breaking the whole screen
      if (mounted) {
        setState(() {
          _galleries = [];
        });
      }
    }
  }
  // ================================================

  // ========== UPDATED: Load posts count and first batch ==========
  Future<void> _loadPostsCountAndFirstBatch() async {
    try {
      // Get total post count
      final totalPostsResponse =
          await _supabase.from('posts').select('postId').eq('uid', widget.uid);

      final totalPostCount = totalPostsResponse.length;

      // Get the initial batch of posts (first 6)
      final initialPosts = await _supabase
          .from('posts')
          .select('postId, postUrl, description, datePublished, uid')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false)
          .range(0, _postsLimit - 1);

      // Pre-initialize video controllers for video posts
      _preInitializeVideoControllers(initialPosts);

      if (mounted) {
        setState(() {
          _displayedPosts = initialPosts;
          postLen = totalPostCount; // Set total post count
          _postsOffset = initialPosts.length; // Set offset for next load
          _hasMorePosts =
              totalPostCount > initialPosts.length; // Check if more posts exist
        });
      }
    } catch (e) {
      // Posts can load separately
      if (mounted) {
        setState(() {
          _displayedPosts = [];
          postLen = 0;
          _hasMorePosts = false;
        });
      }
    }
  }
  // ===============================================================

  Future<void> _loadBlockStatus() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final isBlockedByMe = await SupabaseBlockMethods().isBlockInitiator(
        currentUserId: currentUserId,
        targetUserId: widget.uid,
      );

      final isBlockedByThem = await SupabaseBlockMethods().isUserBlocked(
        currentUserId: currentUserId,
        targetUserId: widget.uid,
      );

      if (mounted) {
        setState(() {
          _isBlockedByMe = isBlockedByMe;
          _isBlockedByThem = isBlockedByThem;
          _isBlocked = isBlockedByMe || isBlockedByThem;
        });
      }

      if (_isBlocked && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BlockedProfileScreen(
                uid: widget.uid,
                isBlocker: _isBlockedByMe,
              ),
            ),
          );
        });
      }
    } catch (e) {
      // Block status can fail without breaking the whole screen
    }
  }

  Future<void> _loadRelationshipData() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      // Load followers, following, and relationship status in parallel
      final results = await Future.wait<dynamic>([
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid)
            .then((value) => value as List<dynamic>),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid)
            .then((value) => value as List<dynamic>),
        _supabase
            .from('user_following')
            .select()
            .eq('user_id', currentUserId)
            .eq('following_id', widget.uid)
            .maybeSingle()
            .then((value) => value as Map<String, dynamic>?),
        _supabase
            .from('user_follow_request')
            .select()
            .eq('user_id', widget.uid)
            .eq('requester_id', currentUserId)
            .maybeSingle()
            .then((value) => value as Map<String, dynamic>?),
        _supabase
            .from('user_following')
            .select()
            .eq('user_id', widget.uid)
            .eq('following_id', currentUserId)
            .maybeSingle()
            .then((value) => value as Map<String, dynamic>?),
      ]);

      final followersResponse = results[0] as List<dynamic>;
      final followingResponse = results[1] as List<dynamic>;
      final isFollowingResponse = results[2] as Map<String, dynamic>?;
      final followRequestResponse = results[3] as Map<String, dynamic>?;
      final otherFollowsCurrent = results[4] as Map<String, dynamic>?;

      // Process followers with user data
      List<dynamic> processedFollowers = [];
      if (followersResponse.isNotEmpty) {
        final followerIds =
            followersResponse.map((f) => f['follower_id'] as String).toList();

        final followersData = await _supabase
            .from('users')
            .select('uid, username, photoUrl')
            .inFilter('uid', followerIds);

        final followerMap = {
          for (var f in followersData) f['uid'] as String: f
        };

        for (var follower in followersResponse) {
          final followerId = follower['follower_id'] as String;
          final followerInfo = followerMap[followerId];
          if (followerInfo != null) {
            processedFollowers.add({
              'userId': followerId,
              'username': followerInfo['username'],
              'photoUrl': followerInfo['photoUrl'],
              'timestamp': follower['followed_at']
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedFollowers;
          isFollowing = isFollowingResponse != null;
          hasPendingRequest = followRequestResponse != null;
          _isMutualFollow =
              isFollowingResponse != null && otherFollowsCurrent != null;
        });
      }
    } catch (e) {
      // Relationship data is non-essential for initial display
      if (mounted) {
        setState(() {
          // Set default values if relationship data fails to load
          followers = 0;
          following = 0;
          _followersList = [];
          isFollowing = false;
          hasPendingRequest = false;
          _isMutualFollow = false;
        });
      }
    }
  }

  // ========== LOAD MORE POSTS METHOD (INFINITE SCROLL) ==========
  Future<void> _loadMorePosts() async {
    if (!_hasMorePosts || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final newPosts = await _supabase
          .from('posts')
          .select('postId, postUrl, description, datePublished, uid')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false)
          .range(_postsOffset, _postsOffset + _postsLimit - 1);

      // Pre-initialize video controllers for new video posts
      _preInitializeVideoControllers(newPosts);

      if (newPosts.isNotEmpty) {
        setState(() {
          _displayedPosts.addAll(newPosts);
          _postsOffset += newPosts.length;
          _hasMorePosts = newPosts.length ==
              _postsLimit; // If we got less than limit, no more posts
        });
      } else {
        setState(() => _hasMorePosts = false);
      }
    } catch (e) {
      // Handle error quietly
      if (mounted) {
        showSnackBar(context, 'Failed to load more posts');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
  // ===========================================

  // -------------------------
  // Video player logic for first-second looping (OPTIMIZED)
  // -------------------------

  /// Initialize video controller for a video URL - only loads first second
  Future<void> _initializeVideoController(String videoUrl) async {
    if (_videoControllers.containsKey(videoUrl) ||
        _videoControllersInitialized[videoUrl] == true) {
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
        ),
      );

      // Store controller immediately to prevent duplicate initializations
      _videoControllers[videoUrl] = controller;
      _videoControllersInitialized[videoUrl] = false;

      // Initialize without waiting for completion
      controller.initialize().then((_) {
        if (mounted && _videoControllers.containsKey(videoUrl)) {
          _videoControllersInitialized[videoUrl] = true;
          _configureVideoLoop(controller);
          controller.setVolume(0.0);
          setState(() {});
        }
      });
    } catch (e) {
      // Clean up on error
      _videoControllers.remove(videoUrl)?.dispose();
      _videoControllersInitialized.remove(videoUrl);
    }
  }

  /// Configure video to play only first second on loop
  void _configureVideoLoop(VideoPlayerController controller) {
    final duration = controller.value.duration;
    final endPosition =
        duration.inSeconds > 0 ? const Duration(seconds: 1) : duration;

    controller.addListener(() {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        final currentPosition = controller.value.position;
        if (currentPosition >= endPosition) {
          controller.seekTo(Duration.zero);
        }
      }
    });

    controller.play();
  }

  /// Get video controller for a URL, initializing if needed
  VideoPlayerController? _getVideoController(String videoUrl) {
    return _videoControllers[videoUrl];
  }

  /// Check if video controller is initialized
  bool _isVideoControllerInitialized(String videoUrl) {
    return _videoControllersInitialized[videoUrl] == true;
  }

  /// Pre-initialize video controllers for posts
  void _preInitializeVideoControllers(List<dynamic> posts) {
    for (final post in posts) {
      final postUrl = post['postUrl'] ?? '';
      if (_isVideoFile(postUrl)) {
        // Start initialization but don't wait for it
        _initializeVideoController(postUrl);
      }
    }
  }

  // Helper method to detect video files by extension
  bool _isVideoFile(String url) {
    if (url.isEmpty) return false;
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.avi') ||
        lowerUrl.endsWith('.wmv') ||
        lowerUrl.endsWith('.flv') ||
        lowerUrl.endsWith('.mkv') ||
        lowerUrl.endsWith('.webm') ||
        lowerUrl.endsWith('.m4v') ||
        lowerUrl.endsWith('.3gp') ||
        lowerUrl.contains('/video/') ||
        lowerUrl.contains('video=true');
  }

  // ========== ADDED: Gallery video player ==========
  Widget _buildGalleryVideoPlayer(
      String videoUrl, _OtherProfileColorSet colors) {
    if (!_videoControllers.containsKey(videoUrl)) {
      _initializeVideoController(videoUrl);
    }

    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return Container(
        color: colors.avatarBackgroundColor,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.progressIndicatorColor,
            strokeWidth: 1.5,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // =================================================

  // -------------------------
  // OPTIMIZED: Skeleton Loading Widgets
  // -------------------------

  Widget _buildOtherProfileSkeleton(_OtherProfileColorSet colors) {
    return SingleChildScrollView(
      controller: _scrollController, // Add scroll controller
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildOtherProfileHeaderSkeleton(colors),
            const SizedBox(height: 20),
            _buildOtherBioSectionSkeleton(colors),
            const SizedBox(height: 16),
            _buildTabButtonsSkeleton(colors), // ADDED: Tab buttons skeleton
            Divider(color: colors.dividerColor),
            _buildOtherPostsGridSkeleton(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherProfileHeaderSkeleton(_OtherProfileColorSet colors) {
    return Column(
      children: [
        // Profile picture skeleton
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.skeletonColor,
          ),
        ),
        const SizedBox(height: 16),
        // Metrics skeleton
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOtherMetricSkeleton(colors),
              _buildOtherMetricSkeleton(colors),
              _buildOtherMetricSkeleton(colors),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Interaction buttons skeleton
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 40,
              decoration: BoxDecoration(
                color: colors.skeletonColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 100,
              height: 40,
              decoration: BoxDecoration(
                color: colors.skeletonColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtherMetricSkeleton(_OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 16,
          width: 30,
          decoration: BoxDecoration(
            color: colors.skeletonColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          width: 50,
          decoration: BoxDecoration(
            color: colors.skeletonColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherBioSectionSkeleton(_OtherProfileColorSet colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            width: 120,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 250,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 200,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // ========== ADDED: Tab buttons skeleton ==========
  Widget _buildTabButtonsSkeleton(_OtherProfileColorSet colors) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: colors.skeletonColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
  // ================================================

  Widget _buildOtherPostsGridSkeleton(_OtherProfileColorSet colors) {
    // Calculate the grid for 3 columns with proper aspect ratio
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6, // Show 6 skeleton items (2 rows of 3)
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 0.8, // Instagram-like aspect ratio
      ),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: colors.skeletonColor,
          ),
        );
      },
    );
  }

  Widget _buildAppBarTitleSkeleton(_OtherProfileColorSet colors) {
    return Container(
      height: 16,
      width: 120,
      decoration: BoxDecoration(
        color: colors.skeletonColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // -------------------------
  // OPTIMIZED: Remaining methods with performance improvements
  // -------------------------

  void _otherHandleFollow() async {
    try {
      final currentUserId = _firebaseAuth.currentUser?.uid;
      if (currentUserId == null) {
        if (mounted) {
          showSnackBar(context, "Please sign in to follow users");
        }
        return;
      }

      final targetUserId = widget.uid;
      final isPrivate = userData['isPrivate'] ?? false;

      if (isFollowing) {
        await SupabaseProfileMethods()
            .unfollowUser(currentUserId, targetUserId);
        if (mounted) {
          setState(() {
            isFollowing = false;
            _isMutualFollow = false;
          });
        }
      } else if (hasPendingRequest) {
        await SupabaseProfileMethods().declineFollowRequest(
          targetUserId,
          currentUserId,
        );
        if (mounted) {
          setState(() {
            hasPendingRequest = false;
          });
        }
      } else {
        await SupabaseProfileMethods().followUser(
          currentUserId,
          targetUserId,
        );
        if (isPrivate) {
          setState(() {
            hasPendingRequest = true;
          });
        } else {
          setState(() {
            isFollowing = true;
          });
          // Check mutual follow in background without blocking UI
          _checkMutualFollowAfterFollow();
        }
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    }
  }

  Future<void> _checkMutualFollowAfterFollow() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    final otherFollowsCurrent = await _supabase
        .from('user_following')
        .select()
        .eq('user_id', widget.uid)
        .eq('following_id', currentUserId)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isMutualFollow = otherFollowsCurrent != null;
      });
    }
  }

  void _otherNavigateToMessaging() async {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) {
      if (mounted) {
        showSnackBar(context, "Please sign in to message users");
      }
      return;
    }

    // Use existing userData instead of fetching again
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagingScreen(
            recipientUid: widget.uid,
            recipientUsername: userData['username'] ?? '',
            recipientPhotoUrl: userData['photoUrl'] ?? '',
          ),
        ),
      );
    }
  }

  void _showProfileReportDialog(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) {
      if (mounted) {
        showSnackBar(context, "Please sign in to report profiles");
      }
      return;
    }

    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.dialogBackgroundColor,
              title: Text('Report Profile',
                  style: TextStyle(color: colors.dialogTextColor)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thank you for helping keep our community safe.\n\nPlease let us know the reason for reporting this content. Your report is anonymous, and our moderators will review it as soon as possible. \n\n If you prefer not to see this user posts or content, you can choose to block them.',
                      style: TextStyle(
                          color: colors.dialogTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select a reason:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.dialogTextColor),
                    ),
                    ...profileReportReasons.map((reason) {
                      return RadioListTile<String>(
                        title: Text(reason,
                            style: TextStyle(color: colors.dialogTextColor)),
                        value: reason,
                        groupValue: selectedReason,
                        activeColor: colors.radioActiveColor,
                        onChanged: (value) {
                          setState(() => selectedReason = value);
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel',
                      style: TextStyle(color: colors.dialogTextColor)),
                ),
                TextButton(
                  onPressed: selectedReason != null
                      ? () => _submitProfileReport(selectedReason!)
                      : null,
                  child: Text('Submit',
                      style: TextStyle(color: colors.dialogTextColor)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitProfileReport(String reason) async {
    try {
      await _supabase.from('reports').insert({
        'user_id': widget.uid,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'profile',
      });

      if (mounted) {
        Navigator.pop(context);
        showSnackBar(context, 'Report submitted. Thank you!');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  // ========== ADDED: Tab buttons ==========
  Widget _buildTabButtons(_OtherProfileColorSet colors) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => setState(() => _selectedTabIndex = 0),
              style: TextButton.styleFrom(
                foregroundColor: _selectedTabIndex == 0
                    ? colors.textColor
                    : colors.textColor.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.grid_on,
                    color: _selectedTabIndex == 0
                        ? colors.textColor
                        : colors.textColor.withOpacity(0.5),
                  ),
                  Text(
                    'POSTS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _selectedTabIndex == 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (_selectedTabIndex == 0)
                    Container(
                      height: 1,
                      color: colors.textColor,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextButton(
              onPressed: () => setState(() => _selectedTabIndex = 1),
              style: TextButton.styleFrom(
                foregroundColor: _selectedTabIndex == 1
                    ? colors.textColor
                    : colors.textColor.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.collections,
                    color: _selectedTabIndex == 1
                        ? colors.textColor
                        : colors.textColor.withOpacity(0.5),
                  ),
                  Text(
                    'GALLERIES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _selectedTabIndex == 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (_selectedTabIndex == 1)
                    Container(
                      height: 1,
                      color: colors.textColor,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ========================================

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final isCurrentUser = currentUserId == widget.uid;
    final isAuthenticated = currentUserId != null;

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: colors.appBarBackgroundColor,
          elevation: 0,
          leading: BackButton(color: colors.appBarIconColor),
          title: _buildAppBarTitleSkeleton(colors),
          centerTitle: true,
        ),
        backgroundColor: colors.backgroundColor,
        body: _buildOtherProfileSkeleton(colors),
      );
    }

    return Scaffold(
      appBar: AppBar(
          iconTheme: IconThemeData(color: colors.appBarIconColor),
          backgroundColor: colors.appBarBackgroundColor,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VerifiedUsernameWidget(
                username: userData['username'] ?? 'User',
                uid: widget.uid,
                style: TextStyle(
                  color: colors.textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          centerTitle: true,
          leading: BackButton(color: colors.appBarIconColor),
          actions: [
            if (isAuthenticated)
              PopupMenuButton(
                icon: Icon(Icons.more_vert, color: colors.appBarIconColor),
                onSelected: (value) async {
                  if (value == 'block') {
                    try {
                      setState(() => isLoading = true);
                      final currentUserId = _firebaseAuth.currentUser?.uid;
                      if (currentUserId == null) return;

                      await SupabaseBlockMethods().blockUser(
                        currentUserId: currentUserId,
                        targetUserId: widget.uid,
                      );

                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BlockedProfileScreen(
                              uid: widget.uid,
                              isBlocker: true,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(context,
                            "Please try again or contact us at ratedly9@gmail.com");
                      }
                    } finally {
                      if (mounted) setState(() => isLoading = false);
                    }
                  } else if (value == 'remove_follower') {
                    final currentUserId = _firebaseAuth.currentUser?.uid;
                    if (currentUserId == null) return;

                    try {
                      await SupabaseProfileMethods()
                          .removeFollower(currentUserId, widget.uid);
                      if (mounted) {
                        setState(() {
                          _isViewerFollower = false;
                          followers = followers - 1;
                        });
                        showSnackBar(context, "Follower removed successfully");
                      }
                    } catch (e) {
                      if (mounted) {
                        showSnackBar(context,
                            "Please try again or contact us at ratedly9@gmail.com");
                      }
                    }
                  } else if (value == 'report') {
                    _showProfileReportDialog(colors);
                  }
                },
                itemBuilder: (context) => [
                  if (_isViewerFollower)
                    PopupMenuItem(
                      value: 'remove_follower',
                      child: Text('Remove Follower',
                          style: TextStyle(color: colors.textColor)),
                    ),
                  if (!isCurrentUser)
                    PopupMenuItem(
                      value: 'report',
                      child: Text('Report Profile',
                          style: TextStyle(color: colors.textColor)),
                    ),
                  PopupMenuItem(
                    value: 'block',
                    child: Text('Block User',
                        style: TextStyle(color: colors.textColor)),
                  ),
                ],
              )
          ]),
      backgroundColor: colors.backgroundColor,
      body: SingleChildScrollView(
        controller: _scrollController, // Add scroll controller
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildOtherProfileHeader(colors),
              const SizedBox(height: 20),
              _buildOtherBioSection(colors),
              const SizedBox(height: 16),
              // Tab buttons
              _buildTabButtons(colors),
              Divider(color: colors.dividerColor),
              // Tab content
              _selectedTabIndex == 0
                  ? _buildOtherPostsGrid(colors)
                  : _buildOtherGalleriesGrid(colors),
              // Show loading indicator at bottom when loading more
              if (_isLoadingMore && _selectedTabIndex == 0)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(color: colors.textColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtherProfileHeader(_OtherProfileColorSet colors) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: colors.avatarBackgroundColor,
          radius: 45,
          backgroundImage: (userData['photoUrl'] != null &&
                  userData['photoUrl'].isNotEmpty &&
                  userData['photoUrl'] != "default")
              ? NetworkImage(userData['photoUrl'])
              : null,
          child: (userData['photoUrl'] == null ||
                  userData['photoUrl'].isEmpty ||
                  userData['photoUrl'] == "default")
              ? Icon(
                  Icons.account_circle,
                  size: 90,
                  color: colors.iconColor,
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildOtherMetric(postLen, "Posts", colors),
                        _buildOtherMetric(followers, "Followers", colors),
                        _buildOtherMetric(following, "Following", colors),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildOtherInteractionButtons(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtherInteractionButtons(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivateAccount = userData['isPrivate'] ?? false;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isCurrentUser) _buildFollowButton(isPrivateAccount, colors),
            const SizedBox(width: 5),
            if (!isCurrentUser)
              ElevatedButton(
                onPressed: _otherNavigateToMessaging,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.buttonBackgroundColor,
                  foregroundColor: colors.buttonTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  minimumSize: const Size(100, 40),
                ),
                child: Text("Message",
                    style: TextStyle(color: colors.buttonTextColor)),
              ),
          ],
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  Widget _buildFollowButton(
      bool isPrivateAccount, _OtherProfileColorSet colors) {
    final isPending = hasPendingRequest && isPrivateAccount;

    return ElevatedButton(
        onPressed: _otherHandleFollow,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.buttonBackgroundColor,
          foregroundColor: colors.buttonTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          side: BorderSide(
            color: colors.buttonBackgroundColor,
          ),
          minimumSize: const Size(100, 40),
        ),
        child: Text(
          isFollowing
              ? 'Unfollow'
              : isPending
                  ? 'Requested'
                  : 'Follow',
          style: TextStyle(
              fontWeight: FontWeight.w600, color: colors.buttonTextColor),
        ));
  }

  Widget _buildOtherMetric(
      int value, String label, _OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 13.6,
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: colors.textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildOtherBioSection(_OtherProfileColorSet colors) {
    final String bio = userData['bio'] ?? '';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VerifiedUsernameWidget(
            username: userData['username'] ?? '',
            uid: widget.uid,
            style: TextStyle(
              color: colors.textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          if (bio.isNotEmpty)
            ExpandableBioText(
              text: bio,
              style: TextStyle(color: colors.textColor),
              expandColor: colors.textColor.withOpacity(0.8),
            ),
        ],
      ),
    );
  }

  Widget _buildPrivateAccountMessage(_OtherProfileColorSet colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock, size: 60, color: colors.errorTextColor),
        const SizedBox(height: 20),
        Text('This Account is Private',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textColor)),
        const SizedBox(height: 10),
        Text('Follow to see their galleries',
            style: TextStyle(fontSize: 14, color: colors.textColor)),
      ],
    );
  }

  // ========== UPDATED POSTS GRID WITH INSTAGRAM-LIKE DESIGN ==========
  Widget _buildOtherPostsGrid(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivate = userData['isPrivate'] ?? false;
    final bool shouldHidePosts = isPrivate && !isFollowing && !isCurrentUser;
    final bool isMutuallyBlocked = _isBlockedByMe || _isBlockedByThem;

    if (isMutuallyBlocked) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            Text('Posts unavailable due to blocking',
                style: TextStyle(color: colors.errorTextColor)),
          ],
        ),
      );
    }

    if (shouldHidePosts) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.3,
        child: _buildPrivateAccountMessage(colors),
      );
    }

    // Use pre-loaded posts instead of FutureBuilder
    if (_displayedPosts.isEmpty) {
      return SizedBox(
          height: 200,
          child: Center(
            child: Text(
              'This user has no posts.',
              style: TextStyle(
                fontSize: 16,
                color: colors.errorTextColor,
              ),
            ),
          ));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _displayedPosts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2, // Reduced spacing for Instagram-like grid
        mainAxisSpacing: 2, // Reduced spacing
        childAspectRatio: 0.8, // Instagram-like aspect ratio (taller than wide)
      ),
      itemBuilder: (context, index) {
        final post = _displayedPosts[index];
        return _buildOtherPostItem(post, colors);
      },
    );
  }
  // =======================================================

  // ========== ADDED: Galleries Grid - VIEW ONLY ==========
  Widget _buildOtherGalleriesGrid(_OtherProfileColorSet colors) {
    final currentUserId = _firebaseAuth.currentUser?.uid;
    final bool isCurrentUser = currentUserId == widget.uid;
    final bool isPrivate = userData['isPrivate'] ?? false;
    final bool shouldHideGalleries =
        isPrivate && !isFollowing && !isCurrentUser;
    final bool isMutuallyBlocked = _isBlockedByMe || _isBlockedByThem;

    if (isMutuallyBlocked) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 50, color: Colors.red),
            const SizedBox(height: 10),
            Text('Galleries unavailable due to blocking',
                style: TextStyle(color: colors.errorTextColor)),
          ],
        ),
      );
    }

    if (shouldHideGalleries) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.3,
        child: _buildPrivateAccountMessage(colors),
      );
    }

    if (_galleries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(
              Icons.collections,
              size: 64,
              color: colors.errorTextColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No Galleries Yet',
              style: TextStyle(
                color: colors.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This user hasn\'t created any galleries',
              style: TextStyle(
                color: colors.textColor.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // NO ADD BUTTON - Just display the galleries
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _galleries.length, // No +1 for add button
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final gallery = _galleries[index];
        return _buildGalleryItem(gallery, colors);
      },
    );
  }
  // ========================================================

  Widget _buildOtherPostItem(
      Map<String, dynamic> post, _OtherProfileColorSet colors) {
    final postUrl = post['postUrl'] ?? '';
    final isVideo = _isVideoFile(postUrl);

    return FutureBuilder<bool>(
      future: SupabaseBlockMethods().isMutuallyBlocked(
        _firebaseAuth.currentUser?.uid ?? '',
        post['uid'] ?? '',
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!) {
          return Container(
            margin: const EdgeInsets.all(1), // Reduced margin
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4), // Smaller radius
              color: colors.avatarBackgroundColor,
            ),
            child: const Center(
              child: Icon(
                Icons.block,
                color: Colors.red,
                size: 24, // Smaller icon
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () {
            // PROPERLY PAUSE any currently playing video before navigation
            for (final controller in _videoControllers.values) {
              if (controller.value.isPlaying) {
                controller.pause();
              }
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageViewScreen(
                  imageUrl: postUrl,
                  postId: post['postId'] ?? '',
                  description: post['description'] ?? '',
                  userId: post['uid'] ?? '',
                  username: userData['username'] ?? '',
                  profImage: userData['photoUrl'] ?? '',
                  datePublished: post['datePublished'],
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.all(1), // Reduced margin
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4), // Smaller radius
              color: isVideo ? colors.avatarBackgroundColor : null,
            ),
            child: isVideo
                ? _buildVideoPlayer(postUrl, colors)
                : _buildImageThumbnail(postUrl, colors),
          ),
        );
      },
    );
  }

  // ========== UPDATED: Video player that fills entire space ==========
  Widget _buildVideoPlayer(String videoUrl, _OtherProfileColorSet colors) {
    if (!_videoControllers.containsKey(videoUrl)) {
      _initializeVideoController(videoUrl);
    }

    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return _buildVideoLoading(colors);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand, // Make stack fill entire container
        children: [
          // Video player that fills the entire space
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover, // Cover the entire container like images do
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // =========================================================

  // ========== ADDED: Gallery item builder - Navigates to GalleryPostViewScreen ==========
  Widget _buildGalleryItem(
      Map<String, dynamic> gallery, _OtherProfileColorSet colors) {
    final postCount =
        gallery['gallery_posts'] != null && gallery['gallery_posts'].isNotEmpty
            ? gallery['gallery_posts'][0]['count'] ?? 0
            : 0;

    final coverImageUrl =
        gallery['posts'] != null ? gallery['posts']['postUrl'] ?? '' : '';

    final isVideoCover = _isVideoFile(coverImageUrl);

    return GestureDetector(
      onTap: () async {
        // Load the gallery posts and navigate to GalleryPostViewScreen
        try {
          final galleryPostsResponse =
              await _supabase.from('gallery_posts').select('''
            post_id,
            posts!inner(postId, postUrl, description, datePublished, uid, username, profImage)
          ''').eq('gallery_id', gallery['id']);

          // Convert the response to a list of posts in the format needed for GalleryPostViewScreen
          final List<Map<String, dynamic>> posts =
              (galleryPostsResponse as List).map<Map<String, dynamic>>((item) {
            final post = item['posts'];
            return {
              'postId': post['postId']?.toString() ?? '',
              'postUrl': post['postUrl']?.toString() ?? '',
              'description': post['description']?.toString() ?? '',
              'uid': post['uid']?.toString() ?? '',
              'datePublished': post['datePublished']?.toString() ?? '',
              'username': post['username']?.toString() ?? '',
              'profImage': post['profImage']?.toString() ?? '',
            };
          }).toList();

          // Navigate to GalleryPostViewScreen (view-only mode for non-owners)
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GalleryPostViewScreen(
                  posts: posts,
                  initialIndex: 0,
                  galleryName: gallery['name'] ?? 'Unnamed Gallery',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            showSnackBar(context, 'Failed to load gallery posts: $e');
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.avatarBackgroundColor,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gallery cover image or video
            if (coverImageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isVideoCover
                    ? _buildGalleryVideoPlayer(coverImageUrl, colors)
                    : Image.network(
                        coverImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color:
                                  colors.avatarBackgroundColor.withOpacity(0.5),
                            ),
                            child: Icon(
                              Icons.collections,
                              size: 40,
                              color: colors.errorTextColor,
                            ),
                          );
                        },
                      ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: colors.avatarBackgroundColor.withOpacity(0.5),
                ),
                child: Icon(
                  Icons.collections,
                  size: 40,
                  color: colors.errorTextColor,
                ),
              ),

            // Overlay with gallery info
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gallery['name'] ?? 'Unnamed Gallery',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$postCount ${postCount == 1 ? 'post' : 'posts'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // =====================================================

  Widget _buildVideoLoading(_OtherProfileColorSet colors) {
    return Container(
      color: colors.avatarBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: colors.progressIndicatorColor,
              strokeWidth: 1.5,
            ),
            const SizedBox(height: 4),
            Text(
              'Loading...',
              style: TextStyle(
                color: colors.textColor,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(String imageUrl, _OtherProfileColorSet colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4), // Smaller radius
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover, // Cover the entire container
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: colors.avatarBackgroundColor,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        (loadingProgress.expectedTotalBytes ?? 1)
                    : null,
                color: colors.progressIndicatorColor,
                strokeWidth: 1.5,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: colors.avatarBackgroundColor,
            child: Center(
              child: Icon(
                Icons.broken_image,
                color: colors.errorTextColor,
                size: 20, // Smaller icon
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();

    // ========== DISPOSE SCROLL CONTROLLER ==========
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    // ===============================================

    // PROPERLY DISPOSE all video controllers
    for (final controller in _videoControllers.values) {
      controller.pause(); // Pause before disposal
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllersInitialized.clear();

    super.dispose();
  }
}
