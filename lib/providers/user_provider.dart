import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:Ratedly/models/user.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

class UserProvider with ChangeNotifier {
  AppUser? _user;
  String? _firebaseUid;
  String? _supabaseUid;
  bool _isMigrated = false;
  final AuthMethods _authMethods = AuthMethods();
  final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  AppUser? get user => _user;
  String? get firebaseUid => _firebaseUid;
  String? get supabaseUid => _supabaseUid;
  bool get isMigrated => _isMigrated;

  // ===========================================================================
  // ERROR LOGGING HELPER
  // ===========================================================================
  Future<void> _logProviderError({
    required String operation,
    required dynamic error,
    StackTrace? stack,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _supabase.from('login_logs').insert({
        'event_type': 'PROVIDER_ERROR',
        'firebase_uid': _firebaseUid,
        'supabase_uid': _supabaseUid,
        'error_details': error.toString(),
        'stack_trace': stack?.toString(),
        'additional_data': {
          'operation': operation,
          if (additionalData != null) ...additionalData,
        },
      });
    } catch (_) {
      // Silently ignore logging failures
    }
  }

  // ===========================================================================
  // USER INITIALIZATION
  // ===========================================================================
  void initializeUser(Map<String, dynamic> userData) {
    try {
      _firebaseUid = userData['uid'] as String?;
      _supabaseUid = userData['supabase_uid'] as String?;
      _isMigrated = userData['migrated'] == true;

      final Map<String, dynamic> appUserData =
          Map<String, dynamic>.from(userData);
      appUserData.remove('supabase_uid');
      appUserData.remove('migrated');

      _user = AppUser.fromMap(appUserData);

      notifyListeners();
    } catch (e, stack) {
      _logProviderError(operation: 'initializeUser', error: e, stack: stack);
    }
  }

  void setUser(AppUser user, {String? supabaseUid, bool migrated = false}) {
    try {
      _user = user;
      _firebaseUid = user.uid;
      _supabaseUid = supabaseUid;
      _isMigrated = migrated;

      notifyListeners();
    } catch (e, stack) {
      _logProviderError(operation: 'setUser', error: e, stack: stack);
    }
  }

  void setUserFromCompleteData(Map<String, dynamic> userData) {
    try {
      _firebaseUid = userData['uid'] as String?;
      _supabaseUid = userData['supabase_uid'] as String?;
      _isMigrated = userData['migrated'] == true;

      final Map<String, dynamic> appUserData =
          Map<String, dynamic>.from(userData);
      appUserData.remove('supabase_uid');
      appUserData.remove('migrated');

      _user = AppUser.fromMap(appUserData);

      notifyListeners();
    } catch (e, stack) {
      _logProviderError(
          operation: 'setUserFromCompleteData', error: e, stack: stack);
    }
  }

