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
import 'package:url_launcher/url_launcher.dart'; // Add this import

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  bool _isLoading = false;
  bool _isCheckingSession = false;
  
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    // Log when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugLogger.logEvent('SIGNUP_SCREEN_LOADED', 'Signup screen displayed');
      // Check initial session state
      _checkInitialSessionState();
    });
  }

  // Check initial session state
  void _checkInitialSessionState() async {
    final session = _supabase.auth.currentSession;
    await DebugLogger.log(
      eventName: 'INITIAL_SESSION_CHECK',
      message: 'App started with session check',
      sessionData: {
        'has_session': session != null,
        'user_id': session?.user.id,
        'user_email': session?.user.email,
      },
      supabaseUid: session?.user.id,
    );
  }

  // Google Sign-up with session management
  Future<void> signUpWithGoogleSupabase() async {
    if (!mounted) return;
    
    DebugLogger.logEvent('GOOGLE_BUTTON_PRESSED', 'User tapped Google sign-up button');
    
    setState(() => _isLoading = true);
    
    try {
      // 🔥 CRITICAL FIX: Check and manage existing session first
      final currentSession = _supabase.auth.currentSession;
      
      if (currentSession != null) {
        await DebugLogger.log(
          eventName: 'EXISTING_SESSION_FOUND',
          message: 'User already has active session',
          sessionData: {
            'user_id': currentSession.user.id,
            'user_email': currentSession.user.email,
            'expires_at': currentSession.expiresAt,
          },
          supabaseUid: currentSession.user.id,
        );
        
        // Show user a message about existing session
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Already Signed In'),
              content: Text(
                'You are already signed in as ${currentSession.user.email}. '
                'Would you like to sign out and create a new account?',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    setState(() => _isLoading = false);
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context); // Close dialog
                    await _handleSignOutAndRetry();
                  },
                  child: const Text('Sign Out & Continue'),
                ),
              ],
            ),
          );
        }
        return; // Exit the function
      }
      
      // If no existing session, proceed with OAuth
      await _startGoogleOAuthFlow();
      
    } catch (e, stackTrace) {
      await DebugLogger.logError('GOOGLE_SIGNUP_INITIAL', e);
      
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      if (mounted) {
        showSnackBar(context, "Error starting Google sign-up: ${e.toString()}");
      }
    }
  }

  // Handle sign out and retry OAuth
  Future<void> _handleSignOutAndRetry() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Sign out from Supabase
      await _supabase.auth.signOut();
      await DebugLogger.logEvent('MANUAL_SIGNOUT', 'User signed out before new OAuth attempt');
      
      // Wait a moment for session to clear
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Clear any cached session data
      final clearedSession = _supabase.auth.currentSession;
      await DebugLogger.log(
        eventName: 'POST_SIGNOUT_CHECK',
        message: 'Session after sign-out',
        sessionData: {
          'has_session': clearedSession != null,
          'user_id': clearedSession?.user.id,
        },
      );
      
      // Now start the OAuth flow
      await _startGoogleOAuthFlow();
      
    } catch (e, stackTrace) {
      await DebugLogger.logError('SIGNOUT_RETRY_FAILED', e);
      
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      if (mounted) {
        showSnackBar(context, "Error during sign-out: ${e.toString()}");
      }
    }
  }

  // Main OAuth flow (without session conflict)
  Future<void> _startGoogleOAuthFlow() async {
    try {
      // Log the start of OAuth
      final redirectUrl = kIsWeb 
          ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
          : 'ratedly://login-callback';
      
      await DebugLogger.logOAuthStart('google', redirectUrl);
      
      // Log current session state before OAuth (should be null)
      final preSession = _supabase.auth.currentSession;
      await DebugLogger.log(
        eventName: 'PRE_OAUTH_SESSION_CLEAN',
        message: 'Session state before OAuth (after cleanup)',
        sessionData: {
          'has_session': preSession != null,
          'user_id': preSession?.user.id,
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

      // 🔥 TRY-CATCH FOR SPECIFIC OAUTH ERROR
      try {
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectUrl,
        );

        // If we get here, OAuth was initiated successfully
        await DebugLogger.logEvent('OAUTH_INITIATED_SUCCESS', 'Browser/WebView should open');
        print('✅ Google OAuth sign-up initiated - browser should open');
        
      } catch (oauthError, oauthStackTrace) {
        // Special handling for PlatformException
        await DebugLogger.log(
          eventName: 'OAUTH_PLATFORM_EXCEPTION',
          message: 'PlatformException during OAuth call',
          errorDetails: '''
          Error: ${oauthError.toString()}
          Stack Trace: $oauthStackTrace
          Runtime Type: ${oauthError.runtimeType}
          Redirect URL: $redirectUrl
          ''',
        );
        
        // Try manual URL launch as fallback
        await _tryManualUrlLaunch(redirectUrl);
        
        // Re-throw to be caught by outer catch
        throw oauthError;
      }
      
    } catch (e, stackTrace) {
      await DebugLogger.log(
        eventName: 'GOOGLE_SIGNUP_FINAL_ERROR',
        message: 'Final error in Google sign-up',
        errorDetails: '''
        Error: ${e.toString()}
        Stack Trace: $stackTrace
        Runtime Type: ${e.runtimeType}
        ''',
      );
      
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      // Show user-friendly error message
      String errorMessage = "Google sign-up failed";
      if (e.toString().contains('PlatformException')) {
        errorMessage = "Could not open browser. Please try again or check device settings.";
      } else if (e is AuthException) {
        errorMessage = "Authentication error: ${e.message}";
      }
      
      if (mounted) {
        showSnackBar(context, errorMessage);
        DebugLogger.logEvent('SHOWED_FINAL_ERROR_TO_USER', errorMessage);
      }
      
      // Provide troubleshooting advice
      if (mounted && e.toString().contains('PlatformException')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Troubleshooting'),
              content: const Text(
                'If you continue having issues:\n\n'
                '1. Close and reopen the app\n'
                '2. Check if Safari is working on your device\n'
                '3. Try restarting your iPhone\n'
                '4. Ensure you have internet connection',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        });
      }
    }
  }

  // Fallback: Try manual URL launch
  Future<void> _tryManualUrlLaunch(String redirectUrl) async {
    try {
      // Construct the OAuth URL manually
      final authUrl = 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/authorize?provider=google&redirect_to=$redirectUrl&flow_type=pkce';
      
      await DebugLogger.logEvent('TRYING_MANUAL_URL_LAUNCH', 'URL: $authUrl');
      
      // Try to launch the URL
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        await DebugLogger.logEvent('MANUAL_URL_LAUNCH_SUCCESS', 'URL launched successfully');
      } else {
        await DebugLogger.logEvent('MANUAL_URL_CANNOT_LAUNCH', 'Cannot launch URL: $authUrl');
      }
    } catch (e) {
      await DebugLogger.logError('MANUAL_URL_LAUNCH_FAILED', e);
    }
  }

  // Enhanced Apple Sign-up with same session management
  void signUpWithAppleSupabase() async {
    if (!mounted) return;
    
    DebugLogger.logEvent('APPLE_BUTTON_PRESSED', 'User tapped Apple sign-up button');
    
    setState(() => _isLoading = true);
    
    try {
      // Check for existing session first
      final currentSession = _supabase.auth.currentSession;
      
      if (currentSession != null) {
        if (mounted) {
          showSnackBar(context, 'Please sign out first to create new account');
          setState(() => _isLoading = false);
        }
        return;
      }
      
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

  // Add a manual sign-out button for testing
  Widget _buildSignOutButton() {
    final session = _supabase.auth.currentSession;
    if (session == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: ElevatedButton(
        onPressed: _isLoading ? null : () async {
          setState(() => _isLoading = true);
          await _supabase.auth.signOut();
          setState(() => _isLoading = false);
          showSnackBar(context, 'Signed out successfully');
          DebugLogger.logEvent('TEST_SIGNOUT', 'Manual sign-out from UI');
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.withOpacity(0.8),
          foregroundColor: Colors.white,
        ),
        child: Text(
          'Sign Out ${session.user.email?.split('@').first ?? 'User'}',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
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
          'expires_at': session?.expiresAt,
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

              // Manual sign-out button (only shows if user is signed in)
              _buildSignOutButton(),

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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                    child: Image.asset(
                      'assets/logo/apple-logo.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    ),
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
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
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
                                        builder: (context) => const LoginScreen()),
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
