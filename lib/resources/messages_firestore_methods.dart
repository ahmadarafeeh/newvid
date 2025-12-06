import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Ratedly/services/notification_service.dart';

class SupabaseMessagesMethods {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final Uuid _uuid = Uuid();

  // Existing sendMessage method remains for backward compatibility
  Future<String> sendMessage(
    String chatId,
    String senderId,
    String receiverId,
    String message,
  ) async {
    return sendMessageWithReply(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      message: message,
    );
  }

  Future<String> sendMessageWithReply({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String message,
    Map<String, dynamic>? repliedToMessage,
  }) async {
    try {
      // 1. Get current chat state BEFORE sending
      final currentChat = await _supabase
          .from('chats')
          .select(
              'streak_count, last_mutual_exchange, streak_checked_at, participants')
          .eq('id', chatId)
          .single();

      // 2. Check message history for debugging
      final recentMessages = await _supabase
          .from('messages')
          .select('sender_id, timestamp')
          .eq('chat_id', chatId)
          .gte(
              'timestamp',
              DateTime.now()
                  .subtract(Duration(hours: 24))
                  .toUtc()
                  .toIso8601String())
          .order('timestamp', ascending: false);

      // 3. Insert the message
      final messageData = {
        'chat_id': chatId,
        'sender_id': senderId,
        'receiver_id': receiverId,
        'message': message,
        'replied_to_message_id': repliedToMessage?['id'],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      if (repliedToMessage != null) {
        messageData['is_reply'] = true;
        messageData['replied_message_preview'] =
            _getMessagePreview(repliedToMessage);
        messageData['replied_message_sender'] =
            repliedToMessage['senderId'] == senderId ? 'You' : 'Them';
        messageData['replied_message_type'] =
            repliedToMessage['type'] ?? 'text';
      }

      final messageResult = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      // 4. Wait for trigger to complete
      await Future.delayed(Duration(seconds: 1));

      // 5. Get updated chat state
      final updatedChat = await _supabase
          .from('chats')
          .select(
              'streak_count, last_mutual_exchange, streak_checked_at, last_updated, last_message')
          .eq('id', chatId)
          .single();

      // 6. Analyze streak changes
      final oldStreak = currentChat['streak_count'] ?? 0;
      final newStreak = updatedChat['streak_count'] ?? 0;
      final streakChange = newStreak - oldStreak;

      if (streakChange > 0) {
        _sendStreakNotification(chatId, senderId, receiverId, newStreak);
      }

      // 7. Calculate time until streak expires
      final lastMutualExchange = updatedChat['last_mutual_exchange'];
      if (lastMutualExchange != null && newStreak > 0) {
        try {
          DateTime? lastMutualTime;
          if (lastMutualExchange is String) {
            lastMutualTime = DateTime.tryParse(lastMutualExchange);
          } else if (lastMutualExchange is DateTime) {
            lastMutualTime = lastMutualExchange;
          }

          if (lastMutualTime != null) {
            final streakExpiryTime = lastMutualTime.add(Duration(hours: 24));
            final now = DateTime.now().toUtc();
            final timeLeft = streakExpiryTime.difference(now);
          }
        } catch (e) {}
      }

      // 9. Send push notification - FIXED METHOD NAME
      try {
        await _notificationService.triggerServerNotification(
          type: 'message',
          targetUserId: receiverId,
          title: 'New Message',
          body:
              message.length > 30 ? '${message.substring(0, 30)}...' : message,
          customData: {
            'senderId': senderId,
            'chatId': chatId,
            'streakCount': newStreak,
            'message': message,
          },
        );
      } catch (e) {}

      return 'success';
    } catch (e) {
      return 'error: ${e.toString()}';
    }
  }

  // Add the new pagination method here
  Future<List<Map<String, dynamic>>> getMessagesPaginated(
    String chatId, {
    required int page,
    required int limit,
    DateTime? olderThan,
  }) async {
    try {
      final offset = page * limit;

      // Build the query step by step
      final query = _supabase.from('messages').select().eq('chat_id', chatId);

      // Try using the lt operator as a string in filter
      // or check if there's a different method name
      final filteredQuery = olderThan != null
          ? query.lt('timestamp', olderThan.toIso8601String())
          : query;

      final orderedQuery = filteredQuery.order('timestamp', ascending: false);
      final paginatedQuery = orderedQuery.range(offset, offset + limit - 1);

      final response = await paginatedQuery;

      // Map the response
      List<Map<String, dynamic>> messages = (response as List).map((message) {
        dynamic postShare = message['post_share'];
        Map<String, dynamic>? postShareData;

        if (postShare != null && postShare is Map) {
          postShareData = Map<String, dynamic>.from(postShare);
        }

        return {
          'id': message['id'],
          'message': message['message'],
          'senderId': message['sender_id'],
          'receiverId': message['receiver_id'],
          'timestamp': DateTime.parse(message['timestamp']),
          'isRead': message['is_read'],
          'delivered': message['delivered'],
          'type': postShareData != null ? 'post' : 'text',
          'postShare': postShareData,
          'isReply': message['is_reply'] ?? false,
          'repliedToMessageId': message['replied_to_message_id'],
          'repliedMessagePreview': message['replied_message_preview'],
          'repliedMessageSender': message['replied_message_sender'],
          'repliedMessageType': message['replied_message_type'],
        };
      }).toList();

      return messages.reversed.toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _sendStreakNotification(String chatId, String senderId,
      String receiverId, int streakCount) async {
    try {
      // Get sender username
      final senderData = await _supabase
          .from('users')
          .select('username')
          .eq('uid', senderId)
          .single();

      final senderName = senderData['username'] ?? 'Someone';

      // Prepare notification data
      final notificationData = {
        'title': '🔥 Streak Updated!',
        'body': '$senderName: Streak is now $streakCount days! Keep it going!',
        'data': {
          'type': 'streak_update',
          'chatId': chatId,
          'streakCount': streakCount,
          'senderId': senderId,
        },
      };
    } catch (e) {}
  }

  String _getMessagePreview(Map<String, dynamic> message) {
    if (message['type'] == 'post') {
      return 'Shared a post';
    }

    String text = message['message'] ?? '';
    if (text.length > 30) {
      return '${text.substring(0, 30)}...';
    }
    return text;
  }

  Future<String> _getUsername(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select('username')
          .eq('uid', userId)
          .single();
      return response['username'] ?? 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  Stream<List<Map<String, dynamic>>> getMessages(String chatId) {
    return _supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .order('timestamp')
        .asStream()
        .map((messages) => messages.map((message) {
              dynamic postShare = message['post_share'];
              Map<String, dynamic>? postShareData;

              if (postShare != null && postShare is Map) {
                postShareData = Map<String, dynamic>.from(postShare);
              }

              return {
                'id': message['id'],
                'message': message['message'],
                'senderId': message['sender_id'],
                'receiverId': message['receiver_id'],
                'timestamp': DateTime.parse(message['timestamp']),
                'isRead': message['is_read'],
                'delivered': message['delivered'],
                'type': postShareData != null ? 'post' : 'text',
                'postShare': postShareData,
                'isReply': message['is_reply'] ?? false,
                'repliedToMessageId': message['replied_to_message_id'],
                'repliedMessagePreview': message['replied_message_preview'],
                'repliedMessageSender': message['replied_message_sender'],
                'repliedMessageType': message['replied_message_type'],
              };
            }).toList());
  }

  Future<Map<String, dynamic>?> getMessageById(String messageId) async {
    try {
      final message = await _supabase
          .from('messages')
          .select()
          .eq('id', messageId)
          .single();

      dynamic postShare = message['post_share'];
      Map<String, dynamic>? postShareData;

      if (postShare != null && postShare is Map) {
        postShareData = Map<String, dynamic>.from(postShare);
      }

      return {
        'id': message['id'],
        'message': message['message'],
        'senderId': message['sender_id'],
        'receiverId': message['receiver_id'],
        'timestamp': DateTime.parse(message['timestamp']),
        'isRead': message['is_read'],
        'delivered': message['delivered'],
        'type': postShareData != null ? 'post' : 'text',
        'postShare': postShareData,
        'isReply': message['is_reply'] ?? false,
      };
    } catch (e) {
      return null;
    }
  }

  Future<String> getOrCreateChat(String user1, String user2) async {
    try {
      final chatResponse = await _supabase
          .from('chats')
          .select('id, streak_count, last_mutual_exchange, participants')
          .contains('participants', [user1, user2]);

      if (chatResponse.isNotEmpty) {
        return chatResponse[0]['id'];
      }

      final newChatId = _uuid.v1();

      await _supabase.from('chats').insert({
        'id': newChatId,
        'participants': [user1, user2],
        'last_message': '',
        'streak_count': 0,
        'last_mutual_exchange': null,
      });

      return newChatId;
    } catch (e) {
      return e.toString();
    }
  }

  Stream<int> getTotalUnreadCount(String currentUserId) {
    return _supabase
        .from('messages')
        .select()
        .eq('receiver_id', currentUserId)
        .eq('is_read', false)
        .asStream()
        .map((messages) => messages.length);
  }

  Stream<int> getUnreadCount(String chatId, String currentUserId) {
    return _supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .eq('receiver_id', currentUserId)
        .eq('is_read', false)
        .asStream()
        .map((messages) => messages.length);
  }

  Future<void> markMessagesAsRead(String chatId, String currentUserId) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('chat_id', chatId)
          .eq('receiver_id', currentUserId)
          .eq('is_read', false);
    } catch (e) {}
  }

  Future<void> markMessageAsDelivered(String messageId) async {
    try {
      await _supabase
          .from('messages')
          .update({'delivered': true}).eq('id', messageId);
    } catch (e) {}
  }

  Future<void> markMessageAsSeen(String messageId) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true, 'delivered': true}).eq('id', messageId);
    } catch (e) {}
  }

  Future<void> deleteAllUserMessages(String uid) async {
    try {
      final chatsResponse = await _supabase
          .from('chats')
          .select('id')
          .contains('participants', [uid]);

      if (chatsResponse.isNotEmpty) {
        final chatIds =
            chatsResponse.map((chat) => chat['id'] as String).toList();

        for (final chatId in chatIds) {
          await _supabase.from('messages').delete().eq('chat_id', chatId);
        }

        for (final chatId in chatIds) {
          await _supabase.from('chats').delete().eq('id', chatId);
        }
      }
    } catch (e) {}
  }

  Stream<List<Map<String, dynamic>>> getUserChats(String userId) {
    return _supabase
        .from('chats')
        .select()
        .contains('participants', [userId])
        .order('last_updated', ascending: false)
        .asStream()
        .map((chats) => chats
            .map((chat) => {
                  'id': chat['id'],
                  'participants': List<String>.from(chat['participants']),
                  'lastMessage': chat['last_message'],
                  'lastUpdated': DateTime.parse(chat['last_updated']),
                  'streakCount': chat['streak_count'] ?? 0,
                  'streakCheckedAt': chat['streak_checked_at'],
                  'lastMutualExchange': chat['last_mutual_exchange'],
                })
            .toList());
  }

  Future<int> getStreakCount(String chatId) async {
    try {
      final response = await _supabase
          .from('chats')
          .select('streak_count')
          .eq('id', chatId)
          .single();

      return response['streak_count'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getStreakBetweenUsers(String user1, String user2) async {
    try {
      final chatResponse = await _supabase
          .from('chats')
          .select('streak_count')
          .contains('participants', [user1, user2]).single();

      return chatResponse['streak_count'] ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // Test function to debug streak logic
  Future<void> testStreakLogic(
      String chatId, String user1, String user2) async {
    // Clear existing messages (for testing only)
    await _supabase.from('messages').delete().eq('chat_id', chatId);

    // Reset streak
    await _supabase.from('chats').update({
      'streak_count': 0,
      'last_mutual_exchange': null,
      'streak_checked_at': null,
    }).eq('id', chatId);

    await sendMessageWithReply(
      chatId: chatId,
      senderId: user1,
      receiverId: user2,
      message: 'Test 1: Hello from A',
    );

    await Future.delayed(Duration(seconds: 2));

    await sendMessageWithReply(
      chatId: chatId,
      senderId: user2,
      receiverId: user1,
      message: 'Test 2: Hi from B',
    );

    await Future.delayed(Duration(seconds: 2));

    await sendMessageWithReply(
      chatId: chatId,
      senderId: user1,
      receiverId: user2,
      message: 'Test 3: How are you?',
    );
  }
}
