import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
import 'dart:convert'; // 🚀 ADD THIS IMPORT
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  // Simple memory cache for faster subsequent loads
  static firebase_auth.User? _cachedUser;
  static bool _cacheInitialized = false;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final _supabase = Supabase.instance.client;
  firebase_auth.User? _currentUser;
  bool _onboardingComplete = false;
  bool _isLoading = true;

  // RLS-Compatible cache keys
  static const _cacheKeyPrefix = 'auth_cache_v3_';
  String get _userCacheKey => '${_cacheKeyPrefix}${_currentUser?.uid}';

  @override
  void initState() {
    super.initState();
    _initializeInstantly();
  }

  void _initializeInstantly() {
    // INSTANT: Use cached user or Firebase's synchronous currentUser
    if (AuthWrapper._cacheInitialized) {
      _currentUser = AuthWrapper._cachedUser;
    } else {
      _currentUser = _auth.currentUser;
      AuthWrapper._cachedUser = _currentUser;
      AuthWrapper._cacheInitialized = true;
    }

    // Load cached auth data immediately
    _loadCachedAuthData();

    // Start background auth check without blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAuthInBackground();
    });
  }

  Future<void> _loadCachedAuthData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_currentUser != null) {
        final cachedData = prefs.getString(_userCacheKey);
        if (cachedData != null) {
          final data = jsonDecode(cachedData);
          final lastUpdated = data['lastUpdated'] ?? 0;
          final cacheAge = DateTime.now().millisecondsSinceEpoch - lastUpdated;

          // Use cache if less than 2 hours old
          if (cacheAge < 2 * 60 * 60 * 1000) {
            if (mounted) {
              setState(() {
                _onboardingComplete = data['onboardingComplete'] ?? false;
                _isLoading = false; // Stop loading since we have cached data
              });
            }
            return;
          }
        }
      }

      // No valid cache
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // Cache error - continue without cache
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkAuthInBackground() async {
    // Background check for auth state changes
    if (_currentUser == null) {
      try {
        final user = await _auth
            .authStateChanges()
            .timeout(const Duration(seconds: 2))
            .first;

        if (mounted && user != _currentUser) {
          setState(() {
            _currentUser = user;
            AuthWrapper._cachedUser = user;
          });
        }
      } catch (e) {
        // Timeout or error - continue with current state
      }
    }

    // Only check onboarding status if we have a user
    if (_currentUser != null && !_onboardingComplete) {
      await _checkOnboardingStatus();
    }

    // Update cache with fresh data
    if (_currentUser != null) {
      await _updateAuthCache();
    }

    // Set loading to false when background checks are complete
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkOnboardingStatus() async {
    if (_currentUser == null) return;

    try {
      // RLS-COMPLIANT: This query will respect RLS policies
      final hasCompletedOnboarding =
          await _verifyOnboardingCompletion(_currentUser!);

      if (mounted) {
        setState(() => _onboardingComplete = hasCompletedOnboarding);
      }
    } catch (e) {
      // If check fails, assume onboarding is not complete
      if (mounted) {
        setState(() => _onboardingComplete = false);
      }
    }
  }

  Future<bool> _verifyOnboardingCompletion(firebase_auth.User user) async {
    try {
      // RLS-COMPLIANT: This query respects user-specific RLS policies
      final response = await _supabase
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      // If no user data found, onboarding is not complete
      if (response == null) {
        return false;
      }

      // Check if required fields are filled (RLS ensures we only see our own data)
      final dateOfBirth = response['dateOfBirth'];
      final username = response['username'];
      final gender = response['gender'];
      final onboardingComplete = response['onboardingComplete'];

      // If onboardingComplete flag is true, trust it
      if (onboardingComplete == true) {
        return true;
      }

      // Otherwise check if required fields are filled
      final hasRequiredFields = dateOfBirth != null &&
          dateOfBirth.toString().isNotEmpty &&
          username != null &&
          username.toString().isNotEmpty &&
          gender != null &&
          gender.toString().isNotEmpty;

      return hasRequiredFields;
    } catch (e) {
      // If any error occurs, consider onboarding not complete
      return false;
    }
  }

  Future<void> _updateAuthCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'onboardingComplete': _onboardingComplete,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'userId': _currentUser?.uid,
      };
      await prefs.setString(_userCacheKey, jsonEncode(cacheData));
    } catch (e) {
      // Cache update failed - non-critical
    }
  }

  void _handleOnboardingComplete() {
    // This is called when user actually completes the onboarding flow
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }

    // Update cache in background
    if (_currentUser != null) {
      _updateAuthCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Only show main app if user exists AND completed onboarding
    if (_currentUser != null && _onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // Show onboarding if user exists but hasn't completed it
    if (_currentUser != null) {
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {
          // Handle onboarding errors
        },
      );
    }

    // No user - show get started page
    return const GetStartedPage();
  }
}
