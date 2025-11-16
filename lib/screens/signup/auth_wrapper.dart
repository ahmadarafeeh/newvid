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
    _currentUser = _auth.currentUser;

    setState(() {
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCachedAuthDataInBackground();
      await _checkOnboardingInBackground();
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
    } catch (e) {
      // Cache error - continue without cache
    }
  }

  Future<void> _checkOnboardingInBackground() async {
    if (_currentUser == null) return;

    try {
      final hasCompletedOnboarding =
          await _verifyOnboardingCompletion(_currentUser!);

      if (mounted) {
        setState(() => _onboardingComplete = hasCompletedOnboarding);
      }

      await _updateAuthCache();
    } catch (e) {
      // Onboarding check failed
    }
  }

  Future<bool> _verifyOnboardingCompletion(firebase_auth.User user) async {
    try {
      final supabase = Supabase.instance;
      final response = await supabase.client
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete')
          .eq('uid', user.uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (response == null) return false;

      final dateOfBirth = response['dateOfBirth'];
      final username = response['username'];
      final gender = response['gender'];
      final onboardingComplete = response['onboardingComplete'];

      if (onboardingComplete == true) return true;

      final hasRequiredFields = dateOfBirth != null &&
          dateOfBirth.toString().isNotEmpty &&
          username != null &&
          username.toString().isNotEmpty &&
          gender != null &&
          gender.toString().isNotEmpty;

      return hasRequiredFields;
    } catch (e) {
      return false;
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
      await prefs.setString(
          'auth_cache_v3_${_currentUser?.uid}', jsonEncode(cacheData));
    } catch (e) {
      // Cache update failed - non-critical
    }
  }

  void _handleOnboardingComplete() {
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }
    _updateAuthCache();
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
}
