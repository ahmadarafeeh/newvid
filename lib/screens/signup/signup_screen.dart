import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/screens/terms_of_service_screen.dart';
import 'package:Ratedly/screens/privacy_policy_screen.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/services/debug_logger.dart';
import 'package:url_launcher/url_launcher.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  bool _isLoading = false;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugLogger.logEvent('SIGNUP_SCREEN_LOADED', 'Signup screen displayed');
    });
  }

  // Check for existing session before starting OAuth
  Future<void> signUpWithGoogleSupabase() async {
    if (!mounted) return;

    DebugLogger.logEvent('GOOGLE_BUTTON_PRESSED', 'User tapped Google sign-up button');

    // Check if already signed in
    final currentSession = _supabase.auth.currentSession;
    if (currentSession != null) {
      DebugLogger.logEvent('ALREADY_SIGNED_IN', 'User already has session, showing dialog');
      _showAlreadySignedInDialog();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final redirectUrl = kIsWeb
          ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
          : 'ratedly://login-callback';

      await DebugLogger.logOAuthStart('google', redirectUrl);

      // Log session state before OAuth
      await DebugLogger.log(
        eventName: 'PRE_OAUTH_SESSION',
        message: 'Session state before OAuth',
        sessionData: {
          'has_session': false,
          'user_id': null,
          'expires_at': null,
        },
      );

      print('🔄 Starting Google OAuth with redirect: $redirectUrl');

      // Attempt OAuth sign-in
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );

      // OAuth initiated successfully – reset loading and log
      await DebugLogger.logEvent('OAUTH_INITIATED', 'Browser/WebView should open');
      print('✅ Google OAuth sign-up initiated - browser should open');

      // 🔥 CRITICAL: Reset loading state immediately after successful OAuth call
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      // Log error and reset loading
      await DebugLogger.log(
        eventName: 'GOOGLE_SIGNUP_ERROR',
        message: 'Exception during Google OAuth',
        errorDetails: '''
        Error: ${e.toString()}
        Stack Trace: $stackTrace
        Runtime Type: ${e.runtimeType}
        ''',
      );

      if (mounted) {
        setState(() => _isLoading = false);
        String errorMessage = "Google sign-up failed. Please try again.";
        showSnackBar(context, errorMessage);
        DebugLogger.logEvent('SHOWED_ERROR_TO_USER', errorMessage);
      }
    }
  }

  void _showAlreadySignedInDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text('Already Signed In', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You are already signed in. Please sign out first if you want to create a new account.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _supabase.auth.signOut();
              DebugLogger.logEvent('SIGNED_OUT_FROM_DIALOG', 'User signed out');
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void signUpWithAppleSupabase() async {
    if (!mounted) return;

    DebugLogger.logEvent('APPLE_BUTTON_PRESSED', 'User tapped Apple sign-up button');

    // Check if already signed in
    final currentSession = _supabase.auth.currentSession;
    if (currentSession != null) {
      _showAlreadySignedInDialog();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final redirectUrl = kIsWeb
          ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
          : 'ratedly://login-callback';

      await DebugLogger.logOAuthStart('apple', redirectUrl);

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: redirectUrl,
      );

      await DebugLogger.logEvent('APPLE_OAUTH_INITIATED', 'Browser/WebView should open');
      print('✅ Apple OAuth sign-up initiated');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      await DebugLogger.logError('APPLE_SIGNUP', e);
      if (mounted) {
        setState(() => _isLoading = false);
        showSnackBar(context, "Apple sign-up failed");
      }
    }
  }

  bool get _shouldShowAppleButton {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/logo/22.png', width: 100, height: 100),
              const SizedBox(height: 8),
              const Text(
                'Create your account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Google Sign-up Button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : signUpWithGoogleSupabase,
                icon: Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  child: Image.asset('assets/logo/google-logo.png', width: 24, height: 24),
                ),
                label: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Sign up with Google',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),

              if (_shouldShowAppleButton) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : signUpWithAppleSupabase,
                  icon: Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    child: Image.asset('assets/logo/apple-logo.png', width: 24, height: 24, color: Colors.white),
                  ),
                  label: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Sign up with Apple',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF333333),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],

              const SizedBox(height: 40),
              // Terms and Privacy Policy (unchanged)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(color: Colors.grey[400], fontFamily: 'Inter', fontSize: 14),
                    children: [
                      const TextSpan(text: 'By signing in, you agree to our '),
                      TextSpan(
                        text: 'Terms',
                        style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),

              // Login prompt
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: Colors.grey[400], fontFamily: 'Inter', fontSize: 14),
                    children: [
                      const TextSpan(text: 'Already have an account? '),
                      TextSpan(
                        text: 'Log in',
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _isLoading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      ),
                    ],
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
