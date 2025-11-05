import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';
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

    // Start background auth check without blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAuthInBackground();
    });
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
      // ACTUAL CHECK: Verify if user completed onboarding
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
      // If any error occurs (timeout, no record, etc.), consider onboarding not complete
      return false;
    }
  }

  void _handleOnboardingComplete() {
    // This is called when user actually completes the onboarding flow
    if (mounted) {
      setState(() => _onboardingComplete = true);
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
