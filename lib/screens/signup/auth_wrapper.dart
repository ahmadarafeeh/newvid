import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/first_time/get_started_page.dart';
import 'package:Ratedly/screens/signup/onboarding_flow.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  // Simple memory cache for faster subsequent loads
  static User? _cachedUser;
  static bool _cacheInitialized = false;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser;
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

  Future<bool> _verifyOnboardingCompletion(User user) async {
    // TODO: Implement actual onboarding check
    // Examples:
    // - Check if user document exists in Firestore
    // - Check if required profile fields are filled
    // - Check if age verification is complete

    // For now, return false to ensure onboarding shows
    return false;
  }

  void _handleOnboardingComplete() {
    // This is called when user actually completes the onboarding flow
    if (mounted) {
      setState(() => _onboardingComplete = true);
    }

    // TODO: Mark user as completed onboarding in your database
    // await userService.markOnboardingComplete(_currentUser!.uid);
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
