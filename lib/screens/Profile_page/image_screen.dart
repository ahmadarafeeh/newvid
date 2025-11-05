import 'dart:convert';
import 'package:Ratedly/services/ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/screens/comment_screen.dart';
import 'package:Ratedly/screens/Profile_page/profile_page.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/widgets/postshare.dart';
import 'package:Ratedly/widgets/rating_list_screen_postcard.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';
import 'package:Ratedly/widgets/blocked_content_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

// Define color schemes for both themes at top level
class _ImageViewColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color appBarBackgroundColor;
  final Color appBarIconColor;
  final Color dialogBackgroundColor;
  final Color dialogTextColor;
  final Color avatarBackgroundColor;
  final Color progressIndicatorColor;
  final Color buttonBackgroundColor;
  final Color dividerColor;
  final Color radioActiveColor;
  final Color errorIconColor;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;

  _ImageViewColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.appBarBackgroundColor,
    required this.appBarIconColor,
    required this.dialogBackgroundColor,
    required this.dialogTextColor,
    required this.avatarBackgroundColor,
    required this.progressIndicatorColor,
    required this.buttonBackgroundColor,
    required this.dividerColor,
    required this.radioActiveColor,
    required this.errorIconColor,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
  });
}

class _ImageViewDarkColors extends _ImageViewColorSet {
  _ImageViewDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          appBarBackgroundColor: const Color(0xFF121212),
          appBarIconColor: const Color(0xFFd9d9d9),
          dialogBackgroundColor: const Color(0xFF121212),
          dialogTextColor: const Color(0xFFd9d9d9),
          avatarBackgroundColor: const Color(0xFF333333),
          progressIndicatorColor: Colors.white70,
          buttonBackgroundColor: const Color(0xFF333333),
          dividerColor: const Color(0xFF333333),
          radioActiveColor: const Color(0xFFd9d9d9),
          errorIconColor: Colors.white54,
          badgeBackgroundColor: const Color(0xFF333333),
          badgeTextColor: const Color(0xFFd9d9d9),
        );
}

class _ImageViewLightColors extends _ImageViewColorSet {
  _ImageViewLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          appBarBackgroundColor: Colors.white,
          appBarIconColor: Colors.black,
          dialogBackgroundColor: Colors.white,
          dialogTextColor: Colors.black,
          avatarBackgroundColor: Colors.grey[300]!,
          progressIndicatorColor: Colors.grey[700]!,
          buttonBackgroundColor: Colors.grey[300]!,
          dividerColor: Colors.grey[300]!,
          radioActiveColor: Colors.black,
          errorIconColor: Colors.grey[600]!,
          badgeBackgroundColor: Colors.grey[300]!,
          badgeTextColor: Colors.black,
        );
}

class ImageViewScreen extends StatefulWidget {
  final String imageUrl;
  final String postId;
  final String description;
  final String userId;
  final String username;
  final String profImage;
  final dynamic datePublished;
  final VoidCallback? onPostDeleted;

  const ImageViewScreen({
    Key? key,
    required this.imageUrl,
    required this.postId,
    required this.description,
    required this.userId,
    required this.username,
    required this.profImage,
    required this.datePublished,
    this.onPostDeleted,
  }) : super(key: key);

  @override
  State<ImageViewScreen> createState() => _ImageViewScreenState();
}

class _ImageViewScreenState extends State<ImageViewScreen> {
  // UPDATED: Changed from commentLen to _commentCount for consistency
  late int _commentCount;
  bool _isBlocked = false;
  bool _viewRecorded = false;
  final SupabasePostsMethods _postsMethods = SupabasePostsMethods();
  bool _showSlider = true;
  bool _isDeleting = false;

  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // Rating state variables
  double _averageRating = 0.0;
  int _totalRatingsCount = 0;
  double? _userRating;
  bool _isLoadingRatings = true;
  late RealtimeChannel _postChannel;

  // ADDED: Comment realtime channels
  late RealtimeChannel _commentsChannel;
  late RealtimeChannel _repliesChannel;

  // Video player variables
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoLoading = false;
  bool _isVideoPlaying = false;
  bool _showPlayButton = false;
  bool _isMuted = false;

  // Local ratings list
  late List<Map<String, dynamic>> _localRatings;

  final List<String> reportReasons = [
    'I just don\'t like it',
    'Discriminatory content',
    'Bullying or harassment',
    'Violence or hate speech',
    'Selling prohibited items',
    'Pornography or nudity',
    'Scam or fraudulent activity',
    'Spam',
    'Misinformation',
  ];

