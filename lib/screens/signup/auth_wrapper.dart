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

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final CountryService _countryService = CountryService();
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
    _initializeInstantly();
  }

  void _initializeInstantly() {
    // INSTANT: Get Firebase user immediately (synchronous)
    _currentUser = _auth.currentUser;

    // INSTANT: Try to load cached data without waiting
    _loadCachedAuthDataInstantly().then((cachedData) {
      if (cachedData != null && mounted) {
        setState(() {
          _onboardingComplete = cachedData['onboardingComplete'] ?? false;
          _usingCachedData = true;
          _isLoading = false;
        });

        // Background verification without blocking UI
        _verifyOnboardingInBackground();

        // RUN COUNTRY BACKFILL: For existing users who don't have country
        _runCountryBackfillForExistingUsers();

        // Also run regular country check
        _checkCountryInBackground();
      } else {
        // No cache available, show content immediately
        if (mounted) {
          setState(() => _isLoading = false);
        }
        _checkOnboardingInBackground();
      }
    });
  }

  // ADD THIS METHOD: Run country backfill for existing users
  Future<void> _runCountryBackfillForExistingUsers() async {
    if (_currentUser == null) return;

    try {
      // Wait a bit so it doesn't interfere with initial app load
      await Future.delayed(const Duration(seconds: 3));
      await _countryService.checkAndBackfillCountryForExistingUsers();
    } catch (e) {
      print('Country backfill failed: $e');
    }
  }

  // ADD THIS METHOD: Check country in background
  Future<void> _checkCountryInBackground() async {
    if (_currentUser == null) return;

    try {
      // Wait a bit so it doesn't interfere with initial app load
      await Future.delayed(const Duration(seconds: 5));
      await _countryService.checkAndUpdateCountryIfNeeded();
    } catch (e) {
      print('Background country check failed: $e');
    }
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

        // Use cache if less than 24 hours old
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
                response['username'].toString().isNotEmpty &&
                response['gender'] != null &&
                response['gender'].toString().isNotEmpty);

        if (hasCompletedOnboarding != _onboardingComplete && mounted) {
          setState(() => _onboardingComplete = hasCompletedOnboarding);
          _updateAuthCache(hasCompletedOnboarding);
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
                response['username'].toString().isNotEmpty &&
                response['gender'] != null &&
                response['gender'].toString().isNotEmpty);

        if (mounted) {
          setState(() => _onboardingComplete = hasCompletedOnboarding);
        }
        _updateAuthCache(hasCompletedOnboarding);

        // RUN COUNTRY BACKFILL: For existing users
        _runCountryBackfillForExistingUsers();

        // Also run regular country check
        _checkCountryInBackground();
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
    _updateAuthCache(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSimpleLoadingScreen();
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

  Widget _buildSimpleLoadingScreen() {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
