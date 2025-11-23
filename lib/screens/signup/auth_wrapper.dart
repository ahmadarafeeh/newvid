import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  firebase_auth.User? _currentUser;
  bool _onboardingComplete = false;
  bool _isLoading = true;
  bool _usingCachedData = false;

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get prefsInstance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  void initState() {
    super.initState();
    _initializeUltraFast();
  }

  void _initializeUltraFast() {
    // PHASE 1: Immediate Firebase user check (INSTANT)
    _currentUser = _auth.currentUser;

    // IMMEDIATE: Try to load cached auth data (NON-BLOCKING)
    unawaited(_loadCachedAuthDataInstantly().then((cachedData) {
      if (cachedData != null && mounted) {
        setState(() {
          _onboardingComplete = cachedData['onboardingComplete'] ?? false;
          _usingCachedData = true;
          _isLoading = false;
        });

        // Background verification without blocking UI
        unawaited(_verifyOnboardingInBackground());
      } else {
        // No cache available, proceed with normal flow
        if (mounted) {
          setState(() => _isLoading = false);
        }
        unawaited(_checkOnboardingInBackground());
      }
    }));

    // FALLBACK: If cache loading takes too long, show UI anyway after 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_isLoading && mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  Future<Map<String, dynamic>?> _loadCachedAuthDataInstantly() async {
    try {
      if (_currentUser == null) return null;

      final prefs = await prefsInstance;
      final cachedData = prefs.getString('auth_cache_v4_${_currentUser!.uid}');

      if (cachedData != null) {
        final data = jsonDecode(cachedData);
        final lastUpdated = data['lastUpdated'] ?? 0;
        final cacheAge = DateTime.now().millisecondsSinceEpoch - lastUpdated;

        // Use cache if less than 1 hour old
        // 24 hours
        if (cacheAge < 24 * 60 * 60 * 1000) {
          return {
            'onboardingComplete': data['onboardingComplete'] ?? false,
            'lastUpdated': lastUpdated,
          };
        }
      }
    } catch (e) {
      // Cache error - proceed without cache
    }
    return null;
  }

  Future<void> _verifyOnboardingInBackground() async {
    if (_currentUser == null || !_usingCachedData) return;

    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', _currentUser!.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (response != null) {
        final hasCompletedOnboarding = response['onboardingComplete'] == true ||
            (response['dateOfBirth'] != null &&
                response['username'] != null &&
                response['gender'] != null);

        if (hasCompletedOnboarding != _onboardingComplete && mounted) {
          setState(() => _onboardingComplete = hasCompletedOnboarding);
          unawaited(_updateAuthCache(hasCompletedOnboarding));
        }
      }
    } catch (e) {
      // Background verification failed - keep using cached data
    }
  }

  Future<void> _checkOnboardingInBackground() async {
    if (_currentUser == null) return;

    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', _currentUser!.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (response != null) {
        final hasCompletedOnboarding = response['onboardingComplete'] == true ||
            (response['dateOfBirth'] != null &&
                response['username'] != null &&
                response['gender'] != null);

        if (mounted) {
          setState(() => _onboardingComplete = hasCompletedOnboarding);
        }
        unawaited(_updateAuthCache(hasCompletedOnboarding));
      }
    } catch (e) {
      // Background check failed - user will see onboarding if needed
    }
  }

  Future<void> _updateAuthCache(bool onboardingComplete) async {
    try {
      final prefs = await prefsInstance;
      final cacheData = {
        'onboardingComplete': onboardingComplete,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'userId': _currentUser?.uid,
      };
      await prefs.setString(
        'auth_cache_v4_${_currentUser?.uid}',
        jsonEncode(cacheData),
      );
    } catch (e) {
      // Cache update failed - non-critical
    }
  }

  void _handleOnboardingComplete() {
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }
    unawaited(_updateAuthCache(true));
  }

  // HELPER: Fire and forget futures
  void unawaited(Future<void> future) {
    // Ignore the future - fire and forget
  }

  @override
  Widget build(BuildContext context) {
    // ULTRA-FAST DECISION TREE
    if (_isLoading) {
      return _buildUltraFastSplashScreen();
    }

    // USER IS LOGGED IN AND ONBOARDING COMPLETE - GO STRAIGHT TO FEED
    if (_currentUser != null && _onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // USER IS LOGGED IN BUT NEEDS ONBOARDING
    if (_currentUser != null) {
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {
          // Handle onboarding errors
        },
      );
    }

    // NO USER - GO TO GET STARTED
    return const GetStartedPage();
  }

  // ULTRA-FAST SPLASH SCREEN (MAX 500ms)
  Widget _buildUltraFastSplashScreen() {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Your branded logo/splash image
              Image.asset(
                'assets/splash.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 16),
              // Minimal progress indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
