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

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get prefsInstance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  void initState() {
    super.initState();
    _initializeLightningFast();
  }

  void _initializeLightningFast() {
    // PHASE 1: Immediate Firebase user check
    _currentUser = _auth.currentUser;

    // IMMEDIATE: Show UI without waiting for anything (PREVENT UI BLOCKING)
    setState(() {
      _isLoading = false;
    });

    // PHASE 2: Background operations after first paint
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // TRULY NON-BLOCKING: Don't await cache loading
      unawaited(_loadCachedAuthDataInBackground().then((_) {
        // Chain background verification AFTER cache loads
        unawaited(_checkOnboardingInBackground());
      }));
    });
  }

  Future<void> _loadCachedAuthDataInBackground() async {
    try {
      final prefs = await prefsInstance;

      if (_currentUser != null) {
        final cachedData =
            prefs.getString('auth_cache_v3_${_currentUser!.uid}');

        if (cachedData != null) {
          final data = jsonDecode(cachedData);
          final lastUpdated = data['lastUpdated'] ?? 0;
          final cacheAge = DateTime.now().millisecondsSinceEpoch - lastUpdated;

          // Use cache even if old, but mark for background refresh
          if (cacheAge < 10 * 60 * 1000) {
            // 10 minutes
            if (mounted) {
              setState(() {
                _onboardingComplete = data['onboardingComplete'] ?? false;
              });
            }
          } else {
            // Use cache anyway, background will update if needed
            if (mounted) {
              setState(() {
                _onboardingComplete = data['onboardingComplete'] ?? false;
              });
            }
          }
          return;
        }
      }
    } catch (e) {
      // Cache error - continue without cache
    }
  }

  Future<void> _checkOnboardingInBackground() async {
    if (_currentUser == null) {
      return;
    }

    // TRULY BACKGROUND: Don't await, just fire and forget
    unawaited(_verifyOnboardingCompletionInBackground(_currentUser!));
  }

  // TRULY BACKGROUND: Verification that doesn't block anything
  Future<void> _verifyOnboardingCompletionInBackground(
      firebase_auth.User user) async {
    try {
      final supabase = Supabase.instance;

      final response = await supabase.client
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 3)); // Reasonable timeout

      if (response == null) {
        return; // Don't update state if no data
      }

      // KEEP ALL FIELDS but run in background
      final dateOfBirth = response['dateOfBirth'];
      final username = response['username'];
      final gender = response['gender'];
      final onboardingComplete = response['onboardingComplete'];

      // FAST PATH: If onboardingComplete is explicitly true
      if (onboardingComplete == true) {
        _updateOnboardingState(true, user.uid);
        return;
      }

      // COMPREHENSIVE FIELD CHECK (keeping all fields)
      final hasRequiredFields = dateOfBirth != null &&
          dateOfBirth.toString().isNotEmpty &&
          username != null &&
          username.toString().isNotEmpty &&
          gender != null &&
          gender.toString().isNotEmpty;

      _updateOnboardingState(hasRequiredFields, user.uid);
    } catch (e) {
      // Silent failure - don't disrupt user experience
    }
  }

  // Helper method to safely update onboarding state
  void _updateOnboardingState(bool hasCompletedOnboarding, String userId) {
    // Only update UI if state changed AND we're still on the same user
    if (mounted &&
        hasCompletedOnboarding != _onboardingComplete &&
        _currentUser?.uid == userId) {
      setState(() {
        _onboardingComplete = hasCompletedOnboarding;
      });

      // Update cache in background
      unawaited(_updateAuthCache());
    }
  }

  Future<void> _updateAuthCache() async {
    try {
      final prefs = await prefsInstance;

      final cacheData = {
        'onboardingComplete': _onboardingComplete,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'userId': _currentUser?.uid,
      };

      final cacheString = jsonEncode(cacheData);

      await prefs.setString('auth_cache_v3_${_currentUser?.uid}', cacheString);
    } catch (e) {
      // Cache update failed - non-critical
    }
  }

  void _handleOnboardingComplete() {
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }

    unawaited(_updateAuthCache());
  }

  // HELPER: Fire and forget futures
  void unawaited(Future<void> future) {
    // Ignore the future - fire and forget
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSplashScreen();
    }

    if (_currentUser != null && _onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    if (_currentUser != null) {
      return OnboardingFlow(
        onComplete: _handleOnboardingComplete,
        onError: (error) {
          // Handle onboarding errors
        },
      );
    }

    return const GetStartedPage();
  }

  // BETTER LOADING SCREEN
  Widget _buildSplashScreen() {
    return Scaffold(
      body: Container(
        color: Colors.white, // Your brand color
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Your branded logo/splash image
              Image.asset(
                'assets/splash.png',
                width: 150,
                height: 150,
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(), // Or your custom loader
            ],
          ),
        ),
      ),
    );
  }
}
