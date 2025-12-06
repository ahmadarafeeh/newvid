// lib/widgets/postshare.dart
import 'package:flutter/material.dart';
import 'package:Ratedly/resources/messages_firestore_methods.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/resources/block_firestore_methods.dart';

// Define color schemes for both themes at top level
class _PostShareColorSet {
  final Color backgroundColor;
  final Color textColor;
  final Color iconColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color blueColor;
  final Color progressIndicatorColor;
  final Color checkboxColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color borderColor;
  final Color cardColor;
  final Color unreadBadgeColor;

  _PostShareColorSet({
    required this.backgroundColor,
    required this.textColor,
    required this.iconColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.blueColor,
    required this.progressIndicatorColor,
    required this.checkboxColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.borderColor,
    required this.cardColor,
    required this.unreadBadgeColor,
  });
}

class _PostShareDarkColors extends _PostShareColorSet {
  _PostShareDarkColors()
      : super(
          backgroundColor: const Color(0xFF121212),
          textColor: const Color(0xFFd9d9d9),
          iconColor: const Color(0xFFd9d9d9),
          primaryColor: const Color(0xFFd9d9d9),
          secondaryColor: const Color(0xFF333333),
          blueColor: const Color(0xFF0095f6),
          progressIndicatorColor: const Color(0xFFd9d9d9),
          checkboxColor: const Color(0xFF333333),
          buttonBackgroundColor: const Color(0xFF0095f6),
          buttonTextColor: const Color(0xFFd9d9d9),
          borderColor: const Color(0xFF333333),
          cardColor: const Color(0xFF333333),
          unreadBadgeColor: const Color(0xFFd9d9d9).withOpacity(0.1),
        );
}

class _PostShareLightColors extends _PostShareColorSet {
  _PostShareLightColors()
      : super(
          backgroundColor: Colors.white,
          textColor: Colors.black,
          iconColor: Colors.black,
          primaryColor: Colors.black,
          secondaryColor: Colors.grey[300]!,
          blueColor: const Color(0xFF0095f6),
          progressIndicatorColor: Colors.black,
          checkboxColor: Colors.grey[300]!,
          buttonBackgroundColor: const Color(0xFF0095f6),
          buttonTextColor: Colors.white,
          borderColor: Colors.grey[400]!,
          cardColor: Colors.grey[100]!,
          unreadBadgeColor: Colors.black.withOpacity(0.1),
        );
}

class PostShare extends StatefulWidget {
  final String currentUserId;
  final String postId;

  const PostShare({
    Key? key,
    required this.currentUserId,
    required this.postId,
  }) : super(key: key);

  @override
  _PostShareState createState() => _PostShareState();
}

