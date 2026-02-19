import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/services/country_service.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/services/debug_logger.dart'; // ✅ Add this import

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

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // First check Supabase session (for new users)
    final supabaseSession = _supabase.auth.currentSession;
    if (supabaseSession != null) {
      await DebugLogger.logEvent('AUTH_INIT', 'Supabase session found, handling...');
      await _handleSupabaseSession(supabaseSession, userProvider);
      return;
    }

    // Then check Firebase (for existing users)
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await DebugLogger.logEvent('AUTH_INIT', 'Firebase user found, handling...');
      await _handleFirebaseUser(firebaseUser, userProvider);
      return;
    }

    // No user signed in
    DebugLogger.logEvent('AUTH_INIT', 'No user signed in');
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleSupabaseSession(
      Session session, UserProvider userProvider) async {
    try {
      DebugLogger.logEvent('SUPABASE_SESSION', 'Handling Supabase session for ${session.user.id}');

      // Look up user record by supabase_uid
      var userDataResponse = await _supabase
          .from('users')
          .select()
          .eq('supabase_uid', session.user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      // If no record exists, create one for this new user
      if (userDataResponse == null) {
        DebugLogger.logEvent('USER_RECORD_MISSING', 'Creating new user record');
        final newUser = {
          'uid': session.user.id, // Use Supabase UID as primary key
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

        await _supabase.from('users').insert(newUser);
        userDataResponse = newUser;
        DebugLogger.logEvent('USER_RECORD_CREATED', 'User record created');
      } else {
        DebugLogger.logEvent('USER_RECORD_FOUND', 'User record exists');
      }

      final userData = userDataResponse as Map<String, dynamic>;

      _supabaseUid = session.user.id;
      _firebaseUid = userData['uid'] as String?; // same as supabaseUid
      _userEmail = userData['email'] as String? ?? session.user.email;
      _userName = userData['username'] as String?;
      _photoUrl = userData['photoUrl'] as String?;
      _isMigrated = true;

      userProvider.initializeUser({
        'uid': _firebaseUid,
        'supabase_uid': _supabaseUid,
        'migrated': true,
        ...userData,
      });

      final hasCompletedOnboarding = await _checkOnboardingStatus(_firebaseUid!);
      DebugLogger.logEvent('ONBOARDING_STATUS_CHECK', 'hasCompletedOnboarding: $hasCompletedOnboarding');

      if (mounted) {
        setState(() {
          _onboardingComplete = hasCompletedOnboarding;
          _isLoading = false;
        });
      }

      _updateAuthCache(hasCompletedOnboarding);
      _runCountryChecks(_firebaseUid!);
    } catch (e, stack) {
      DebugLogger.logError('SUPABASE_SESSION_HANDLING', e);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFirebaseUser(
      firebase_auth.User firebaseUser, UserProvider userProvider) async {
    _firebaseUid = firebaseUser.uid;
    _userEmail = firebaseUser.email;
    _userName = firebaseUser.displayName;
    _photoUrl = firebaseUser.photoURL;
    _isMigrated = false;

    DebugLogger.logEvent('FIREBASE_USER', 'Handling Firebase user $_firebaseUid');

    final cachedData = await _loadCachedAuthDataInstantly();

    if (cachedData != null && mounted) {
      setState(() {
        _onboardingComplete = cachedData['onboardingComplete'] ?? false;
        _usingCachedData = true;
        _isLoading = false;
      });

      await _initializeUserProvider(userProvider);
      _verifyOnboardingInBackground();
    } else {
      if (mounted) setState(() => _isLoading = false);
      await _checkOnboardingFromDatabase(userProvider);
    }

    _checkMigrationInBackground();
    _runCountryChecks(_firebaseUid!);
  }

  Future<void> _initializeUserProvider(UserProvider userProvider) async {
    try {
      final userData = await _supabase
          .from('users')
          .select()
          .eq('uid', _firebaseUid!)
          .maybeSingle();

      if (userData != null) {
        userProvider.initializeUser(userData as Map<String, dynamic>);
      }
    } catch (e) {
      DebugLogger.logError('INIT_USER_PROVIDER', e);
    }
  }

  Future<Map<String, dynamic>?> _loadCachedAuthDataInstantly() async {
    try {
      if (_firebaseUid == null) return null;

      final prefs = await prefsInstance;
      final cachedData = prefs.getString('auth_cache_v4_$_firebaseUid');

      if (cachedData != null) {
        final data = jsonDecode(cachedData);
        final lastUpdated = data['lastUpdated'] ?? 0;
        final cacheAge = DateTime.now().millisecondsSinceEpoch - lastUpdated;

        if (cacheAge < 24 * 60 * 60 * 1000) {
          return {
            'onboardingComplete': data['onboardingComplete'] ?? false,
            'lastUpdated': lastUpdated,
          };
        }
      }
    } catch (e) {
      DebugLogger.logError('LOAD_CACHED_AUTH', e);
    }
    return null;
  }

  Future<void> _verifyOnboardingInBackground() async {
    if (_firebaseUid == null || !_usingCachedData) return;

    try {
      final hasCompletedOnboarding = await _checkOnboardingStatus(_firebaseUid!);

      if (hasCompletedOnboarding != _onboardingComplete && mounted) {
        setState(() => _onboardingComplete = hasCompletedOnboarding);
        _updateAuthCache(hasCompletedOnboarding);
      }
    } catch (e) {
      DebugLogger.logError('VERIFY_ONBOARDING_BG', e);
    }
  }

  Future<bool> _checkOnboardingStatus(String uid) async {
    try {
      final response = await _supabase
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', uid)
          .maybeSingle();

      if (response == null) return false;

      final data = response as Map<String, dynamic>;
      final hasCompletedOnboarding = data['onboardingComplete'] == true ||
          (data['dateOfBirth'] != null &&
              data['username'] != null &&
              data['username'].toString().isNotEmpty &&
              data['gender'] != null &&
              data['gender'].toString().isNotEmpty);

      return hasCompletedOnboarding;
    } catch (e) {
      DebugLogger.logError('CHECK_ONBOARDING_STATUS', e);
      return false;
    }
  }

  Future<void> _checkOnboardingFromDatabase(UserProvider userProvider) async {
    if (_firebaseUid == null) return;

    try {
      await _initializeUserProvider(userProvider);

      final hasCompletedOnboarding = await _checkOnboardingStatus(_firebaseUid!);

      if (mounted) {
        setState(() => _onboardingComplete = hasCompletedOnboarding);
      }
      _updateAuthCache(hasCompletedOnboarding);
    } catch (e) {
      DebugLogger.logError('CHECK_ONBOARDING_DB', e);
    }
  }

  Future<void> _checkMigrationInBackground() async {
    if (_firebaseUid == null || _checkingMigration) return;

    _checkingMigration = true;

    try {
      final migrationStatus = await _authMethods.getCurrentUserMigrationStatus();

      if (mounted) {
        setState(() {
          _needsMigration = migrationStatus['needs_migration'] == true;
        });

        if (_needsMigration) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _showMigrationScreen();
          }
        }
      }
    } catch (e) {
      DebugLogger.logError('CHECK_MIGRATION', e);
    } finally {
      _checkingMigration = false;
    }
  }

  void _runCountryChecks(String uid) {
    Future.delayed(const Duration(seconds: 3), () {
      _countryService.checkAndBackfillCountryForExistingUsers();
    });

    Future.delayed(const Duration(seconds: 5), () {
      _countryService.checkAndUpdateCountryIfNeeded();
    });
  }

  Future<void> _updateAuthCache(bool onboardingComplete) async {
    try {
      if (_firebaseUid == null) return;

      final prefs = await prefsInstance;
      final cacheData = {
        'onboardingComplete': onboardingComplete,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'userId': _firebaseUid,
      };
      await prefs.setString(
        'auth_cache_v4_$_firebaseUid',
        jsonEncode(cacheData),
      );
    } catch (e) {
      DebugLogger.logError('UPDATE_AUTH_CACHE', e);
    }
  }

  void _showMigrationScreen() {
    if (_firebaseUid == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          migrationEmail: _userEmail ?? '',
          migrationUid: _firebaseUid!,
        ),
      ),
    );
  }

  void _handleOnboardingComplete() {
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }
    _updateAuthCache(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSimpleLoadingScreen();
    }

    final isFirebaseUser = _firebaseUid != null;
    final isSupabaseUser = _supabaseUid != null;

    // If either type of user is logged in and onboarding is complete, go to home
    if ((isFirebaseUser || isSupabaseUser) && _onboardingComplete && !_needsMigration) {
      DebugLogger.logEvent('AUTH_WRAPPER', 'User logged in and onboarding complete → Home');
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // If logged in but onboarding incomplete, show onboarding flow
    if (isFirebaseUser || isSupabaseUser) {
      DebugLogger.logEvent('AUTH_WRAPPER', 'User logged in but onboarding incomplete → OnboardingFlow');
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {
          DebugLogger.logError('ONBOARDING_FLOW_ERROR', error);
        },
      );
    }

    // No user: show get started page
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