  // Check if URL is a video
  bool get _isVideo {
    final url = widget.imageUrl.toLowerCase();
    return url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi') ||
        url.endsWith('.mkv') ||
        url.contains('video');
  }

  @override
  void initState() {
    super.initState();

    _localRatings = [];
    // UPDATED: Initialize comment count
    _commentCount = 0;
    _fetchCommentsCount();
    _checkBlockStatus();
    _setupRealtime();
    _setupCommentsRealtime(); // ADDED: Setup comment realtime
    _fetchInitialRatings();
    _loadBannerAd();
    _recordView();

    if (_isVideo) {
      _initializeVideoPlayer();
    }
  }

  // ADDED: Setup realtime for comments and replies (same as PostCard)
  void _setupCommentsRealtime() {
    // Comments channel
    _commentsChannel =
        Supabase.instance.client.channel('comments_${widget.postId}');
    _commentsChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'comments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.postId,
      ),
      callback: (payload) {
        _fetchCommentsCount();
      },
    );

    // Replies channel
    _repliesChannel =
        Supabase.instance.client.channel('replies_${widget.postId}');
    _repliesChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'replies',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.postId,
      ),
      callback: (payload) {
        _fetchCommentsCount();
      },
    );

    _commentsChannel.subscribe();
    _repliesChannel.subscribe();
  }

  Future<void> _recordView() async {
    if (_viewRecorded) return;

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user != null) {
      await _postsMethods.recordPostView(
        widget.postId,
        user.uid,
      );
      if (mounted) setState(() => _viewRecorded = true);
    }
  }

  void _setupRealtime() {
    _postChannel = Supabase.instance.client.channel('post_${widget.postId}');

    _postChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'post_rating',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'postid',
        value: widget.postId,
      ),
      callback: (payload) {
        _handleRatingUpdate(payload);
      },
    );

    _postChannel.subscribe();
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
  }

  void _updateAverageRating() {
    if (_localRatings.isEmpty) {
      setState(() => _averageRating = 0.0);
      return;
    }

    final total = _localRatings.fold(
        0.0, (sum, r) => sum + (r['rating'] as num).toDouble());

    setState(() => _averageRating = total / _localRatings.length);
  }

  Future<void> _fetchInitialRatings() async {
    setState(() => _isLoadingRatings = true);

    try {
      final countResponse = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.postId);

      final avgResponse = await Supabase.instance.client
          .from('post_rating')
          .select('rating')
          .eq('postid', widget.postId);

      final user = Provider.of<UserProvider>(context, listen: false).user;
      dynamic userRatingRes;
      if (user != null) {
        userRatingRes = await Supabase.instance.client
            .from('post_rating')
            .select('rating')
            .eq('postid', widget.postId)
            .eq('userid', user.uid)
            .maybeSingle();
      }

      final allRatings = await Supabase.instance.client
          .from('post_rating')
          .select()
          .eq('postid', widget.postId);

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
          'postid': widget.postId,
          'rating': rating,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });

    try {
      final success = await _postsMethods.ratePost(
        widget.postId,
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

  void _initializeVideoPlayer() async {
    setState(() => _isVideoLoading = true);

    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.imageUrl),
      )..addListener(() {
          if (mounted) {
            setState(() {
              _isVideoPlaying = _videoController!.value.isPlaying;
              if (_videoController!.value.position ==
                  _videoController!.value.duration) {
                _videoController!.seekTo(Duration.zero);
                _videoController!.play();
              }
            });
          }
        });

      await _videoController!.initialize();
      _videoController!.setLooping(true);

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _isVideoLoading = false;
          _showPlayButton = false;
        });

        _playVideo();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    }
  }

  void _playVideo() {
    if (_videoController != null && _isVideoInitialized) {
      _videoController!.play();
      setState(() {
        _isVideoPlaying = true;
      });

      Future.delayed(Duration(seconds: 2), () {
        if (mounted && _isVideoPlaying) {
          setState(() {
            _showPlayButton = false;
          });
        }
      });
    }
  }

  void _pauseVideo() {
    if (_videoController != null && _isVideoInitialized) {
      _videoController!.pause();
      setState(() {
        _isVideoPlaying = false;
        _showPlayButton = true;
      });
    }
  }

  void _toggleMute() {
    if (_videoController != null && _isVideoInitialized) {
      setState(() {
        _isMuted = !_isMuted;
        _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _bannerAd?.dispose();
    _postChannel.unsubscribe();
    // ADDED: Unsubscribe from comment channels
    _commentsChannel.unsubscribe();
    _repliesChannel.unsubscribe();
    super.dispose();
  }

  void _loadBannerAd() {
    BannerAd(
      adUnitId: AdHelper.imagescreenAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    ).load();
  }

  // Helper method to get the appropriate color scheme
  _ImageViewColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _ImageViewDarkColors() : _ImageViewLightColors();
  }

  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is DateTime) return date;
    if (date is String) return DateTime.tryParse(date);
    return null;
  }

  // ADDED: Helper method to count items (same as PostCard)
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

  // UPDATED: Comment count method to match PostCard implementation
  Future<void> _fetchCommentsCount() async {
    try {
      final commentsResponse = await Supabase.instance.client
          .from('comments')
          .select('id')
          .eq('postid', widget.postId);

      final repliesResponse = await Supabase.instance.client
          .from('replies')
          .select('id')
          .eq('postid', widget.postId);

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
          _commentCount = 0;
        });
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    final isBlocked = await SupabaseBlockMethods().isMutuallyBlocked(
      user.uid,
      widget.userId,
    );

    if (mounted) setState(() => _isBlocked = isBlocked);
  }

  // UPDATED: Delete post with loading indicator overlay
  void deletePost(String postId) async {
    // First close the delete options dialog
    Navigator.of(context).pop();

    // Then show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final colors =
            _getColors(Provider.of<ThemeProvider>(context, listen: false));
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button during deletion
          child: Dialog(
            backgroundColor: colors.dialogBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: colors.progressIndicatorColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Deleting post...',
                    style: TextStyle(
                      color: colors.dialogTextColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      await _postsMethods.deletePost(postId);

      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();
        // Notify parent about deletion
        widget.onPostDeleted?.call();
        // Close the image view screen
        Navigator.of(context).pop();
      }
    } catch (err) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();
        // Show error message
        showSnackBar(context, 'Failed to delete post: $err');
      }
    }
  }

  void _showReportDialog(_ImageViewColorSet colors) {
    String? selectedReason;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: colors.dialogBackgroundColor,
              title: Text('Report Post',
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
                      'Select a reason: \n',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.dialogTextColor,
                      ),
                    ),
                    ...reportReasons.map((reason) {
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
                      ? () {
                          _postsMethods
                              .reportPost(widget.postId, selectedReason!)
                              .then((res) {
                            Navigator.pop(context);
                            if (res == 'success') {
                              showSnackBar(
                                  context, 'Report submitted. Thank you!');
                            } else {
                              showSnackBar(context,
                                  'Something went wrong, please try again later or contact us at ratedly9@gmail.com');
                            }
                          });
                        }
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

  // ADDED: Comment button matching PostCard styling
  Widget _buildCommentButton(_ImageViewColorSet colors) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.comment_outlined, color: colors.iconColor, size: 28),
          onPressed: () => _navigateToComments(colors),
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
                color: colors.badgeBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _commentCount.toString(),
                  style: TextStyle(
                    color: colors.badgeTextColor,
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

  Widget _buildMediaContent(_ImageViewColorSet colors) {
    if (_isVideo) {
      return _buildVideoPlayer(colors);
    } else {
      return _buildImage(colors);
    }
  }

  Widget _buildVideoPlayer(_ImageViewColorSet colors) {
    return AspectRatio(
      aspectRatio:
          _isVideoInitialized ? _videoController!.value.aspectRatio : 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (_isVideoInitialized)
            GestureDetector(
              onTap: () {
                if (_isVideoPlaying) {
                  _pauseVideo();
                  setState(() {
                    _showPlayButton = true;
                  });

                  Future.delayed(Duration(seconds: 3), () {
                    if (mounted && !_isVideoPlaying) {
                      setState(() {
                        _showPlayButton = false;
                      });
                    }
                  });
                } else {
                  _playVideo();
                  Future.delayed(Duration(milliseconds: 300), () {
                    if (mounted && _isVideoPlaying) {
                      setState(() {
                        _showPlayButton = false;
                      });
                    }
                  });
                }
              },
              child: VideoPlayer(_videoController!),
            )
          else if (_isVideoLoading)
            Container(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor,
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
                    Icon(Icons.videocam,
                        size: 50, color: colors.errorIconColor),
                    SizedBox(height: 8),
                    Text(
                      'Video not available',
                      style: TextStyle(color: colors.errorIconColor),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _initializeVideoPlayer,
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if (_showPlayButton && _isVideoInitialized)
            Center(
              child: GestureDetector(
                onTap: () {
                  _playVideo();
                  Future.delayed(Duration(milliseconds: 300), () {
                    if (mounted && _isVideoPlaying) {
                      setState(() {
                        _showPlayButton = false;
                      });
                    }
                  });
                },
                child: AnimatedOpacity(
                  opacity: _showPlayButton ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 200),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (_isVideoInitialized)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Ratedly',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_isVideoInitialized)
            Positioned(
              bottom: 16,
              right: 16,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(_ImageViewColorSet colors) {
    return AspectRatio(
      aspectRatio: 1,
      child: InteractiveViewer(
        panEnabled: true,
        scaleEnabled: true,
        minScale: 1.0,
        maxScale: 4.0,
        child: Image.network(
          widget.imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: double.infinity,
              height: 250,
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          (loadingProgress.expectedTotalBytes ?? 1)
                      : null,
                  color: colors.progressIndicatorColor,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: double.infinity,
            height: 250,
            child: Center(
              child: Icon(Icons.broken_image,
                  color: colors.errorIconColor, size: 48),
            ),
          ),
        ),
      ),
    );
  }

  // UPDATED: Navigate to comments using the proper CommentsBottomSheet
  void _navigateToComments(_ImageViewColorSet colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsBottomSheet(
        postId: widget.postId,
        postImage: widget.imageUrl,
        isVideo: _isVideo,
        onClose: () {
          // Video will automatically resume if it was playing before
        },
        videoController: _videoController,
      ),
    ).then((_) {
      _fetchCommentsCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final user = Provider.of<UserProvider>(context).user;

    final datePublished = _parseDate(widget.datePublished);
    final timeagoText =
        datePublished != null ? timeago.format(datePublished) : '';

    if (user == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: colors.progressIndicatorColor,
          ),
        ),
      );
    }

    if (_isBlocked) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: colors.appBarBackgroundColor,
          iconTheme: IconThemeData(color: colors.appBarIconColor),
        ),
        body: const BlockedContentMessage(
          message: 'Post unavailable due to blocking',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.appBarIconColor),
        backgroundColor: colors.appBarBackgroundColor,
        title: Text(
          widget.username,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textColor,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.appBarIconColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: colors.appBarIconColor),
            onPressed: () {
              if (FirebaseAuth.instance.currentUser?.uid == widget.userId) {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    backgroundColor: colors.dialogBackgroundColor,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shrinkWrap: true,
                      children: [
                        // Show progress indicator if deleting, otherwise show delete button
                        if (_isDeleting)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            child: Row(
                              children: [
                                CircularProgressIndicator(
                                  color: colors.progressIndicatorColor,
                                  strokeWidth: 2,
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Deleting...',
                                  style:
                                      TextStyle(color: colors.dialogTextColor),
                                ),
                              ],
                            ),
                          )
                        else
                          InkWell(
                            onTap: () => deletePost(widget.postId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              child: Text(
                                'Delete',
                                style: TextStyle(color: colors.dialogTextColor),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              } else {
                _showReportDialog(colors);
              }
            },
          ),
        ],
      ),
      backgroundColor: colors.backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16)
                  .copyWith(right: 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(uid: widget.userId),
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 21,
                      backgroundColor: colors.avatarBackgroundColor,
                      backgroundImage: (widget.profImage.isNotEmpty &&
                              widget.profImage != "default")
                          ? NetworkImage(widget.profImage)
                          : null,
                      child: (widget.profImage.isEmpty ||
                              widget.profImage == "default")
                          ? Icon(Icons.account_circle,
                              size: 42, color: colors.errorIconColor)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProfileScreen(uid: widget.userId),
                              ),
                            ),
                            child: Text(
                              widget.username,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.textColor,
                              ),
                            ),
                          ),
                          if (timeagoText.isNotEmpty)
                            Text(
                              timeagoText,
                              style: TextStyle(
                                color: colors.textColor.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildMediaContent(colors),
            if (widget.description.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.description,
                    style: TextStyle(
                      color: colors.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        // UPDATED: Use the new comment button
                        _buildCommentButton(colors),
                        IconButton(
                          icon: Icon(Icons.send, color: colors.iconColor),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => PostShare(
                                currentUserId: user.uid,
                                postId: widget.postId,
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RatingListScreen(
                                  postId: widget.postId,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.buttonBackgroundColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: _isLoadingRatings
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: colors.progressIndicatorColor,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Rated ${_averageRating.toStringAsFixed(1)} by $_totalRatingsCount ${_totalRatingsCount == 1 ? 'voter' : 'voters'}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