class _PostShareState extends State<PostShare>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final Set<String> selectedUsers = <String>{};
  bool _isSharing = false;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Pagination and state management like FeedMessages
  List<Map<String, dynamic>> _chatsWithUsers = [];
  List<String> _blockedUsers = [];
  final Map<String, Map<String, dynamic>> _userCache = {};
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMoreChats = true;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  // Helper method to get the appropriate color scheme
  _PostShareColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _PostShareDarkColors() : _PostShareLightColors();
  }

  DateTime? _parseDateTime(dynamic dateValue) {
    if (dateValue == null) return null;

    if (dateValue is DateTime) {
      return dateValue;
    }

    if (dateValue is String) {
      try {
        return DateTime.tryParse(dateValue);
      } catch (e) {
        print('[PostShare] Error parsing date string: $dateValue, error: $e');
        return null;
      }
    }

    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    print(
        '[PostShare] initState called, currentUserId: ${widget.currentUserId}');
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    print('[PostShare] dispose called');
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      print('[PostShare] Reached bottom, loading more chats');
      _loadMoreChats();
    }
  }

  Future<void> _loadInitialData() async {
    print('[PostShare] _loadInitialData started');
    if (!mounted) {
      print('[PostShare] Widget not mounted, returning');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('[PostShare] Loading blocked users and chats...');
      await Future.wait([
        _loadBlockedUsers(),
        _loadChatsWithUsersMinimal(),
      ]);

      print(
          '[PostShare] Initial data loaded, chats count: ${_chatsWithUsers.length}');
      print('[PostShare] Blocked users count: ${_blockedUsers.length}');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      // Load additional user data in background
      _loadAdditionalDataInBackground();
    } catch (e) {
      print('[PostShare] Error in _loadInitialData: $e');
      print('[PostShare] Stack trace: ${e.toString()}');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadChatsWithUsersMinimal() async {
    print('[PostShare] _loadChatsWithUsersMinimal started');
    try {
      // Get chats ordered by last_updated in descending order (most recent first)
      print('[PostShare] Querying chats for user: ${widget.currentUserId}');
      final chats = await _supabase
          .from('chats')
          .select('id, participants, last_updated')
          .contains('participants', [widget.currentUserId])
          .order('last_updated', ascending: false)
          .limit(11); // Load 11 to check if there are more

      print('[PostShare] Raw chats response: $chats');
      print('[PostShare] Chats count from query: ${chats.length}');

      if (chats.isEmpty) {
        print('[PostShare] No chats found');
        _chatsWithUsers = [];
        return;
      }

      final List<Map<String, dynamic>> validChats = [];
      for (final chat in chats) {
        final participants = List<String>.from(chat['participants'] ?? []);
        print(
            '[PostShare] Processing chat: ${chat['id']}, participants: $participants');

        final otherUserId = participants.firstWhere(
          (id) => id != widget.currentUserId,
          orElse: () => '',
        );

        print('[PostShare] Other user ID: $otherUserId');
        print('[PostShare] Is blocked: ${_blockedUsers.contains(otherUserId)}');

        if (otherUserId.isNotEmpty && !_blockedUsers.contains(otherUserId)) {
          final chatCopy = Map<String, dynamic>.from(chat);

          // Parse dates for potential future use
          if (chatCopy['last_updated'] != null) {
            chatCopy['last_updated'] = _parseDateTime(chatCopy['last_updated']);
          }

          validChats.add(chatCopy);
          print('[PostShare] Added chat with user: $otherUserId');
        }
      }

      print('[PostShare] Valid chats count: ${validChats.length}');

      if (mounted) {
        setState(() {
          _chatsWithUsers = validChats;
          _hasMoreChats = chats.length == 11;
        });
      }

      print('[PostShare] Has more chats: $_hasMoreChats');
    } catch (e) {
      print('[PostShare] Error in _loadChatsWithUsersMinimal: $e');
      print('[PostShare] Stack trace: ${e.toString()}');
    }
  }

  Future<void> _loadMoreChats() async {
    if (!_hasMoreChats) {
      print('[PostShare] No more chats to load');
      return;
    }
    if (_loadingMore) {
      print('[PostShare] Already loading more');
      return;
    }

    print(
        '[PostShare] _loadMoreChats started, current count: ${_chatsWithUsers.length}');
    setState(() {
      _loadingMore = true;
    });

    final start = _chatsWithUsers.length;
    final end = start + 10;

    try {
      final moreChats = await _supabase
          .from('chats')
          .select('id, participants, last_updated')
          .contains('participants', [widget.currentUserId])
          .order('last_updated', ascending: false)
          .range(start, end);

      print('[PostShare] More chats loaded: ${moreChats.length}');

      if (moreChats.isEmpty) {
        print('[PostShare] No more chats found');
        setState(() {
          _hasMoreChats = false;
          _loadingMore = false;
        });
        return;
      }

      final List<Map<String, dynamic>> parsedChats = [];
      for (final chat in moreChats) {
        final participants = List<String>.from(chat['participants'] ?? []);
        final otherUserId = participants.firstWhere(
          (id) => id != widget.currentUserId,
          orElse: () => '',
        );

        if (otherUserId.isNotEmpty && !_blockedUsers.contains(otherUserId)) {
          final chatCopy = Map<String, dynamic>.from(chat);

          if (chatCopy['last_updated'] != null) {
            chatCopy['last_updated'] = _parseDateTime(chatCopy['last_updated']);
          }

          parsedChats.add(chatCopy);
        }
      }

      print('[PostShare] Parsed new chats: ${parsedChats.length}');

      setState(() {
        _chatsWithUsers.addAll(parsedChats);
        _loadingMore = false;
        _hasMoreChats = moreChats.length == 11;
      });

      print('[PostShare] Total chats now: ${_chatsWithUsers.length}');
      print('[PostShare] Has more chats after load: $_hasMoreChats');

      _loadUsersForNewChats(parsedChats);
    } catch (e) {
      print('[PostShare] Error in _loadMoreChats: $e');
      setState(() {
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadAdditionalDataInBackground() async {
    print('[PostShare] _loadAdditionalDataInBackground started');
    if (_chatsWithUsers.isEmpty) {
      print('[PostShare] No chats to load additional data for');
      return;
    }

    final userIds = <String>[];
    for (final chat in _chatsWithUsers) {
      final participants = List<String>.from(chat['participants'] ?? []);
      final otherUserId = participants.firstWhere(
        (id) => id != widget.currentUserId,
      );
      userIds.add(otherUserId);
    }

    print('[PostShare] Loading batch user data for ${userIds.length} users');
    await _loadUsersBatch(userIds);
    print('[PostShare] Background data loading complete');
  }

  Future<void> _loadUsersForNewChats(
      List<Map<String, dynamic>> newChats) async {
    print('[PostShare] _loadUsersForNewChats for ${newChats.length} new chats');
    final newUserIds = <String>{};

    for (final chat in newChats) {
      final participants = List<String>.from(chat['participants'] ?? []);
      final otherUserId = participants.firstWhere(
        (id) => id != widget.currentUserId,
      );
      if (!_userCache.containsKey(otherUserId)) {
        newUserIds.add(otherUserId);
      }
    }

    print('[PostShare] New user IDs to load: ${newUserIds.length}');
    if (newUserIds.isNotEmpty) {
      await _loadUsersBatch(newUserIds.toList());
    }
  }

  Future<void> _loadUsersBatch(List<String> userIds) async {
    print('[PostShare] _loadUsersBatch for ${userIds.length} users');
    if (userIds.isEmpty) {
      print('[PostShare] No user IDs to load');
      return;
    }

    try {
      // FIXED: Using correct column name - photoUrl instead of photo_url
      final users = await _supabase
          .from('users')
          .select('uid, username, photoUrl, country')
          .inFilter('uid', userIds);

      print('[PostShare] Users loaded from DB: ${users.length}');
      print(
          '[PostShare] Sample user data: ${users.isNotEmpty ? users[0] : "No users"}');

      for (final user in users) {
        _userCache[user['uid']] = user;
        print('[PostShare] Cached user: ${user['uid']} - ${user['username']}');
      }

      // Fill in missing users with placeholder data
      for (final userId in userIds) {
        if (!_userCache.containsKey(userId)) {
          print('[PostShare] User not found in DB: $userId, using placeholder');
          _userCache[userId] = {
            'uid': userId,
            'username': 'User Not Found',
            'photoUrl': 'default', // Fixed key name
            'country': null,
          };
        }
      }

      if (mounted) {
        print('[PostShare] Updating UI with user cache');
        setState(() {});
      }
    } catch (e) {
      print('[PostShare] Error in _loadUsersBatch: $e');
      print('[PostShare] Stack trace: ${e.toString()}');
    }
  }

  Future<void> _loadBlockedUsers() async {
    print('[PostShare] _loadBlockedUsers started');
    try {
      final blockedUsers =
          await SupabaseBlockMethods().getBlockedUsers(widget.currentUserId);

      print('[PostShare] Blocked users loaded: ${blockedUsers.length}');

      if (mounted) {
        setState(() {
          _blockedUsers = blockedUsers;
        });
      }
    } catch (e) {
      print('[PostShare] Error in _loadBlockedUsers: $e');
      if (mounted) {
        setState(() {
          _blockedUsers = [];
        });
      }
    }
  }

  Future<void> _sharePost() async {
    print(
        '[PostShare] _sharePost started, selected users: ${selectedUsers.length}');
    if (_isSharing || selectedUsers.isEmpty) {
      print(
          '[PostShare] Cannot share: isSharing=$_isSharing, selectedUsers empty=${selectedUsers.isEmpty}');
      return;
    }

    setState(() => _isSharing = true);

    try {
      print('[PostShare] Fetching post data for postId: ${widget.postId}');
      // Fetch post data from Supabase
      final postResponse = await _supabase
          .from('posts')
          .select()
          .eq('postId', widget.postId)
          .single();

      print('[PostShare] Post response: $postResponse');

      if (postResponse.isEmpty) {
        throw Exception('Post does not exist');
      }

      final Map<String, dynamic> postData = postResponse;
      final String postImageUrl = (postData['postUrl'] ?? '').toString();
      final String postCaption = (postData['description'] ?? '').toString();
      final String postOwnerId = (postData['uid'] ?? '').toString();

      print(
          '[PostShare] Post data - imageUrl: $postImageUrl, caption: $postCaption, ownerId: $postOwnerId');

      // Fetch user data from Supabase
      final userResponse = await _supabase
          .from('users')
          .select()
          .eq('uid', postOwnerId)
          .single();

      print('[PostShare] Post owner user response: $userResponse');

      final Map<String, dynamic> userData = userResponse;
      final String postOwnerUsername =
          (userData['username'] ?? 'Unknown User').toString();
      final String postOwnerPhotoUrl =
          (userData['photoUrl'] ?? '').toString().trim();

      print(
          '[PostShare] Post owner - username: $postOwnerUsername, photoUrl: $postOwnerPhotoUrl');

      // iterate recipients
      for (final userId in selectedUsers) {
        print('[PostShare] Sharing with user: $userId');
        // Get or create chat in Firestore (keeps your existing chat model)
        final chatId = await SupabaseMessagesMethods()
            .getOrCreateChat(widget.currentUserId, userId);

        print('[PostShare] Chat ID: $chatId');

        // Use Supabase method to insert message/post share into Supabase chat_messages table.
        await SupabasePostsMethods().sharePostThroughChat(
          chatId: chatId,
          senderId: widget.currentUserId,
          receiverId: userId,
          postId: widget.postId,
          postImageUrl: postImageUrl,
          postCaption: postCaption,
          postOwnerId: postOwnerId,
          postOwnerUsername: postOwnerUsername,
          postOwnerPhotoUrl: postOwnerPhotoUrl,
        );

        print('[PostShare] Successfully shared with $userId');
      }

      if (!mounted) {
        print('[PostShare] Widget not mounted after sharing');
        return;
      }

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Post shared with ${selectedUsers.length} user(s)'),
          duration: const Duration(seconds: 2),
        ),
      );

      print('[PostShare] Share completed successfully');
    } catch (e) {
      print('[PostShare] Error in _sharePost: $e');
      print('[PostShare] Stack trace: ${e.toString()}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Something went wrong, please try again later or contact us at ratedly9@gmail.com',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (!mounted) {
        print('[PostShare] Widget not mounted in finally');
        return;
      }
      setState(() => _isSharing = false);
    }
  }

  Widget _buildUserAvatar(String photoUrl, _PostShareColorSet colors) {
    final hasValidPhoto =
        photoUrl.isNotEmpty && photoUrl != "default" && photoUrl != "null";

    print(
        '[PostShare] Building avatar, photoUrl: $photoUrl, hasValidPhoto: $hasValidPhoto');

    return CircleAvatar(
      radius: 21,
      backgroundColor: colors.cardColor,
      backgroundImage: hasValidPhoto ? NetworkImage(photoUrl) : null,
      child: !hasValidPhoto
          ? Icon(
              Icons.account_circle,
              size: 42,
              color: colors.iconColor,
            )
          : null,
    );
  }

  Widget _buildLoadingIndicator(_PostShareColorSet colors) {
    print('[PostShare] Building loading indicator');
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: CircularProgressIndicator(
          color: colors.progressIndicatorColor,
        ),
      ),
    );
  }

  Widget _buildChatSkeleton(_PostShareColorSet colors) {
    print('[PostShare] Building chat skeleton');
    return ListTile(
      leading: CircleAvatar(
        radius: 21,
        backgroundColor: colors.cardColor.withOpacity(0.5),
      ),
      title: Container(
        height: 16,
        width: 120,
        decoration: BoxDecoration(
          color: colors.cardColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      subtitle: Container(
        height: 14,
        width: 80,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: colors.cardColor.withOpacity(0.4),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colors.cardColor.withOpacity(0.4),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);

    print(
        '[PostShare] build called, isLoading: $_isLoading, chats count: ${_chatsWithUsers.length}');

    return Dialog(
      backgroundColor: colors.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: colors.borderColor),
      ),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share Post',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textColor,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? ListView.builder(
                      itemCount: 3,
                      itemBuilder: (context, index) =>
                          _buildChatSkeleton(colors),
                    )
                  : _chatsWithUsers.isEmpty
                      ? _buildEmptyStateMessage(colors)
                      : _buildChatsList(colors),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _isSharing || selectedUsers.isEmpty ? null : _sharePost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.buttonBackgroundColor,
                  foregroundColor: colors.buttonTextColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSharing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              colors.progressIndicatorColor),
                        ),
                      )
                    : const Text('Share Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateMessage(_PostShareColorSet colors) {
    print('[PostShare] Building empty state message');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 60,
              color: colors.iconColor.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No users to share with yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: colors.textColor.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start conversations with other users\nto share posts with them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colors.textColor.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsList(_PostShareColorSet colors) {
    final totalItemCount = _chatsWithUsers.length + (_hasMoreChats ? 1 : 0);

    print('[PostShare] Building chats list, total items: $totalItemCount');
    print('[PostShare] User cache size: ${_userCache.length}');

    return ListView.builder(
      controller: _scrollController,
      itemCount: totalItemCount,
      itemBuilder: (context, index) {
        if (index >= _chatsWithUsers.length) {
          print('[PostShare] Building loading indicator at index $index');
          return _buildLoadingIndicator(colors);
        }

        final chat = _chatsWithUsers[index];
        final participants = List<String>.from(chat['participants'] ?? []);
        final otherUserId = participants.firstWhere(
          (id) => id != widget.currentUserId,
          orElse: () => '',
        );

        print(
            '[PostShare] Building item $index, chat ID: ${chat['id']}, otherUserId: $otherUserId');

        if (otherUserId.isEmpty) {
          print('[PostShare] Empty otherUserId, returning empty widget');
          return const SizedBox.shrink();
        }

        if (_blockedUsers.contains(otherUserId)) {
          print('[PostShare] User $otherUserId is blocked, skipping');
          return const SizedBox.shrink();
        }

        final userData = _userCache[otherUserId];
        print(
            '[PostShare] User data for $otherUserId: ${userData != null ? "found" : "not found"}');

        if (userData == null) {
          print('[PostShare] Building skeleton for $otherUserId');
          return _buildChatSkeleton(colors);
        }

        final username = userData['username'] ?? 'Unknown User';
        // FIXED: Use photoUrl instead of photo_url
        final photoUrl = userData['photoUrl'] ?? 'default';
        final countryCode = userData['country']?.toString();

        print('[PostShare] Building ListTile for $username ($otherUserId)');
        print('[PostShare] Photo URL: $photoUrl');

        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.cardColor, width: 0.5),
            ),
          ),
          child: ListTile(
            leading: _buildUserAvatar(photoUrl, colors),
            title: Text(
              username,
              style: TextStyle(
                color: colors.textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: countryCode != null
                ? Text(
                    'From $countryCode',
                    style: TextStyle(
                      color: colors.textColor.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: Checkbox(
              value: selectedUsers.contains(otherUserId),
              checkColor: colors.primaryColor,
              fillColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => colors.checkboxColor,
              ),
              onChanged: _isSharing
                  ? null
                  : (bool? selected) {
                      print(
                          '[PostShare] Checkbox changed for $otherUserId: $selected');
                      setState(() {
                        if (selected == true) {
                          selectedUsers.add(otherUserId);
                        } else {
                          selectedUsers.remove(otherUserId);
                        }
                        print('[PostShare] Selected users now: $selectedUsers');
                      });
                    },
            ),
            onTap: _isSharing
                ? null
                : () {
                    print('[PostShare] ListTile tapped for $otherUserId');
                    setState(() {
                      if (selectedUsers.contains(otherUserId)) {
                        selectedUsers.remove(otherUserId);
                      } else {
                        selectedUsers.add(otherUserId);
                      }
                      print(
                          '[PostShare] Selected users after tap: $selectedUsers');
                    });
                  },
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[PostShare] App lifecycle state changed: $state');
    if (state == AppLifecycleState.resumed) {
      print('[PostShare] App resumed, refreshing data');
      _loadInitialData();
    }
  }
}
