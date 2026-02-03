// lib/screens/Profile_page/profile_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/edit_profile_screen.dart';
import 'package:Ratedly/screens/Profile_page/image_screen.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';
import 'package:Ratedly/widgets/settings_screen.dart';
import 'package:Ratedly/widgets/user_list_screen.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/gestures.dart';
import 'package:Ratedly/screens/Profile_page/gallery_detail_screen.dart';
import 'package:country_flags/country_flags.dart';

// Define color schemes for both themes at top level (same as in feed_screen)
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
        );
}

// Reusable flag widget
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
    ));
  }
}

class CurrentUserProfileScreen extends StatefulWidget {
  final String uid;
  const CurrentUserProfileScreen({Key? key, required this.uid})
      : super(key: key);

  @override
  State<CurrentUserProfileScreen> createState() =>
      _CurrentUserProfileScreenState();
}

class _CurrentUserProfileScreenState extends State<CurrentUserProfileScreen>
    with WidgetsBindingObserver {
  final SupabaseClient _supabase = Supabase.instance.client;
  var userData = {};
  int followers = 0;
  int following = 0;
  int postCount = 0;
  int viewCount = 0;
  List<dynamic> _followersList = [];
  List<dynamic> _followingList = [];
  bool isLoading = false;
  bool hasError = false;
  String errorMessage = '';
  final SupabaseProfileMethods _profileMethods = SupabaseProfileMethods();

  // New gallery variables
  List<dynamic> _galleries = [];
  int _selectedTabIndex = 0;

  // Video player controllers cache for posts
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, bool> _videoControllersInitialized = {};

  // Video player controller for profile picture
  VideoPlayerController? _profileVideoController;
  bool _isProfileVideoInitialized = false;
  bool _isProfileVideoMuted = false; // Track mute state for profile video

  // Pagination variables
  List<dynamic> _displayedPosts = [];
  int _postsOffset = 0;
  final int _initialPostsLimit = 9;
  final int _subsequentPostsLimit = 6;
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;
  bool _isFirstLoad = true;

  // Scroll controller
  late ScrollController _scrollController;

  // Helper method to get the appropriate color scheme
  _ColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _DarkColors() : _LightColors();
  }

  // Helper method to check if a URL is a video
  bool _isVideoFile(String url) {
    if (url.isEmpty || url == 'default') return false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    getData();
    _fetchViewCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();

    // Dispose all video controllers
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    _videoControllersInitialized.clear();

    // Dispose profile video controller
    if (_profileVideoController != null) {
      _profileVideoController!.dispose();
      _profileVideoController = null;
    }

    super.dispose();
  }

  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is going to background or losing focus
      _muteProfileVideo();
    } else if (state == AppLifecycleState.resumed) {
      // App is coming back to foreground
      _unmuteProfileVideo();
    }
  }

  // Mute profile video
  void _muteProfileVideo() {
    if (_profileVideoController != null && _isProfileVideoInitialized) {
      try {
        _profileVideoController!.setVolume(0.0);
      } catch (e) {
        // Handle error silently
      }
    }
  }

  // Unmute profile video
  void _unmuteProfileVideo() {
    if (_profileVideoController != null && _isProfileVideoInitialized) {
      try {
        _profileVideoController!.setVolume(_isProfileVideoMuted ? 0.0 : 1.0);
      } catch (e) {
        // Handle error silently
      }
    }
  }

  // Toggle profile video mute state
  void _toggleProfileVideoMute() {
    if (_profileVideoController != null && _isProfileVideoInitialized) {
      setState(() {
        _isProfileVideoMuted = !_isProfileVideoMuted;
      });

      try {
        _profileVideoController!.setVolume(_isProfileVideoMuted ? 0.0 : 1.0);
      } catch (e) {
        // Handle error silently
      }
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50 &&
        !_isLoadingMore &&
        _hasMorePosts &&
        _selectedTabIndex == 0) {
      Future.delayed(const Duration(milliseconds: 15), () {
        if (mounted) {
          _loadMorePosts();
        }
      });
    }
  }

  // ========== PROFILE VIDEO HANDLING ==========
  Future<void> _initializeProfileVideo(String videoUrl) async {
    if (_profileVideoController != null) {
      await _profileVideoController!.dispose();
      setState(() {
        _profileVideoController = null;
        _isProfileVideoInitialized = false;
      });
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      await controller.initialize();
      // Play with sound by default (volume 1.0)
      await controller.setVolume(1.0);
      await controller.setLooping(true);
      await controller.play();

      if (mounted) {
        setState(() {
          _profileVideoController = controller;
          _isProfileVideoInitialized = true;
          _isProfileVideoMuted =
              false; // Reset mute state when initializing new video
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProfileVideoInitialized = false;
        });
      }
    }
  }

  Widget _buildProfileVideoPlayer(_ColorSet colors) {
    if (_profileVideoController == null || !_isProfileVideoInitialized) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.cardColor,
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: colors.textColor,
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipOval(
          child: SizedBox(
            width: 80,
            height: 80,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _profileVideoController!.value.size.width,
                height: _profileVideoController!.value.size.height,
                child: VideoPlayer(_profileVideoController!),
              ),
            ),
          ),
        ),
        // Mute button overlay
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _toggleProfileVideoMute,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isProfileVideoMuted ? Icons.volume_off : Icons.volume_up,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePicture(_ColorSet colors) {
    final photoUrl = userData['photoUrl']?.toString() ?? '';
    final isDefault = photoUrl.isEmpty || photoUrl == 'default';
    final isVideo = !isDefault && _isVideoFile(photoUrl);

    if (isDefault) {
      return CircleAvatar(
        radius: 40,
        backgroundColor: colors.cardColor,
        child: Icon(
          Icons.account_circle,
          size: 80,
          color: colors.textColor,
        ),
      );
    }

    if (isVideo) {
      return _buildProfileVideoPlayer(colors);
    }

    // Regular image - use ClipOval instead of CircleAvatar to handle errors properly
    return ClipOval(
      child: Container(
        width: 80,
        height: 80,
        color: colors.cardColor,
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                Icons.account_circle,
                size: 80,
                color: colors.textColor,
              ),
            );
          },
        ),
      ),
    );
  }
  // ============================================

  // ========== POST VIDEO HANDLING ==========
  Future<void> _initializeVideoController(String videoUrl) async {
    if (_videoControllers.containsKey(videoUrl) ||
        _videoControllersInitialized[videoUrl] == true) {
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      _videoControllers[videoUrl] = controller;
      _videoControllersInitialized[videoUrl] = false;

      controller.addListener(() {
        if (controller.value.isInitialized &&
            !_videoControllersInitialized[videoUrl]!) {
          _videoControllersInitialized[videoUrl] = true;

          // Configure loop for first second
          _configureVideoLoop(controller);

          if (mounted) {
            setState(() {});
          }
        }
      });

      await controller.initialize();
      // KEEP muted for post videos (grid view)
      await controller.setVolume(0.0);
    } catch (e) {
      _videoControllers.remove(videoUrl)?.dispose();
      _videoControllersInitialized.remove(videoUrl);
    }
  }

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

  VideoPlayerController? _getVideoController(String videoUrl) {
    return _videoControllers[videoUrl];
  }

  bool _isVideoControllerInitialized(String videoUrl) {
    return _videoControllersInitialized[videoUrl] == true;
  }

  Widget _buildPostVideoPlayer(String videoUrl, _ColorSet colors) {
    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return Container(
        color: colors.cardColor,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.textColor,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
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

  Widget _buildGalleryVideoPlayer(String videoUrl, _ColorSet colors) {
    final controller = _getVideoController(videoUrl);
    final isInitialized = _isVideoControllerInitialized(videoUrl);

    if (!isInitialized || controller == null) {
      return Container(
        color: colors.cardColor,
        child: Center(
          child: CircularProgressIndicator(
            color: colors.textColor,
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

  void _preInitializeVideoControllers(List<dynamic> posts) {
    for (final post in posts) {
      final postUrl = post['postUrl'] ?? '';
      if (_isVideoFile(postUrl)) {
        _initializeVideoController(postUrl);
      }
    }
  }
  // =========================================

  Future<void> _fetchViewCount() async {
    try {
      final count = await _profileMethods.getProfileViewCount(widget.uid);
      if (mounted) {
        setState(() {
          viewCount = count;
        });
      }
    } catch (e) {}
  }

  Future<void> getData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = '';
    });

    try {
      // Get total post count
      final totalPostsResponse =
          await _supabase.from('posts').select('postId').eq('uid', widget.uid);
      final totalPostCount = totalPostsResponse.length;

      // Get initial posts
      final postsLimit =
          _isFirstLoad ? _initialPostsLimit : _subsequentPostsLimit;
      final initialPosts = await _supabase
          .from('posts')
          .select('postId, postUrl, description, datePublished, uid')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false)
          .range(0, postsLimit - 1);

      final List<Future<dynamic>> queries = [
        _supabase.from('users').select().eq('uid', widget.uid).single(),
        Future.value(initialPosts),
        _supabase
            .from('user_followers')
            .select('follower_id, followed_at')
            .eq('user_id', widget.uid),
        _supabase
            .from('user_following')
            .select('following_id, followed_at')
            .eq('user_id', widget.uid),
        _supabase.from('galleries').select('''
            *,
            gallery_posts(count),
            posts!cover_post_id(postUrl)
          ''').eq('uid', widget.uid).order('created_at', ascending: false),
      ];

      final results = await Future.wait(queries);

      final userResponse = results[0];
      final postsResponse = results[1] as List;
      final followersResponse = results[2] as List;
      final followingResponse = results[3] as List;
      final galleriesResponse = results[4] as List;

      if (userResponse.isEmpty) {
        throw Exception('User data not found for UID: ${widget.uid}');
      }

      // Initialize profile video if needed
      final photoUrl = userResponse['photoUrl'] ?? '';
      if (_isVideoFile(photoUrl)) {
        _initializeProfileVideo(photoUrl);
      }

      // Pre-initialize video controllers for posts and galleries
      _preInitializeVideoControllers(postsResponse);
      for (final gallery in galleriesResponse) {
        final coverImageUrl =
            gallery['posts'] != null ? gallery['posts']['postUrl'] ?? '' : '';
        if (_isVideoFile(coverImageUrl)) {
          _initializeVideoController(coverImageUrl);
        }
      }

      final processedData = await Future.wait([
        _processUserList(followersResponse, 'follower_id'),
        _processUserList(followingResponse, 'following_id'),
      ]);

      if (mounted) {
        setState(() {
          userData = userResponse;
          postCount = totalPostCount;
          followers = followersResponse.length;
          following = followingResponse.length;
          _followersList = processedData[0];
          _followingList = processedData[1];
          _galleries = galleriesResponse;
          _displayedPosts = postsResponse;
          _postsOffset = postsResponse.length;
          _hasMorePosts = totalPostCount > postsResponse.length;
          _isFirstLoad = false;
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          hasError = true;
          errorMessage = 'Failed to load profile data';
          _isFirstLoad = false;
        });
        showSnackBar(
            context, "Please try again or contact us at ratedly9@gmail.com");
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMorePosts || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final postsLimit = _subsequentPostsLimit;
      final newPosts = await _supabase
          .from('posts')
          .select('postId, postUrl, description, datePublished, uid')
          .eq('uid', widget.uid)
          .order('datePublished', ascending: false)
          .range(_postsOffset, _postsOffset + postsLimit - 1);

      _preInitializeVideoControllers(newPosts);

      if (newPosts.isNotEmpty && mounted) {
        setState(() {
          _displayedPosts.addAll(newPosts);
          _postsOffset += newPosts.length;
          _hasMorePosts = newPosts.length == _subsequentPostsLimit;
        });
      } else {
        if (mounted) {
          setState(() => _hasMorePosts = false);
        }
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to load more posts');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<List<dynamic>> _processUserList(
      List<dynamic> userList, String idKey) async {
    if (userList.isEmpty) return [];

    final userIds = userList.map((user) => user[idKey] as String).toList();
    final usersData = await _supabase
        .from('users')
        .select('uid, username, photoUrl')
        .inFilter('uid', userIds);

    final userMap = {for (var user in usersData) user['uid'] as String: user};

    return userList
        .map((entry) {
          final userInfo = userMap[entry[idKey]];
          return userInfo != null
              ? {
                  'userId': entry[idKey],
                  'username': userInfo['username'],
                  'photoUrl': userInfo['photoUrl'],
                  'timestamp': entry['followed_at'],
                }
              : null;
        })
        .where((item) => item != null)
        .toList();
  }

  void _navigateToSettings() {
    // Mute video before navigation
    _muteProfileVideo();

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    ).then((_) {
      // Unmute when returning (after a small delay)
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _unmuteProfileVideo();
        }
      });
    });
  }

  // Build username with flag
  Widget _buildUsernameWithFlag(
      String username, bool isVerified, String? countryCode, _ColorSet colors) {
    final bool hasCountryFlag = countryCode != null &&
        countryCode.isNotEmpty &&
        countryCode.length == 2;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(username,
            style: TextStyle(
              color: colors.textColor,
              fontWeight: FontWeight.bold,
            )),
        if (hasCountryFlag) ...[
          const SizedBox(width: 4),
          CountryFlagWidget(
            countryCode: countryCode!,
            width: 16,
            height: 12,
          ),
        ],
        if (isVerified) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified,
            color: Colors.blue,
            size: 16,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.textColor),
        backgroundColor: colors.backgroundColor,
        elevation: 0,
        title: isLoading
            ? Container(
                height: 16,
                width: 120,
                decoration: BoxDecoration(
                  color: colors.cardColor.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            : _buildUsernameWithFlag(
                userData['username'] ?? 'Loading...',
                userData['isVerified'] == true,
                userData['country']?.toString(),
                colors,
              ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.menu, color: colors.textColor),
            onPressed: _navigateToSettings,
          )
        ],
      ),
      backgroundColor: colors.backgroundColor,
      body: hasError
          ? _buildErrorWidget(colors)
          : isLoading
              ? _buildProfileSkeleton(colors)
              : SingleChildScrollView(
                  controller: _scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildProfileHeader(colors),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            _buildBioSection(colors),
                            const SizedBox(height: 16),
                            Column(
                              children: [
                                _buildTabButtons(colors),
                                _selectedTabIndex == 0
                                    ? _buildPostsGrid(colors)
                                    : _buildGalleriesGrid(colors),
                              ],
                            ),
                          ],
                        ),
                        if (_selectedTabIndex == 0 && _isLoadingMore)
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(
                                color: colors.textColor),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorWidget(_ColorSet colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: colors.textColor,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: TextStyle(
              color: colors.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: TextStyle(color: colors.textColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: getData,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.cardColor,
              foregroundColor: colors.textColor,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(_ColorSet colors) {
    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Center(
            child: _buildProfilePicture(colors),
          ),
        ),
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMetric(postCount, "Posts", colors.textColor),
                  _buildInteractiveMetric(
                      followers, "Followers", _followersList, colors),
                  _buildInteractiveMetric(
                      following, "Following", _followingList, colors),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Center(
              child: _buildEditProfileButton(colors),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInteractiveMetric(
      int value, String label, List<dynamic> userList, _ColorSet colors) {
    return GestureDetector(
      onTap: () {
        // Mute video before navigation
        _muteProfileVideo();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserListScreen(
              title: label,
              userEntries: userList,
            ),
          ),
        ).then((_) {
          // Unmute when returning (after a small delay to ensure video is ready)
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _unmuteProfileVideo();
            }
          });
        });
      },
      child: _buildMetric(value, label, colors.textColor),
    );
  }

  Widget _buildEditProfileButton(_ColorSet colors) {
    return ElevatedButton(
      onPressed: () async {
        // Mute video before navigation
        _muteProfileVideo();

        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
        );

        // Unmute when returning (after a small delay to ensure video is ready)
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _unmuteProfileVideo();
          }
        });

        if (result != null && mounted) {
          setState(() {
            userData['bio'] = result['bio'] ?? userData['bio'];
            userData['photoUrl'] = result['photoUrl'] ?? userData['photoUrl'];
          });

          await getData();
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.cardColor,
        foregroundColor: colors.textColor,
      ),
      child: const Text("Edit Profile"),
    );
  }

  Widget _buildMetric(int value, String label, Color textColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w400, color: textColor),
        ),
      ],
    );
  }

  Widget _buildBioSection(_ColorSet colors) {
    final String bio = userData['bio'] ?? '';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUsernameWithFlag(
            userData['username'] ?? '',
            userData['isVerified'] == true,
            userData['country']?.toString(),
            colors,
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

  Widget _buildTabButtons(_ColorSet colors) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.cardColor, width: 1),
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

  Widget _buildPostsGrid(_ColorSet colors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _displayedPosts.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildAddPostButton(colors);
        }

        final postIndex = index - 1;
        if (postIndex < 0 || postIndex >= _displayedPosts.length) {
          return Container();
        }

        final post = _displayedPosts[postIndex];
        return _buildPostItem(post, colors);
      },
    );
  }

  Widget _buildAddPostButton(_ColorSet colors) {
    return GestureDetector(
      onTap: () {
        // Mute video before navigation
        _muteProfileVideo();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddPostScreen(
              onPostUploaded: () async {
                // Refresh data
                await getData();
              },
            ),
          ),
        ).then((_) {
          // Unmute when returning (after a small delay to ensure video is ready)
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _unmuteProfileVideo();
            }
          });
        });
      },
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: colors.cardColor,
        ),
        child: Icon(
          Icons.add_circle_outline,
          size: 40,
          color: colors.textColor,
        ),
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post, _ColorSet colors) {
    final postUrl = post['postUrl'] ?? '';
    final isVideo = _isVideoFile(postUrl);

    return GestureDetector(
      onTap: () {
        // Pause any currently playing video before navigation
        for (final controller in _videoControllers.values) {
          if (controller.value.isPlaying) {
            controller.pause();
          }
        }

        // Mute profile video before navigation to ImageViewScreen
        _muteProfileVideo();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageViewScreen(
              imageUrl: postUrl,
              postId: post['postId']?.toString() ?? '',
              description: post['description']?.toString() ?? '',
              userId: post['uid']?.toString() ?? '',
              username: userData['username']?.toString() ?? '',
              profImage: userData['photoUrl']?.toString() ?? '',
              onPostDeleted: () async {
                // Refresh data when returning from deleted post
                await getData();
              },
              datePublished: post['datePublished']?.toString() ?? '',
            ),
          ),
        ).then((_) {
          // Unmute when returning (after a small delay to ensure video is ready)
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _unmuteProfileVideo();
            }
          });
        });
      },
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: isVideo ? colors.cardColor : null,
        ),
        child: isVideo
            ? _buildPostVideoPlayer(postUrl, colors)
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  postUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: colors.cardColor,
                      child: Icon(
                        Icons.broken_image,
                        color: colors.iconColor,
                        size: 20,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildGalleriesGrid(_ColorSet colors) {
    if (_galleries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(
              Icons.collections,
              size: 64,
              color: colors.textColor.withOpacity(0.5),
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
              'Create your first gallery to organize your posts',
              style: TextStyle(
                color: colors.textColor.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _createNewGallery,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.cardColor,
                foregroundColor: colors.textColor,
              ),
              child: const Text('Create Gallery'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _galleries.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildAddGalleryButton(colors);
        }

        final galleryIndex = index - 1;
        if (galleryIndex < 0 || galleryIndex >= _galleries.length) {
          return Container();
        }

        final gallery = _galleries[galleryIndex];
        return _buildGalleryItem(gallery, colors);
      },
    );
  }

  Widget _buildAddGalleryButton(_ColorSet colors) {
    return GestureDetector(
      onTap: _createNewGallery,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.cardColor,
          border: Border.all(color: colors.textColor.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: 40,
              color: colors.textColor.withOpacity(0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'New Gallery',
              style: TextStyle(
                color: colors.textColor.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryItem(Map<String, dynamic> gallery, _ColorSet colors) {
    final postCount =
        gallery['gallery_posts'] != null && gallery['gallery_posts'].isNotEmpty
            ? gallery['gallery_posts'][0]['count'] ?? 0
            : 0;

    final coverImageUrl =
        gallery['posts'] != null ? gallery['posts']['postUrl'] ?? '' : '';
    final isVideoCover = _isVideoFile(coverImageUrl);

    return GestureDetector(
      onTap: () {
        // Mute video before navigation
        _muteProfileVideo();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GalleryDetailScreen(
              galleryId: gallery['id'],
              galleryName: gallery['name'] ?? 'Unnamed Gallery',
              uid: widget.uid,
            ),
          ),
        ).then((_) {
          // Unmute when returning
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _unmuteProfileVideo();
            }
          });
          getData();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.cardColor,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
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
                              color: colors.cardColor.withOpacity(0.5),
                            ),
                            child: Icon(
                              Icons.collections,
                              size: 40,
                              color: colors.textColor.withOpacity(0.5),
                            ),
                          );
                        },
                      ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: colors.cardColor.withOpacity(0.5),
                ),
                child: Icon(
                  Icons.collections,
                  size: 40,
                  color: colors.textColor.withOpacity(0.5),
                ),
              ),
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

  void _createNewGallery() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final colors = _getColors(themeProvider);

    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController nameController = TextEditingController();
        return AlertDialog(
          title: Text(
            'Create New Gallery',
            style: TextStyle(color: colors.textColor),
          ),
          backgroundColor: colors.backgroundColor,
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              hintText: 'Gallery name',
              hintStyle: TextStyle(color: colors.textColor.withOpacity(0.5)),
              border: const OutlineInputBorder(),
            ),
            style: TextStyle(color: colors.textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: colors.textColor)),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop();
                  await _createGallery(name);
                }
              },
              child: Text('Create', style: TextStyle(color: colors.textColor)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createGallery(String name) async {
    try {
      final response = await _supabase.from('galleries').insert({
        'uid': widget.uid,
        'name': name,
      }).select();

      if (mounted) {
        setState(() {
          _galleries = [response.first, ..._galleries];
        });
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Failed to create gallery: $e');
      }
    }
  }

  // Skeleton widgets (keep your existing skeleton methods)
  Widget _buildProfileSkeleton(_ColorSet colors) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProfileHeaderSkeleton(colors),
            const SizedBox(height: 20),
            Column(
              children: [
                _buildBioSectionSkeleton(colors),
                const SizedBox(height: 16),
                Divider(color: colors.cardColor),
                _buildPostsGridSkeleton(colors),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeaderSkeleton(_ColorSet colors) {
    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.cardColor.withOpacity(0.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMetricSkeleton(colors),
              _buildMetricSkeleton(colors),
              _buildMetricSkeleton(colors),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 120,
          height: 36,
          decoration: BoxDecoration(
            color: colors.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricSkeleton(_ColorSet colors) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        height: 16,
        width: 30,
        decoration: BoxDecoration(
          color: colors.cardColor.withOpacity(0.8),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(height: 6),
      Container(
        height: 12,
        width: 50,
        decoration: BoxDecoration(
          color: colors.cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    ]);
  }

  Widget _buildBioSectionSkeleton(_ColorSet colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            width: 120,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 250,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 14,
            width: 200,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsGridSkeleton(_ColorSet colors) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 7,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: colors.cardColor.withOpacity(0.5),
          ),
        );
      },
    );
  }

  Widget _buildErrorWidgetSkeleton(_ColorSet colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.cardColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 20,
            width: 200,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 16,
            width: 150,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 100,
            height: 40,
            decoration: BoxDecoration(
              color: colors.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }
}
