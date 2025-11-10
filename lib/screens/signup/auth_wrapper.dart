import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final _supabase = Supabase.instance.client;

  // 🎯 INSTANT STATE: We'll use cached values immediately
  firebase_auth.User? _currentUser;
  bool _onboardingComplete = false;
  bool _usingCachedData = true; // Start with cached data

  // 🎯 CACHE KEYS
  static const _cacheKeyPrefix = 'auth_cache_';
  String get _userCacheKey => '${_cacheKeyPrefix}${_currentUser?.uid}';

  @override
  void initState() {
    super.initState();
    _initializeWithCache();
  }

  Future<void> _initializeWithCache() async {
    // 🚀 STEP 1: Get current user synchronously (instant)
    _currentUser = _auth.currentUser;

    // 🚀 STEP 2: Try to load cached data (very fast)
    await _loadCachedData();

    // 🚀 STEP 3: Start background verification (don't wait for it)
    _verifyInBackground();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_currentUser != null) {
        // Try to get cached data for this specific user
        final cachedData = prefs.getString(_userCacheKey);
        if (cachedData != null) {
          final data = jsonDecode(cachedData);
          final lastUpdated = data['lastUpdated'] ?? 0;
          final cacheAge = DateTime.now().millisecondsSinceEpoch - lastUpdated;

          // Use cache if it's less than 24 hours old
          if (cacheAge < 24 * 60 * 60 * 1000) {
            if (mounted) {
              setState(() {
                _onboardingComplete = data['onboardingComplete'] ?? false;
                _usingCachedData = true;
              });
            }
            return;
          }
        }
      }

      // No valid cache - use default values
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
          _usingCachedData = false;
        });
      }
    } catch (e) {
      // Cache error - use defaults
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
          _usingCachedData = false;
        });
      }
    }
  }

  Future<void> _verifyInBackground() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        // No user - clear any existing cache
        await _clearUserCache();
        return;
      }

      // 🎯 BACKGROUND VERIFICATION: Check real onboarding status
      final hasCompletedOnboarding = await _verifyOnboardingCompletion(user);

      // 🎯 Update cache with fresh data
      await _updateCache(
        onboardingComplete: hasCompletedOnboarding,
        user: user,
      );

      // 🎯 Update UI if different from cached data
      if (mounted && hasCompletedOnboarding != _onboardingComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _onboardingComplete = hasCompletedOnboarding;
              _usingCachedData = false;
            });
          }
        });
      }
    } catch (e) {
      // Verification failed - keep using cached data
      debugPrint('Background verification failed: $e');
    }
  }

  Future<bool> _verifyOnboardingCompletion(firebase_auth.User user) async {
    try {
      // Fetch user data from Supabase
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      // If no user data found, onboarding is not complete
      if (response == null) {
        return false;
      }

      // Check if required fields are empty
      final dateOfBirth = response['dateOfBirth'];
      final username = response['username'];
      final gender = response['gender'];

      // If any of the required fields is empty, onboarding is not complete
      if (dateOfBirth == null ||
          dateOfBirth.toString().isEmpty ||
          username == null ||
          username.toString().isEmpty ||
          gender == null ||
          gender.toString().isEmpty) {
        return false;
      }

      // Also check the onboardingComplete flag if it exists
      final onboardingComplete = response['onboardingComplete'];
      if (onboardingComplete != null && onboardingComplete == true) {
        return true;
      }

      // If all required fields are filled but onboardingComplete flag is not set,
      // we should still consider onboarding complete
      return true;
    } catch (e) {
      // If any error occurs, consider onboarding not complete
      return false;
    }
  }

  Future<void> _updateCache({
    required bool onboardingComplete,
    required firebase_auth.User user,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'onboardingComplete': onboardingComplete,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'userId': user.uid,
      };
      await prefs.setString(_userCacheKey, jsonEncode(cacheData));
    } catch (e) {
      debugPrint('Cache update failed: $e');
    }
  }

  Future<void> _clearUserCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentUser != null) {
        await prefs.remove(_userCacheKey);
      }
    } catch (e) {
      debugPrint('Cache clear failed: $e');
    }
  }

  void _handleOnboardingComplete() {
    // 🚀 FIX: Use post-frame callback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _onboardingComplete = true;
        });
      }
    });

    // Update cache in background
    final user = _auth.currentUser;
    if (user != null) {
      _updateCache(onboardingComplete: true, user: user);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 INSTANT ROUTING: No loading screens based on cached data

    // Case 1: No user → Get Started page
    if (_currentUser == null) {
      return const GetStartedPage();
    }

    // Case 2: User exists AND onboarding complete → Main App
    if (_onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // Case 3: User exists but onboarding not complete → Onboarding Flow
    return OnboardingFlow(
      onComplete: _handleOnboardingComplete,
      onError: (error) {
        // Handle onboarding errors - but don't block user
        debugPrint('Onboarding error: $error');
      },
    );
  }
}