  // ===========================================================================
  // REFRESH USER
  // ===========================================================================
  Future<void> refreshUser() async {
    try {
      final firebase_auth.User? firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        try {
          final supabaseUser = _supabase.auth.currentUser;
          if (supabaseUser != null) {
            await _refreshFromSupabase(supabaseUser.id);
            return;
          }
        } catch (e, stack) {
          await _logProviderError(
              operation: 'refreshUser/supabaseCheck', error: e, stack: stack);
        }

        _user = null;
        _firebaseUid = null;
        _supabaseUid = null;
        _isMigrated = false;
        notifyListeners();
        return;
      }

      final Map<String, dynamic>? userData =
          await _getUserDataByFirebaseUid(firebaseUser.uid);

      if (userData != null) {
        setUserFromCompleteData(userData);

        final results = await Future.wait([
          _authMethods.getUserFollowers(firebaseUser.uid),
          _authMethods.getUserFollowing(firebaseUser.uid),
          _authMethods.getFollowRequests(firebaseUser.uid),
        ]);

        final List<String> followers = results[0] as List<String>;
        final List<String> following = results[1] as List<String>;
        final List<String> requests = results[2] as List<String>;

        if (_user != null) {
          _user = _user!.withRelationships(
            followers: followers,
            following: following,
            followRequests: requests,
          );
          notifyListeners();
        }
      } else {
        _user = null;
        _firebaseUid = null;
        _supabaseUid = null;
        _isMigrated = false;
        notifyListeners();
      }
    } catch (e, stack) {
      await _logProviderError(operation: 'refreshUser', error: e, stack: stack);
      _user = null;
      _firebaseUid = null;
      _supabaseUid = null;
      _isMigrated = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // HELPER METHODS
  // ===========================================================================
  Future<Map<String, dynamic>?> _getUserDataByFirebaseUid(
      String firebaseUid) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', firebaseUid)
          .limit(1);

      if (response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }
    } catch (e, stack) {
      await _logProviderError(
          operation: '_getUserDataByFirebaseUid',
          error: e,
          stack: stack,
          additionalData: {'firebaseUid': firebaseUid});
    }
    return null;
  }

  Future<void> _refreshFromSupabase(String supabaseUid) async {
    try {
      final userData = await _getUserDataBySupabaseUid(supabaseUid);
      if (userData != null) {
        setUserFromCompleteData(userData);

        if (_firebaseUid != null) {
          final results = await Future.wait([
            _authMethods.getUserFollowers(_firebaseUid!),
            _authMethods.getUserFollowing(_firebaseUid!),
            _authMethods.getFollowRequests(_firebaseUid!),
          ]);

          final List<String> followers = results[0] as List<String>;
          final List<String> following = results[1] as List<String>;
          final List<String> requests = results[2] as List<String>;

          if (_user != null) {
            _user = _user!.withRelationships(
              followers: followers,
              following: following,
              followRequests: requests,
            );
            notifyListeners();
          }
        }
      } else {
        await _logProviderError(
            operation: '_refreshFromSupabase',
            error: 'No user data found for supabaseUid $supabaseUid');
      }
    } catch (e, stack) {
      await _logProviderError(
          operation: '_refreshFromSupabase',
          error: e,
          stack: stack,
          additionalData: {'supabaseUid': supabaseUid});
    }
  }

  Future<Map<String, dynamic>?> _getUserDataBySupabaseUid(
      String supabaseUid) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('supabase_uid', supabaseUid)
          .limit(1);

      if (response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }
    } catch (e, stack) {
      await _logProviderError(
          operation: '_getUserDataBySupabaseUid',
          error: e,
          stack: stack,
          additionalData: {'supabaseUid': supabaseUid});
    }
    return null;
  }

  // ===========================================================================
  // CLEAR / UPDATE
  // ===========================================================================
  void clearUser() {
    _user = null;
    _firebaseUid = null;
    _supabaseUid = null;
    _isMigrated = false;
    notifyListeners();
  }

  void updateUser(Map<String, dynamic> updates) {
    if (_user != null) {
      try {
        final updatedMap = _user!.toMap();
        updatedMap.addAll(updates);
        _user = AppUser.fromMap(updatedMap);

        if (updates.containsKey('uid')) {
          _firebaseUid = updates['uid'] as String?;
        }
        if (updates.containsKey('supabase_uid')) {
          _supabaseUid = updates['supabase_uid'] as String?;
        }
        if (updates.containsKey('migrated')) {
          _isMigrated = updates['migrated'] == true;
        }

        notifyListeners();
      } catch (e, stack) {
        _logProviderError(operation: 'updateUser', error: e, stack: stack);
      }
    }
  }

  // Safe UID getter – returns Firebase UID for data operations, but logs if both are missing
  String? get safeUID {
    if (_firebaseUid == null && _supabaseUid == null) {
      _logProviderError(operation: 'safeUID', error: 'Both UIDs are null');
    }
    return _firebaseUid ?? _supabaseUid;
  }

  void debugInfo() {
    // Debug functionality removed – use logging service instead
  }
}
