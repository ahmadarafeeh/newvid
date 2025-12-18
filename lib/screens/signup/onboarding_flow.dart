import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/screens/signup/age_screen.dart';
import 'package:Ratedly/screens/signup/verify_email_screen.dart';
import 'package:Ratedly/screens/signup/profile_setup_screen.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  final Function(dynamic) onError;

  const OnboardingFlow({
    Key? key,
    required this.onComplete,
    required this.onError,
  }) : super(key: key);

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _supabase = Supabase.instance.client;
  final _auth = firebase_auth.FirebaseAuth.instance;

  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _hasRequiredFields = false;
  bool _emailVerified = true;

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      _emailVerified = user.emailVerified;

      // Check if user exists in Supabase and has completed onboarding
      final response = await _supabase
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete, photoUrl')
          .eq('uid', user.uid)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userData = response;
          _isLoading = false;

          // Check if user has all required fields filled
          if (response != null) {
            _hasRequiredFields = _hasCompletedOnboarding(response);
          }
        });
      }

      // If user has all required fields, complete onboarding immediately
      if (_hasRequiredFields) {
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      // If no user found or other error, continue with onboarding
      if (e is PostgrestException && e.code == 'PGRST116') {
        // No user found - this is normal for new social signups
        if (mounted) {
          setState(() {
            _userData = null;
            _hasRequiredFields = false;
          });
        }
      } else {
        widget.onError(e);
      }
    }
  }

  bool _hasCompletedOnboarding(Map<String, dynamic> userData) {
    return userData['onboardingComplete'] == true ||
        (userData['username'] != null &&
            userData['username']!.toString().isNotEmpty &&
            userData['dateOfBirth'] != null &&
            userData['gender'] != null &&
            userData['gender']!.toString().isNotEmpty);
  }

  void _handleAgeVerificationComplete(DateTime dateOfBirth) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileSetupScreen(
          dateOfBirth: dateOfBirth,
          onComplete: widget.onComplete,
        ),
      ),
    );
  }

  void _handleEmailVerified() {
    // After email verification, reload user status
    _checkUserStatus();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) return const LoginScreen();

    if (_isLoading) {
      return _buildLoadingScreen();
    }

    // If user has all required fields, they've completed onboarding
    if (_hasRequiredFields) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // Check if user needs email verification (only for email/password users)
    final isEmailUser =
        user.providerData.any((userInfo) => userInfo.providerId == 'password');

    if (isEmailUser && !_emailVerified) {
      return VerifyEmailScreen(
        onVerified: _handleEmailVerified,
      );
    }

    // Start with age verification for all new users
    return AgeVerificationScreen(
      onComplete:
          _handleAgeVerificationComplete, // This now matches the expected type
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }
}
