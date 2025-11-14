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

  // 🚀 INSTANT: Use cached values immediately
  firebase_auth.User? _currentUser;
  bool _onboardingComplete = false;
  bool _isVerifying = false;

  // 🚀 CACHE: User-specific cache keys
  static const _cacheKeyPrefix = 'auth_cache_v2_';
  String get _userCacheKey => '${_cacheKeyPrefix}${_currentUser?.uid}';

  @override
  void initState() {
    super.initState();

    // 🚀 STEP 1: Get user synchronously (instant)
    _currentUser = _auth.currentUser;

    // 🚀 STEP 2: Load cached data immediately
    _loadCachedData();

    // 🚀 STEP 3: Verify in background (don't wait)
    _verifyInBackground();
  }

  Future<void> _loadCachedData() async {
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
              });
            }
            return;
          }
        }
      }

      // No valid cache - use defaults
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
        });
      }
    } catch (e) {
      // Cache error - use defaults
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
        });
      }
    }
  }

  Future<void> _verifyInBackground() async {
    if (_isVerifying) return;
    _isVerifying = true;

    try {
      final user = _auth.currentUser;
      if (user == null) {
        await _clearUserCache();
        return;
      }

      // 🚀 OPTIMIZED: Fast onboarding check with specific columns only
      final hasCompletedOnboarding = await _checkOnboardingStatus(user);

      // 🚀 UPDATE: Cache the fresh data
      await _updateCache(
        onboardingComplete: hasCompletedOnboarding,
        user: user,
      );

      // 🚀 UPDATE: Only refresh UI if data changed
      if (mounted && hasCompletedOnboarding != _onboardingComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _onboardingComplete = hasCompletedOnboarding;
            });
          }
        });
      }
    } catch (e) {
      // Verification failed - keep using cached data
      debugPrint('Background verification failed: $e');
    } finally {
      _isVerifying = false;
    }
  }

  // 🚀 OPTIMIZED: Fast onboarding check with minimal data
  Future<bool> _checkOnboardingStatus(firebase_auth.User user) async {
    try {
      // 🚀 ONLY SELECT NEEDED COLUMNS - Much faster query
      final response = await _supabase
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 3)); // 🚀 Shorter timeout

      if (response == null) return false;

      // 🚀 FAST: Simple null/empty checks
      final username = response['username']?.toString();
      final dateOfBirth = response['dateOfBirth']?.toString();
      final gender = response['gender']?.toString();
      final onboardingComplete = response['onboardingComplete'] == true;

      // If onboardingComplete flag is true, trust it
      if (onboardingComplete) return true;

      // Otherwise check if required fields are filled
      final hasRequiredFields = username != null &&
          username.isNotEmpty &&
          dateOfBirth != null &&
          dateOfBirth.isNotEmpty &&
          gender != null &&
          gender.isNotEmpty;

      return hasRequiredFields;
    } catch (e) {
      // On error, assume onboarding not complete
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
    // 🚀 INSTANT ROUTING: No loading delays

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
        debugPrint('Onboarding error: $error');
      },
    );
  }
}
