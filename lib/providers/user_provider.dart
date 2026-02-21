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

  // Initialize user with both Firebase and Supabase UIDs
  void initializeUser(Map<String, dynamic> userData) {
    try {
      _firebaseUid = userData['uid'] as String?;
      _supabaseUid = userData['supabase_uid'] as String?;
      _isMigrated = userData['migrated'] == true;

      // Create AppUser from data (excluding supabase-specific fields)
      final Map<String, dynamic> appUserData =
          Map<String, dynamic>.from(userData);
      appUserData.remove('supabase_uid');
      appUserData.remove('migrated');

      _user = AppUser.fromMap(appUserData);

      notifyListeners();
    } catch (e) {
      // Error initializing UserProvider
    }
  }

  // Set user from AppUser with optional Supabase info
  void setUser(AppUser user, {String? supabaseUid, bool migrated = false}) {
    _user = user;
    _firebaseUid = user.uid;
    _supabaseUid = supabaseUid;
    _isMigrated = migrated;

    notifyListeners();
  }

  // Set user from complete data map
  void setUserFromCompleteData(Map<String, dynamic> userData) {
    try {
      _firebaseUid = userData['uid'] as String?;
      _supabaseUid = userData['supabase_uid'] as String?;
      _isMigrated = userData['migrated'] == true;

      // Create AppUser (excluding supabase-specific fields)
      final Map<String, dynamic> appUserData =
          Map<String, dynamic>.from(userData);
      appUserData.remove('supabase_uid');
      appUserData.remove('migrated');

      _user = AppUser.fromMap(appUserData);

      notifyListeners();
    } catch (e) {
      // Error setting user from complete data
    }
  }

  // Refresh user data from database
  Future<void> refreshUser() async {
    try {
      // Get current Firebase user
      final firebase_auth.User? firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        // Try to get user from Supabase session
        try {
          final supabaseUser = _supabase.auth.currentUser;
          if (supabaseUser != null) {
            await _refreshFromSupabase(supabaseUser.id);
            return;
          }
        } catch (e) {
          // Supabase user check failed
        }

        // Clear user if no auth found
        _user = null;
        _firebaseUid = null;
        _supabaseUid = null;
        _isMigrated = false;
        notifyListeners();
        return;
      }

      // Try to get user data by Firebase UID
      final Map<String, dynamic>? userData =
          await _getUserDataByFirebaseUid(firebaseUser.uid);

      if (userData != null) {
        setUserFromCompleteData(userData);

        // Run follower/following/request queries in parallel for speed
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
    } catch (e) {
      // Error refreshing user
      _user = null;
      _firebaseUid = null;
      _supabaseUid = null;
      _isMigrated = false;
      notifyListeners();
    }
  }

  // Helper method to get user data by Firebase UID
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
    } catch (e) {
      // Error getting user by Firebase UID
    }
    return null;
  }

  // Refresh user from Supabase UID
  Future<void> _refreshFromSupabase(String supabaseUid) async {
    try {
      final userData = await _getUserDataBySupabaseUid(supabaseUid);
      if (userData != null) {
        setUserFromCompleteData(userData);

        // Get relationships
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
      }
    } catch (e) {
      // Error refreshing from Supabase
    }
  }

  // Helper method to get user data by Supabase UID
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
    } catch (e) {
      // Error getting user by Supabase UID
    }
    return null;
  }

  // Clear user data
  void clearUser() {
    _user = null;
    _firebaseUid = null;
    _supabaseUid = null;
    _isMigrated = false;
    notifyListeners();
  }

  // Update user data
  void updateUser(Map<String, dynamic> updates) {
    if (_user != null) {
      final updatedMap = _user!.toMap();
      updatedMap.addAll(updates);
      _user = AppUser.fromMap(updatedMap);

      // Update UIDs if provided
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
    }
  }

  // Safe UID getter - returns Firebase UID for data operations
  String? get safeUID => _firebaseUid;

  // Debug info
  void debugInfo() {
    // Debug functionality removed - use logging service instead
  }
}
