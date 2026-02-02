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

    final supabaseSession = _supabase.auth.currentSession;

    if (supabaseSession != null) {
      await _handleSupabaseSession(supabaseSession, userProvider);
    } else {
      final firebaseUser = _auth.currentUser;

      if (firebaseUser != null) {
        await _handleFirebaseUser(firebaseUser, userProvider);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleSupabaseSession(
      Session session, UserProvider userProvider) async {
    try {
      final userDataResponse = await _supabase
          .from('users')
          .select()
          .eq('supabase_uid', session.user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (userDataResponse != null) {
        final userData = userDataResponse as Map<String, dynamic>;

        _supabaseUid = session.user.id;
        _firebaseUid = userData['uid'] as String?;
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

        final hasCompletedOnboarding =
            await _checkOnboardingStatus(_firebaseUid!);

        if (mounted) {
          setState(() {
            _onboardingComplete = hasCompletedOnboarding;
            _isLoading = false;
          });
        }

        _updateAuthCache(hasCompletedOnboarding);
        _runCountryChecks(_firebaseUid!);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleFirebaseUser(
      firebase_auth.User firebaseUser, UserProvider userProvider) async {
    _firebaseUid = firebaseUser.uid;
    _userEmail = firebaseUser.email;
    _userName = firebaseUser.displayName;
    _photoUrl = firebaseUser.photoURL;
    _isMigrated = false;

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
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      // Error initializing UserProvider
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
      // Cache error
    }
    return null;
  }

  Future<void> _verifyOnboardingInBackground() async {
    if (_firebaseUid == null || !_usingCachedData) return;

    try {
      final hasCompletedOnboarding =
          await _checkOnboardingStatus(_firebaseUid!);

      if (hasCompletedOnboarding != _onboardingComplete && mounted) {
        setState(() => _onboardingComplete = hasCompletedOnboarding);
        _updateAuthCache(hasCompletedOnboarding);
      }
    } catch (e) {
      // Background verification failed
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
      return false;
    }
  }

  Future<void> _checkOnboardingFromDatabase(UserProvider userProvider) async {
    if (_firebaseUid == null) return;

    try {
      await _initializeUserProvider(userProvider);

      final hasCompletedOnboarding =
          await _checkOnboardingStatus(_firebaseUid!);

      if (mounted) {
        setState(() => _onboardingComplete = hasCompletedOnboarding);
      }
      _updateAuthCache(hasCompletedOnboarding);
    } catch (e) {
      // Database check failed
    }
  }

  Future<void> _checkMigrationInBackground() async {
    if (_firebaseUid == null) return;
    if (_checkingMigration) return;

    _checkingMigration = true;

    try {
      final migrationStatus =
          await _authMethods.getCurrentUserMigrationStatus();

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
      // Error checking migration
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
      // Cache update failed
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

    final isLoggedIn = _firebaseUid != null || _supabaseUid != null;
    if (isLoggedIn && _onboardingComplete && !_needsMigration) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    if (isLoggedIn) {
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {
          // Handle onboarding errors
        },
      );
    }

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
