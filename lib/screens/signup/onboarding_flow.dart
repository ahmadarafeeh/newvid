import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/screens/signup/age_screen.dart';
import 'package:Ratedly/screens/signup/profile_setup_screen.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/services/debug_logger.dart'; // Keep for error logging

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

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    try {
      final firebaseUser = _auth.currentUser;
      final supabaseSession = _supabase.auth.currentSession;

      // Determine user ID
      String? userId;
      if (firebaseUser != null) {
        userId = firebaseUser.uid;
      } else if (supabaseSession != null) {
        userId = supabaseSession.user.id;
      } else {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Query user record (uid column holds the primary key for both types)
      final response = await _supabase
          .from('users')
          .select('username, dateOfBirth, gender, onboardingComplete, photoUrl')
          .eq('uid', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userData = response;
          _isLoading = false;
          if (response != null) {
            _hasRequiredFields = _hasCompletedOnboarding(response);
          }
        });
      }

      if (_hasRequiredFields) {
        widget.onComplete();
      }
    } catch (e, stack) {
      DebugLogger.logError('ONBOARDING_CHECK', e);
      if (mounted) setState(() => _isLoading = false);
      // If user record missing (PGRST116), proceed to onboarding screens
      if (e is PostgrestException && e.code == 'PGRST116') {
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

  @override
  Widget build(BuildContext context) {
    final firebaseUser = _auth.currentUser;
    final supabaseSession = _supabase.auth.currentSession;

    // If no user at all, redirect to login
    if (firebaseUser == null && supabaseSession == null) {
      return const LoginScreen();
    }

    if (_isLoading) {
      return _buildLoadingScreen();
    }

    if (_hasRequiredFields) {
      return const ResponsiveLayout(
        mobileScreenLayout: MobileScreenLayout(),
      );
    }

    // For both Firebase and Supabase users, start with age verification
    return AgeVerificationScreen(
      onComplete: _handleAgeVerificationComplete,
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
