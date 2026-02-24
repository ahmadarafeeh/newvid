import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
import 'package:Ratedly/services/country_service.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/services/debug_logger.dart';

// Helper to log to login_logs table
Future<void> _logLoginEvent({
  required String eventType,
  String? firebaseUid,
  String? supabaseUid,
  String? email,
  bool? hasFirebaseSession,
  bool? hasSupabaseSession,
  bool? existingRecordFound,
  String? recordSource,
  bool? onboardingComplete,
  bool? needsMigration,
  String? errorDetails,
  String? stackTrace,
  String? navigationTarget,
  Map<String, dynamic>? additionalData,
}) async {
  try {
    await Supabase.instance.client.from('login_logs').insert({
      'event_type': eventType,
      'firebase_uid': firebaseUid,
      'supabase_uid': supabaseUid,
      'email': email,
      'has_firebase_session': hasFirebaseSession,
      'has_supabase_session': hasSupabaseSession,
      'existing_record_found': existingRecordFound,
      'record_source': recordSource,
      'onboarding_complete': onboardingComplete,
      'needs_migration': needsMigration,
      'error_details': errorDetails,
      'stack_trace': stackTrace,
      'navigation_target': navigationTarget,
      'additional_data': additionalData,
    });
  } catch (e) {
    print('Failed to log to login_logs: $e');
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final CountryService _countryService = CountryService();
  final AuthMethods _authMethods = AuthMethods();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _usingCachedData = false;
  bool _needsMigration = false;
  bool _checkingMigration = false;
  bool _isInitializing = false; // Guard to prevent concurrent init

  String? _firebaseUid;
  String? _supabaseUid;
  String? _userEmail;
  String? _userName;
  String? _photoUrl;
  bool _isMigrated = false;
  bool _onboardingComplete = false;

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get prefsInstance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _initializeAuth();

    // Listen for auth state changes (e.g., after OAuth redirect)
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed) {
        _logLoginEvent(
          eventType: 'AUTH_LISTENER_TRIGGERED',
          firebaseUid: _auth.currentUser?.uid,
          supabaseUid: data.session?.user.id,
          email: data.session?.user.email,
          hasFirebaseSession: _auth.currentUser != null,
          hasSupabaseSession: data.session != null,
        );
        if (!_isInitializing) {
          _isInitializing = true;
          _initializeAuth().then((_) => _isInitializing = false);
        }
      } else if (data.event == AuthChangeEvent.signedOut && mounted) {
        _logLoginEvent(eventType: 'USER_SIGNED_OUT');
        setState(() {
          _firebaseUid = null;
          _supabaseUid = null;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _initializeAuth() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    final hasFirebase = _auth.currentUser != null;
    final hasSupabase = _supabase.auth.currentSession != null;

    await _logLoginEvent(
      eventType: 'AUTH_INIT_START',
      firebaseUid: _auth.currentUser?.uid,
      supabaseUid: _supabase.auth.currentSession?.user.id,
      email: _auth.currentUser?.email ?? _supabase.auth.currentSession?.user.email,
      hasFirebaseSession: hasFirebase,
      hasSupabaseSession: hasSupabase,
    );

    // First check Supabase session (for all users)
    final supabaseSession = _supabase.auth.currentSession;
    if (supabaseSession != null) {
      await DebugLogger.logEvent('AUTH_INIT', 'Supabase session found, handling...');
      await _handleSupabaseSession(supabaseSession, userProvider);
      return;
    }

    // Then check Firebase (for existing users not yet migrated)
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await DebugLogger.logEvent('AUTH_INIT', 'Firebase user found, handling...');
      await _handleFirebaseUser(firebaseUser, userProvider);
      return;
    }

    // No user signed in
    DebugLogger.logEvent('AUTH_INIT', 'No user signed in');
    await _logLoginEvent(eventType: 'AUTH_INIT_NO_USER');
    if (mounted) setState(() => _isLoading = false);
  }

  // 🛠️ CORRECTED: Prioritize Firebase UID and email lookups for migration
  Future<void> _handleSupabaseSession(
      Session session, UserProvider userProvider) async {
    String? recordSource;
    bool found = false;
    Map<String, dynamic>? userData;
    final firebaseUser = _auth.currentUser; // Capture current Firebase user

    try {
      DebugLogger.logEvent('SUPABASE_SESSION',
          'Handling Supabase session for ${session.user.id}');

      // --- STEP 1: If Firebase user exists, try to find record by Firebase UID ---
      if (firebaseUser != null) {
        userData = await _supabase
            .from('users')
            .select()
            .eq('uid', firebaseUser.uid)
            .maybeSingle();

        if (userData != null) {
          found = true;
          recordSource = 'firebase_uid';
          await _logLoginEvent(
            eventType: 'USER_RECORD_FOUND_BY_FIREBASE_UID',
            firebaseUid: firebaseUser.uid,
            supabaseUid: session.user.id,
            email: session.user.email,
            existingRecordFound: true,
            recordSource: recordSource,
          );
          DebugLogger.logEvent('USER_RECORD_FOUND',
              'Found existing Firebase user record, updating with supabase_uid');

          // Update the existing record with supabase_uid and mark migrated
          await _supabase.from('users').update({
            'supabase_uid': session.user.id,
            'migrated': true,
          }).eq('uid', firebaseUser.uid);

          // Re-fetch the updated record
          userData = await _supabase
              .from('users')
              .select()
              .eq('uid', firebaseUser.uid)
              .maybeSingle();
        }
      }

      // --- STEP 2: If not found, try by email (migration without current Firebase session) ---
      if (!found && session.user.email != null) {
        final userByEmail = await _supabase
            .from('users')
            .select()
            .eq('email', session.user.email!)
            .eq('migrated', false) // Only unmatched users
            .maybeSingle();

        if (userByEmail != null) {
          found = true;
          recordSource = 'email_migration';
          userData = userByEmail;
          await _logLoginEvent(
            eventType: 'USER_RECORD_FOUND_BY_EMAIL',
            supabaseUid: session.user.id,
            email: session.user.email,
            existingRecordFound: true,
            recordSource: recordSource,
          );
          DebugLogger.logEvent('USER_RECORD_FOUND',
              'Found existing user by email, updating with supabase_uid');

          // Update the existing record with supabase_uid and mark migrated
          await _supabase.from('users').update({
            'supabase_uid': session.user.id,
            'migrated': true,
          }).eq('uid', userData!['uid']);

          // Re-fetch the updated record
          userData = await _supabase
              .from('users')
              .select()
              .eq('uid', userData!['uid'])
              .maybeSingle();
        }
      }

      // --- STEP 3: Try to find by supabase_uid (normal case after migration) ---
      if (!found) {
        userData = await _supabase
            .from('users')
            .select()
            .eq('supabase_uid', session.user.id)
            .maybeSingle();

        if (userData != null) {
          found = true;
          recordSource = 'supabase_uid';
          await _logLoginEvent(
            eventType: 'USER_RECORD_FOUND_BY_SUPABASE_UID',
            supabaseUid: session.user.id,
            email: session.user.email,
            existingRecordFound: true,
            recordSource: recordSource,
          );
          DebugLogger.logEvent('USER_RECORD_FOUND', 'User record exists by supabase_uid');
        }
      }

      // --- STEP 4: If still no record, create a new one ---
      if (!found) {
        recordSource = 'none';
        await _logLoginEvent(
          eventType: 'USER_RECORD_MISSING_CREATING_NEW',
          supabaseUid: session.user.id,
          email: session.user.email,
          existingRecordFound: false,
          recordSource: recordSource,
        );
        DebugLogger.logEvent('USER_RECORD_MISSING', 'Creating new user record');
        final newUser = {
          'uid': session.user.id, // Primary key = Supabase UID
          'email': session.user.email,
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
          'migrated': true,
          'supabase_uid': session.user.id,
        };

        await _supabase.from('users').upsert(newUser, onConflict: 'uid');
        userData = newUser;
        DebugLogger.logEvent('USER_RECORD_CREATED', 'User record created');
      }

      // Populate state
      _supabaseUid = session.user.id;
      _firebaseUid = userData!['uid'] as String?;
      _userEmail = userData['email'] as String? ?? session.user.email;
      _userName = userData['username'] as String?;
      _photoUrl = userData['photoUrl'] as String?;
      _isMigrated = userData['migrated'] == true;

      userProvider.initializeUser({
        'uid': _firebaseUid,
        'supabase_uid': _supabaseUid,
        'migrated': _isMigrated,
        ...userData,
      });

      final hasCompletedOnboarding = await _checkOnboardingStatus(_firebaseUid!);
      _onboardingComplete = hasCompletedOnboarding;

      await _logLoginEvent(
        eventType: 'SUPABASE_SESSION_HANDLED',
        firebaseUid: _firebaseUid,
        supabaseUid: _supabaseUid,
        email: _userEmail,
        onboardingComplete: _onboardingComplete,
        recordSource: recordSource,
      );
      DebugLogger.logEvent('ONBOARDING_STATUS_CHECK',
          'hasCompletedOnboarding: $hasCompletedOnboarding');

      if (mounted) {
        setState(() {
          _onboardingComplete = hasCompletedOnboarding;
          _isLoading = false;
        });
      }

      _updateAuthCache(hasCompletedOnboarding);
      _runCountryChecks(_firebaseUid!);
    } catch (e, stack) {
      await _logLoginEvent(
        eventType: 'ERROR_SUPABASE_SESSION_HANDLING',
        errorDetails: e.toString(),
        stackTrace: stack.toString(),
      );
      DebugLogger.logError('SUPABASE_SESSION_HANDLING', e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // The rest of the methods remain exactly as in the original file
  Future<void> _handleFirebaseUser(
      firebase_auth.User firebaseUser, UserProvider userProvider) async {
    // ... (unchanged)
  }

  Future<void> _initializeUserProvider(UserProvider userProvider) async {
    // ... (unchanged)
  }

  Future<Map<String, dynamic>?> _loadCachedAuthDataInstantly() async {
    // ... (unchanged)
  }

  Future<void> _verifyOnboardingInBackground() async {
    // ... (unchanged)
  }

  Future<bool> _checkOnboardingStatus(String uid) async {
    // ... (unchanged)
  }

  Future<void> _checkOnboardingFromDatabase(UserProvider userProvider) async {
    // ... (unchanged)
  }

  Future<void> _checkMigrationInBackground() async {
    // ... (unchanged)
  }

  void _runCountryChecks(String uid) {
    // ... (unchanged)
  }

  Future<void> _updateAuthCache(bool onboardingComplete) async {
    // ... (unchanged)
  }

  void _showMigrationScreen() {
    // ... (unchanged)
  }

  void _handleOnboardingComplete() {
    // ... (unchanged)
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSimpleLoadingScreen();
    }

    final isFirebaseUser = _firebaseUid != null;
    final isSupabaseUser = _supabaseUid != null;

    // Determine navigation target
    String? target;
    if ((isFirebaseUser || isSupabaseUser) &&
        _onboardingComplete &&
        !_needsMigration) {
      target = 'Home';
    } else if (isFirebaseUser || isSupabaseUser) {
      target = 'OnboardingFlow';
    } else {
      target = 'GetStartedPage';
    }

    // Log navigation decision (after build to ensure context exists)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logLoginEvent(
        eventType: 'NAVIGATION_DECISION',
        firebaseUid: _firebaseUid,
        supabaseUid: _supabaseUid,
        email: _userEmail,
        onboardingComplete: _onboardingComplete,
        needsMigration: _needsMigration,
        navigationTarget: target,
      );
    });

    // Log with DebugLogger as well
    if ((isFirebaseUser || isSupabaseUser) &&
        _onboardingComplete &&
        !_needsMigration) {
      DebugLogger.logEvent(
          'AUTH_WRAPPER', 'User logged in and onboarding complete → Home');
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    if (isFirebaseUser || isSupabaseUser) {
      DebugLogger.logEvent('AUTH_WRAPPER',
          'User logged in but onboarding incomplete → OnboardingFlow');
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {
          DebugLogger.logError('ONBOARDING_FLOW_ERROR', error);
        },
      );
    }

    DebugLogger.logEvent('AUTH_WRAPPER', 'No user → GetStartedPage');
    return const GetStartedPage();
  }

  Widget _buildSimpleLoadingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo/22.png',
              width: 100,
              height: 100,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
