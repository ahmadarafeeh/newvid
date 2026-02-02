import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:Ratedly/resources/storage_methods.dart';
import 'package:Ratedly/models/user.dart';
import 'package:country_detector/country_detector.dart';
import 'package:Ratedly/services/country_service.dart';

class AuthMethods {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final SupabaseClient _supabase = Supabase.instance.client;
  final CountryService _countryService = CountryService();
  final CountryDetector _detector = CountryDetector();

  // Nonce helpers for Apple sign-in
  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ----------------------
  // Country detection helper
  // ----------------------
  Future<String?> _detectUserCountry() async {
    try {
      final countryCode = await _detector.isoCountryCode();

      if (countryCode != null &&
          countryCode.isNotEmpty &&
          countryCode != "--") {
        return countryCode;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ----------------------
  // Generic helper to normalise various supabase returns
  // ----------------------
  static dynamic _unwrapSupabaseResponse(dynamic res) {
    try {
      if (res == null) return null;
      final data = (res is Map && res.containsKey('data')) ? res['data'] : null;
      if (data != null) return data;
    } catch (_) {}
    return res;
  }

  // ----------------------
  // User relational queries (Supabase)
  // ----------------------
  Future<List<String>> getUserFollowers(String uid) async {
    try {
      final dynamic res = await _supabase
          .from('user_followers')
          .select('follower_id')
          .eq('user_id', uid);

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data is List) {
        return data
            .map<String>(
                (e) => (e['follower_id'] ?? e['followerId'])?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data is Map) {
        final id = (data['follower_id'] ?? data['followerId'])?.toString();
        return id != null ? [id] : [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getUserFollowing(String uid) async {
    try {
      final dynamic res = await _supabase
          .from('user_following')
          .select('following_id')
          .eq('user_id', uid);

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data is List) {
        return data
            .map<String>((e) =>
                (e['following_id'] ?? e['followingId'])?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data is Map) {
        final id = (data['following_id'] ?? data['followingId'])?.toString();
        return id != null ? [id] : [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // ----------------------
  // SIMPLIFIED Google user migration
  // ----------------------
  Future<String> migrateGoogleUser({
    required String firebaseUid,
    required String email,
  }) async {
    try {
      print('🚀 Starting Google OAuth migration for: $email');
      
      // Start Supabase Google OAuth - this will open browser
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'ratedly://login-callback',
      );
      
      print('✅ OAuth flow initiated successfully');
      return "oauth_initiated";
      
    } catch (e) {
      print('❌ Google OAuth migration error: $e');
      return "Google migration failed: $e";
    }
  }

  // ----------------------
  // NEW: Complete migration after OAuth success
  // ----------------------
  Future<String> completeMigrationAfterOAuth() async {
    try {
      print('🔄 Checking for migration completion...');
      
      // Wait a moment for Supabase to process the OAuth response
      await Future.delayed(const Duration(seconds: 1));
      
      // Get current Supabase session
      final session = _supabase.auth.currentSession;
      if (session == null) {
        print('❌ No Supabase session found');
        return "No Supabase session found. OAuth might have failed.";
      }
      
      // Get current Firebase user
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        print('❌ No Firebase user found');
        return "Firebase user not found. Please log in again.";
      }
      
      print('✅ Found Firebase UID: ${firebaseUser.uid}');
      print('✅ Found Supabase UID: ${session.user.id}');
      
      // Check if user is already migrated
      final List<dynamic> userCheck = await _supabase
          .from('users')
          .select('migrated, supabase_uid')
          .eq('uid', firebaseUser.uid)
          .limit(1);
      
      if (userCheck.isNotEmpty && userCheck[0]['migrated'] == true) {
        print('ℹ️ User already migrated');
        return "already_migrated";
      }
      
      // Update the user record to mark as migrated
      print('📝 Marking user as migrated...');
      await _supabase.from('users').update({
        'migrated': true,
        'supabase_uid': session.user.id,
      }).eq('uid', firebaseUser.uid);
      
      print('✅ Migration completed successfully!');
      return "success";
      
    } catch (e) {
      print('❌ Error completing migration: $e');
      return "Failed to complete migration: $e";
    }
  }

  // ----------------------
  // Check if user needs migration (call this after OAuth)
  // ----------------------
  Future<bool> checkAndCompleteMigration() async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) return false;
      
      final session = _supabase.auth.currentSession;
      if (session == null) return false;
      
      // Check if already migrated
      final List<dynamic> userCheck = await _supabase
          .from('users')
          .select('migrated')
          .eq('uid', firebaseUser.uid)
          .limit(1);
      
      if (userCheck.isEmpty) return false;
      
      if (userCheck[0]['migrated'] != true) {
        // Not migrated yet - complete it
        await _supabase.from('users').update({
          'migrated': true,
          'supabase_uid': session.user.id,
        }).eq('uid', firebaseUser.uid);
        return true;
      }
      
      return true; // Already migrated
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> getFollowRequests(String uid) async {
    try {
      final dynamic res = await _supabase
          .from('user_follow_request')
          .select('requester_id')
          .eq('user_id', uid);

      final dynamic data = _unwrapSupabaseResponse(res) ?? res;

      if (data is List) {
        return data
            .map<String>((e) =>
                (e['requester_id'] ?? e['requesterId'])?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (data is Map) {
        final id = (data['requester_id'] ?? data['requesterId'])?.toString();
        return id != null ? [id] : [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // ----------------------
  // Get user details (from Supabase, based on Firebase UID)
  // ----------------------
  Future<AppUser?> getUserDetails() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final List<dynamic> data =
          await _supabase.from('users').select().eq('uid', user.uid).limit(1);

      if (data.isEmpty) return null;
      return AppUser.fromMap(data[0]);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        // No results - user hasn't completed onboarding
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ----------------------
  // Check if user needs migration
  // ----------------------
  Future<bool> needsMigration(String uid) async {
    try {
      final List<dynamic> result = await _supabase
          .from('users')
          .select('migrated')
          .eq('uid', uid)
          .limit(1);

      if (result.isEmpty) return true;
      return result[0]['migrated'] != true;
    } catch (e) {
      return true; // Assume needs migration on error
    }
  }

  // ----------------------
  // Mark user as migrated
  // ----------------------
  Future<void> markAsMigrated(String uid, String? supabaseUid) async {
    try {
      await _supabase.from('users').update({
        'migrated': true,
        'supabase_uid': supabaseUid,
      }).eq('uid', uid);
    } catch (e) {
      rethrow;
    }
  }

  // ----------------------
  // Universal migration for ALL users (email, Google, Apple)
  // ----------------------
  Future<String> migrateUser({
    required String email,
    required String newPassword,
    required String firebaseUid,
  }) async {
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser == null) {
        return "User not logged in. Please log in first.";
      }

      if (firebaseUser.uid != firebaseUid) {
        return "UID mismatch. Please log in with the correct account.";
      }

      if (firebaseUser.email != email) {
        return "Email mismatch. Please log in with the correct account.";
      }

      final AuthResponse response = await _supabase.auth.signUp(
        email: email,
        password: newPassword,
        data: {
          'firebase_uid': firebaseUid,
        },
      );

      if (response.user == null) {
        return "Failed to create Supabase account";
      }

      await markAsMigrated(firebaseUid, response.user!.id);

      return "success";
    } on AuthException catch (e) {
      if (e.message?.contains('User already registered') ?? false) {
        try {
          final signInResponse = await _supabase.auth.signInWithPassword(
            email: email,
            password: newPassword,
          );

          if (signInResponse.user != null) {
            await markAsMigrated(firebaseUid, signInResponse.user!.id);
            return "success";
          } else {
            return "Account exists but could not sign in. Please try a different password.";
          }
        } catch (signInError) {
          return "Account exists but could not sign in. Please try a different password or contact support.";
        }
      }
      return "Migration failed: ${e.message}";
    } catch (e) {
      return "Migration failed: $e";
    }
  }

  // ----------------------
  // Email/password signup (Firebase Auth) - sets migrated = false
  // ----------------------
  Future<String> signUpUser({
    required String email,
    required String password,
  }) async {
    try {
      if (email.isEmpty || password.isEmpty) {
        return "Please fill all required fields";
      }

      final List<dynamic> existingUsers = await _supabase
          .from('users')
          .select('uid')
          .eq('email', email)
          .limit(1);

      if (existingUsers.isNotEmpty) {
        return "User with this email already exists. Please log in instead.";
      }

      try {
        final firebase_auth.UserCredential cred =
            await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (cred.user == null) {
          return "Registration failed - please try again";
        }

        await cred.user!.sendEmailVerification();

        try {
          await _supabase.from('users').upsert({
            'uid': cred.user!.uid,
            'email': cred.user!.email,
            'username': '',
            'bio': '',
            'photoUrl': 'default',
            'isPrivate': false,
            'onboardingComplete': false,
            'createdAt': DateTime.now().toIso8601String(),
            'dateOfBirth': null,
            'gender': null,
            'isVerified': false,
            'blockedUsers': jsonEncode([]),
            'country': null,
            'migrated': false,
          });
        } catch (_) {
          // ignore DB errors for now
        }

        return "success";
      } on firebase_auth.FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          return "Email already registered. Please log in instead.";
        }
        return e.message ?? "Registration failed";
      }
    } catch (err) {
      return err.toString();
    }
  }

  // ----------------------
  // Complete profile (for both email and social users)
  // ----------------------
  Future<String> completeProfile({
    required String username,
    required String bio,
    Uint8List? file,
    bool isPrivate = false,
    required DateTime dateOfBirth,
    required String gender,
  }) async {
    try {
      final firebase_auth.User? user = _auth.currentUser;
      if (user == null) return "User not authenticated";

      final isSocialUser = user.providerData
          .any((userInfo) => userInfo.providerId != 'password');

      if (!isSocialUser && !user.emailVerified) {
        return "Email not verified";
      }

      final processedUsername = username.trim();

      if (processedUsername.isEmpty) return "Username cannot be empty";
      if (processedUsername.length < 3)
        return "Username must be at least 3 characters";
      if (processedUsername.length > 20)
        return "Username cannot exceed 20 characters";
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(processedUsername)) {
        return "Username can only contain letters, numbers, and underscores";
      }

      final List<dynamic> usernameRes = await _supabase
          .from('users')
          .select('uid')
          .eq('username', processedUsername)
          .limit(1);

      if (usernameRes.isNotEmpty) {
        return "Username '$processedUsername' is already taken";
      }

      String photoUrl = 'default';

      if (file != null) {
        String fileName =
            'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
        photoUrl = await StorageMethods().uploadImageToSupabase(
          file,
          fileName,
          useUserFolder: true,
        );
      }

      final List<dynamic> currentUserData = await _supabase
          .from('users')
          .select('country')
          .eq('uid', user.uid)
          .limit(1);

      final String? existingCountry = currentUserData.isNotEmpty
          ? currentUserData[0]['country'] as String?
          : null;

      final payload = {
        'uid': user.uid,
        'email': user.email,
        'username': processedUsername,
        'bio': bio,
        'photoUrl': photoUrl,
        'isPrivate': isPrivate,
        'onboardingComplete': true,
        'createdAt': DateTime.now().toIso8601String(),
        'dateOfBirth': dateOfBirth.toIso8601String(),
        'gender': gender,
        'isVerified': true,
        'migrated': false,
      };

      try {
        await _supabase.from('users').upsert(payload);

        if (existingCountry == null) {
          await _countryService.setCountryForUser(user.uid);
        } else {
          await _countryService.setupCountryTimer(user.uid);
        }
      } catch (e) {
        return "Failed to save profile: ${e.toString()}";
      }

      return "success";
    } on Exception catch (e) {
      return e.toString();
    }
  }

  // ----------------------
  // UNIFIED LOGIN - Checks both Firebase and Supabase
  // ----------------------
  Future<String> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final List<dynamic> userRecords = await _supabase
          .from('users')
          .select('uid, migrated, "supabase_uid", "createdAt"')
          .eq('email', email);

      if (userRecords.isEmpty) {
        return await _loginWithFirebase(email, password, null);
      }

      if (userRecords.length > 1) {
        // Log the issue but continue with most recent
      }

      userRecords.sort((a, b) {
        final aTime = DateTime.parse(a['createdAt'] ?? '2000-01-01');
        final bTime = DateTime.parse(b['createdAt'] ?? '2000-01-01');
        return bTime.compareTo(aTime);
      });

      final Map<String, dynamic> userRecord = userRecords[0];
      final bool isMigrated = userRecord['migrated'] == true;
      final String firebaseUid = userRecord['uid'] as String;
      final String? supabaseUid = userRecord['supabase_uid'] as String?;

      if (isMigrated && supabaseUid != null) {
        try {
          final AuthResponse supabaseResponse =
              await _supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (supabaseResponse.user != null) {
            return await _checkOnboardingStatus(firebaseUid);
          }
        } on AuthException catch (supabaseError) {
          return await _loginWithFirebase(email, password, firebaseUid);
        }
      } else {
        return await _loginWithFirebase(email, password, firebaseUid);
      }

      return "Incorrect email or password";
    } catch (e) {
      return "An unexpected error occurred";
    }
  }

  // Helper method for Firebase login
  Future<String> _loginWithFirebase(
    String email,
    String password,
    String? expectedUid,
  ) async {
    try {
      final firebaseCred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (firebaseCred.user == null) {
        return "Login failed";
      }

      final firebaseUid = firebaseCred.user!.uid;

      if (expectedUid != null && firebaseUid != expectedUid) {
        return "Account mismatch. Please contact support.";
      }

      final needsMigration = await this.needsMigration(firebaseUid);
      if (needsMigration) {
        return "needs_migration";
      }

      return await _checkOnboardingStatus(firebaseUid);
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        return "Please enter a valid email address";
      } else if (e.code == 'wrong-password' || e.code == 'user-not-found') {
        return "Incorrect email or password";
      } else if (e.code == 'user-disabled') {
        return "Account disabled";
      } else if (e.code == 'too-many-requests') {
        return "Too many attempts. Try again later";
      } else {
        return "Incorrect email or password";
      }
    } catch (e) {
      return "An unexpected error occurred";
    }
  }

  // Check onboarding status
  Future<String> _checkOnboardingStatus(String uid) async {
    try {
      final List<dynamic> userRecords = await _supabase
          .from('users')
          .select('username, "dateOfBirth", gender, "onboardingComplete"')
          .eq('uid', uid)
          .limit(1);

      if (userRecords.isEmpty) return "onboarding_required";

      final Map<String, dynamic> data = userRecords[0];

      final hasCompletedOnboarding = data['onboardingComplete'] == true ||
          (data['username'] != null &&
              data['username'].toString().isNotEmpty &&
              data['dateOfBirth'] != null &&
              data['gender'] != null &&
              data['gender'].toString().isNotEmpty);

      return hasCompletedOnboarding ? "success" : "onboarding_required";
    } catch (e) {
      return "onboarding_required";
    }
  }

  // ----------------------
  // Helper to make firebase auth error messages readable
  // ----------------------
  String _handleFirebaseAuthError(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'Email already linked with another method';
      case 'invalid-credential':
        return 'Invalid Google credentials';
      case 'operation-not-allowed':
        return 'Google sign-in is disabled';
      case 'user-disabled':
        return 'User account disabled';
      case 'operation-not-supported':
        return 'Apple sign-in is not enabled';
      case 'user-not-found':
        return 'User not found';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }

  // ----------------------
  // Google sign-in (Firebase auth) - sets migrated = false
  // ----------------------
  Future<String> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return "cancelled";

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final firebase_auth.OAuthCredential credential =
          firebase_auth.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      final firebase_auth.UserCredential cred =
          await _auth.signInWithCredential(credential);

      final String userId = cred.user!.uid;
      final String? userEmail = cred.user!.email;

      // Check if user needs migration
      final needsMigration = await this.needsMigration(userId);

      // If user needs migration, return specific status
      if (needsMigration) {
        return "needs_migration";
      }

      final List<dynamic> res = await _supabase
          .from('users')
          .select(
              'username, "dateOfBirth", gender, "onboardingComplete", migrated')
          .eq('uid', userId)
          .limit(1);

      if (res.isEmpty) {
        try {
          await _supabase.from('users').upsert({
            'uid': userId,
            'email': userEmail,
            'username': '',
            'bio': '',
            'photoUrl': 'default',
            'isPrivate': false,
            'onboardingComplete': false,
            'createdAt': DateTime.now().toIso8601String(),
            'dateOfBirth': null,
            'gender': null,
            'isVerified': false,
            'blockedUsers': jsonEncode([]),
            'country': null,
            'migrated': false,
          });
        } catch (e) {
          // Error creating user record
        }
        return "onboarding_required";
      }

      final Map<String, dynamic> data = res[0];

      final hasCompletedOnboarding = data['onboardingComplete'] == true ||
          (data['username'] != null &&
              data['username'].toString().isNotEmpty &&
              data['dateOfBirth'] != null &&
              data['gender'] != null &&
              data['gender'].toString().isNotEmpty);

      return hasCompletedOnboarding ? "success" : "onboarding_required";
    } on firebase_auth.FirebaseAuthException catch (e) {
      return _handleFirebaseAuthError(e);
    } catch (e) {
      return "Google sign-in failed: ${e.toString()}";
    }
  }

  // ----------------------
  // Apple sign-in (Firebase auth) - sets migrated = false
  // ----------------------
  Future<String> signInWithApple() async {
    String? rawNonce;
    String? hashedNonce;
    String? identityToken;

    try {
      rawNonce = _generateRawNonce();
      hashedNonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
      );

      identityToken = appleCredential.identityToken;

      final oauthProvider = firebase_auth.OAuthProvider('apple.com');
      final oauthCredential = oauthProvider.credential(
        idToken: identityToken,
        accessToken: appleCredential.authorizationCode,
        rawNonce: rawNonce,
      );

      final firebase_auth.UserCredential userCredential =
          await _auth.signInWithCredential(oauthCredential);

      final String userId = userCredential.user!.uid;
      final String? userEmail = userCredential.user!.email;

      final List<dynamic> res = await _supabase
          .from('users')
          .select(
              'username, "dateOfBirth", gender, "onboardingComplete", migrated')
          .eq('uid', userId)
          .limit(1);

      if (res.isEmpty) {
        try {
          await _supabase.from('users').upsert({
            'uid': userId,
            'email': userEmail,
            'username': '',
            'bio': '',
            'photoUrl': 'default',
            'isPrivate': false,
            'onboardingComplete': false,
            'createdAt': DateTime.now().toIso8601String(),
            'dateOfBirth': null,
            'gender': null,
            'isVerified': false,
            'blockedUsers': jsonEncode([]),
            'country': null,
            'migrated': false,
          });
        } catch (e) {
          // Error creating user record
        }
        return "onboarding_required";
      }

      final Map<String, dynamic> data = res[0];

      if (data['migrated'] != true) {
        return "needs_migration";
      }

      final hasCompletedOnboarding = data['onboardingComplete'] == true ||
          (data['username'] != null &&
              data['username'].toString().isNotEmpty &&
              data['dateOfBirth'] != null &&
              data['gender'] != null &&
              data['gender'].toString().isNotEmpty);

      return hasCompletedOnboarding ? "success" : "onboarding_required";
    } on SignInWithAppleAuthorizationException catch (e) {
      return e.code == AuthorizationErrorCode.canceled
          ? "cancelled"
          : "Apple sign-in failed: ${e.message}";
    } on firebase_auth.FirebaseAuthException catch (e) {
      return _handleFirebaseAuthError(e);
    } catch (e, st) {
      return "Unexpected error: ${e.toString()}";
    }
  }

  // ----------------------
  // Get current user's migration status
  // ----------------------
  Future<Map<String, dynamic>> getCurrentUserMigrationStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      return {'needs_migration': false, 'reason': 'not_logged_in'};
    }

    try {
      final List<dynamic> result = await _supabase
          .from('users')
          .select('migrated, email')
          .eq('uid', user.uid)
          .limit(1);

      if (result.isEmpty) {
        return {
          'needs_migration': true,
          'reason': 'no_user_record',
          'email': user.email,
          'firebase_uid': user.uid,
        };
      }

      final isMigrated = result[0]['migrated'] == true;

      return {
        'needs_migration': !isMigrated,
        'reason': isMigrated ? 'already_migrated' : 'needs_migration',
        'email': result[0]['email'] ?? user.email,
        'firebase_uid': user.uid,
        'migrated': isMigrated,
      };
    } catch (e) {
      return {
        'needs_migration': true,
        'reason': 'error_checking_status',
        'error': e.toString(),
        'firebase_uid': user.uid,
      };
    }
  }

  // ----------------------
  // Get Google credential for reauthentication (for account deletion)
  // ----------------------
  Future<firebase_auth.OAuthCredential?> getCurrentUserCredential() async {
    try {
      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently();
      if (googleUser == null) {
        return null;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      return firebase_auth.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
    } catch (e) {
      return null;
    }
  }

  // ----------------------
  // Sign out from all services
  // ----------------------
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      // Supabase sign out error
    }
  }

  // ----------------------
  // Method to check country
  // ----------------------
  Future<void> checkCountryPeriodically() async {
    await _countryService.checkAndUpdateCountryIfNeeded();
  }

  // ----------------------
  // Backfill country for existing users
  // ----------------------
  Future<void> backfillCountryForExistingUsers() async {
    await _countryService.checkAndBackfillCountryForExistingUsers();
  }
}
