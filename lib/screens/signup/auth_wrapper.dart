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

  // 🚀 ULTRA-FAST: No async operations in initState
  firebase_auth.User? _currentUser;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();

    // 🚀 INSTANT: Get user synchronously
    _currentUser = _auth.currentUser;

    // 🚀 BACKGROUND: Load cached data without blocking
    _loadCachedDataAsync();
  }

  // 🚀 ASYNC: Don't block UI thread
  Future<void> _loadCachedDataAsync() async {
    try {
      if (_currentUser == null) return;

      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('auth_cache_v3_${_currentUser!.uid}');

      if (cachedData != null) {
        final data = jsonDecode(cachedData);
        final cacheAge =
            DateTime.now().millisecondsSinceEpoch - (data['lastUpdated'] ?? 0);

        // Use cache if less than 4 hours old
        if (cacheAge < 4 * 60 * 60 * 1000) {
          if (mounted) {
            setState(() {
              _onboardingComplete = data['onboardingComplete'] ?? false;
            });
          }
        }
      }

      // 🚀 BACKGROUND: Verify in background without blocking
      _verifyInBackground();
    } catch (e) {
      // Silent fail - use defaults
    }
  }

  Future<void> _verifyInBackground() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // 🚀 FAST: Minimal query with timeout
      final response = await _supabase
          .from('users')
          .select('username, dateOfBirth, gender')
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));

      final hasCompleted = response != null &&
          response['username']?.toString().isNotEmpty == true &&
          response['dateOfBirth']?.toString().isNotEmpty == true &&
          response['gender']?.toString().isNotEmpty == true;

      // Update cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'auth_cache_v3_${user.uid}',
          jsonEncode({
            'onboardingComplete': hasCompleted,
            'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          }));

      if (mounted && hasCompleted != _onboardingComplete) {
        setState(() => _onboardingComplete = hasCompleted);
      }
    } catch (e) {
      // Silent background fail
    }
  }

  void _handleOnboardingComplete() {
    final user = _auth.currentUser;
    if (user != null) {
      setState(() => _onboardingComplete = true);

      // Update cache in background
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(
            'auth_cache_v3_${user.uid}',
            jsonEncode({
              'onboardingComplete': true,
              'lastUpdated': DateTime.now().millisecondsSinceEpoch,
            }));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 INSTANT ROUTING: No async checks in build method

    if (_currentUser == null) {
      return const GetStartedPage();
    }

    if (_onboardingComplete) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    return OnboardingFlow(
      onComplete: _handleOnboardingComplete,
      onError: (error) {
        // Silent error handling
      },
    );
  }

  // 🚀 GET: Lazy initialize Supabase client
  SupabaseClient get _supabase => Supabase.instance.client;
}
