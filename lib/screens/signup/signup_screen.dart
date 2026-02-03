import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/screens/signup/auth_wrapper.dart';
import 'package:Ratedly/screens/terms_of_service_screen.dart';
import 'package:Ratedly/screens/privacy_policy_screen.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/services/debug_logger.dart';

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
    // Log when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugLogger.logEvent('SIGNUP_SCREEN_LOADED', 'Signup screen displayed');
    });
  }

  // Enhanced Google Sign-up with detailed logging
  void signUpWithGoogleSupabase() async {
    if (!mounted) return;

    DebugLogger.logEvent(
        'GOOGLE_BUTTON_PRESSED', 'User tapped Google sign-up button');

    setState(() => _isLoading = true);

    try {
      // Log the start of OAuth
      final redirectUrl = kIsWeb
          ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
          : 'ratedly://login-callback';

      await DebugLogger.logOAuthStart('google', redirectUrl);

      // Log current session state before OAuth - FIXED: removed toIso8601String()
      final currentSession = _supabase.auth.currentSession;
      await DebugLogger.log(
        eventName: 'PRE_OAUTH_SESSION',
        message: 'Session state before OAuth',
        sessionData: {
          'has_session': currentSession != null,
          'user_id': currentSession?.user.id,
          'expires_at': currentSession?.expiresAt, // Now stores as int
        },
      );

      print('🔄 Starting Google OAuth with redirect: $redirectUrl');

      // THE CRITICAL LINE - log everything about this call
      await DebugLogger.log(
        eventName: 'CALLING_SIGNIN_WITH_OAUTH',
        message: 'Making Supabase OAuth call',
        redirectUrl: redirectUrl,
        oauthProvider: 'google',
      );

      // Attempt the OAuth sign-in
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );

      // If we get here, OAuth was initiated successfully
      await DebugLogger.logEvent(
          'OAUTH_INITIATED', 'Browser/WebView should open');
      print('✅ Google OAuth sign-up initiated - browser should open');
    } catch (e, stackTrace) {
      // Log detailed error information
      await DebugLogger.log(
        eventName: 'GOOGLE_SIGNUP_ERROR',
        message: 'Exception during Google OAuth',
        errorDetails: '''
        Error: ${e.toString()}
        Stack Trace: $stackTrace
        Runtime Type: ${e.runtimeType}
        Is AuthException: ${e is AuthException}
        ''',
      );

      if (e is AuthException) {
        await DebugLogger.log(
          eventName: 'AUTH_EXCEPTION_DETAILS',
          message: 'Supabase Auth Exception',
          errorDetails: '''
          Message: ${e.message}
          Status Code: ${e.statusCode}
          ''',
        );
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Show error to user
      String errorMessage = "Google sign-up failed";
      if (e is AuthException) {
        errorMessage = "Auth Error: ${e.message}";
      } else if (e.toString().contains('PlatformException')) {
        errorMessage = "Device error - check URL scheme configuration";
      }

      if (mounted) {
        showSnackBar(context, errorMessage);
        DebugLogger.logEvent('SHOWED_ERROR_TO_USER', errorMessage);
      }
    }
  }

  // Enhanced Apple Sign-up
  void signUpWithAppleSupabase() async {
    if (!mounted) return;

    DebugLogger.logEvent(
        'APPLE_BUTTON_PRESSED', 'User tapped Apple sign-up button');

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

      await DebugLogger.logEvent(
          'APPLE_OAUTH_INITIATED', 'Browser/WebView should open');
      print('✅ Apple OAuth sign-up initiated');
    } catch (e, stackTrace) {
      await DebugLogger.logError('APPLE_SIGNUP', e);

      if (!mounted) return;
      setState(() => _isLoading = false);

      String errorMessage = "Apple sign-up failed";
      if (e is AuthException) {
        errorMessage = e.message;
      }

      if (mounted) showSnackBar(context, errorMessage);
    }
  }

  // Also add a listener for auth state changes to log what happens
  void _setupAuthListener() {
    _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      DebugLogger.log(
        eventName: 'AUTH_STATE_CHANGE_${event.name.toUpperCase()}',
        message: 'Auth state changed: ${event.name}',
        sessionData: {
          'event': event.name,
          'has_session': session != null,
          'user_id': session?.user.id,
          'user_email': session?.user.email,
          'expires_at': session?.expiresAt, // FIXED: stores as int
        },
        supabaseUid: session?.user.id,
      );

      print('🎯 Auth State Change: ${event.name}');
      if (session != null) {
        print('✅ User ID: ${session.user.id}');
        print('📧 Email: ${session.user.email}');
      }
    });
  }

  // Getter for Apple button visibility - FIXED: moved out of build()
  bool get _shouldShowAppleButton {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    // Setup auth listener when widget builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAuthListener();
    });

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset(
                'assets/logo/22.png',
                width: 100,
                height: 100,
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                  height: 1.3,
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
                  child: Image.asset(
                    'assets/logo/google-logo.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  ),
                ),
                label: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              // Conditionally show Apple Signup Button - FIXED: using class getter
              if (_shouldShowAppleButton) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : signUpWithAppleSupabase,
                  icon: Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/logo/apple-logo.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    ),
                  ),
                  label: _isLoading
                      ? const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Terms and Privacy Policy
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontFamily: 'Inter',
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(text: 'By signing in, you agree to our '),
                      TextSpan(
                        text: 'Terms',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const TermsOfServiceScreen(),
                              ),
                            );
                          },
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PrivacyPolicyScreen(),
                              ),
                            );
                          },
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),

              // Login prompt
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                        ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontFamily: 'Inter',
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(text: 'Already have an account? '),
                      TextSpan(
                        text: 'Log in',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = _isLoading
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const LoginScreen()),
                                  );
                                },
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
