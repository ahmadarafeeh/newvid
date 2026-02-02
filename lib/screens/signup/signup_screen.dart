import 'dart:convert'; // Add this import at the top of the file
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/login.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/text_filed_input.dart';
import 'package:Ratedly/screens/signup/auth_wrapper.dart';
import 'package:Ratedly/screens/terms_of_service_screen.dart';
import 'package:Ratedly/screens/privacy_policy_screen.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart'; // Add this import

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  // ✅ NEW: Supabase instance
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void dispose() {
    super.dispose();
    _emailController.dispose();
  }

  // ✅ NEW: Supabase Google Sign-up (no Firebase involved)
  void signUpWithGoogleSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
            : 'ratedly://login-callback',
      );

      // If we get here, the OAuth flow has been initiated
      // The actual sign-up completion will be handled by the auth state listener
      // in your AuthWrapper
      print('✅ Google OAuth sign-up initiated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      String errorMessage = "Google sign-up failed";
      if (e is AuthException) {
        errorMessage = e.message;
      }

      if (mounted) showSnackBar(context, errorMessage);
    }
  }

  // ✅ NEW: Supabase Apple Sign-up (no Firebase involved)
  void signUpWithAppleSupabase() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb
            ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
            : 'ratedly://login-callback',
      );

      print('✅ Apple OAuth sign-up initiated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      String errorMessage = "Apple sign-up failed";
      if (e is AuthException) {
        errorMessage = e.message;
      }

      if (mounted) showSnackBar(context, errorMessage);
    }
  }

  void navigateToPasswordScreen() {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      showSnackBar(context, "Please enter your email");
      return;
    }

    if (!email.contains("@") || !email.contains(".")) {
      showSnackBar(context, "Please enter a valid email address");
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PasswordSignupScreen(email: email),
      ),
    );
  }

  bool get _shouldShowAppleButton {
    // Show Apple button on iOS and macOS, but not on web or Android
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
              TextFieldInput(
                hintText: 'Enter your email',
                textInputType: TextInputType.emailAddress,
                textEditingController: _emailController,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Inter',
                ),
                fillColor: const Color(0xFF333333),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : navigateToPasswordScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // Separator with OR
              Row(
                children: [
                  const Expanded(
                    child: Divider(
                      color: Colors.grey,
                      thickness: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Divider(
                      color: Colors.grey,
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ✅ UPDATED: Google Sign-up Button (Supabase-only)
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

              // ✅ UPDATED: Conditionally show Apple Signup Button (Supabase-only)
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
              const SizedBox(height: 16),

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

class PasswordSignupScreen extends StatefulWidget {
  final String email;

  const PasswordSignupScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<PasswordSignupScreen> createState() => _PasswordSignupScreenState();
}

class _PasswordSignupScreenState extends State<PasswordSignupScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmationController =
      TextEditingController();
  bool _isLoading = false;

  // ✅ NEW: Supabase instance
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void dispose() {
    super.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
  }

  // ✅ NEW: Supabase Email/Password Sign-up (no Firebase involved)
  void signUpWithEmailAndPasswordSupabase() async {
    if (_passwordController.text != _passwordConfirmationController.text) {
      showSnackBar(context, "Passwords don't match");
      return;
    }

    if (_passwordController.text.length < 6) {
      showSnackBar(context, "Password must be at least 6 characters");
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Sign up with Supabase Auth
      final AuthResponse response = await _supabase.auth.signUp(
        email: widget.email,
        password: _passwordController.text,
        emailRedirectTo: kIsWeb
            ? 'https://tbiemcbqjjjsgumnjlqq.supabase.co/auth/v1/callback'
            : 'ratedly://login-callback',
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (response.user == null) {
        showSnackBar(context, "Sign-up failed. Please try again.");
        return;
      }

      // 2. Create user record in the 'users' table
      try {
        await _supabase.from('users').upsert({
          'uid': response.user!.id, // Use Supabase UID as primary key
          'email': widget.email,
          'username': '',
          'bio': '',
          'photoUrl': 'default',
          'isPrivate': false,
          'onboardingComplete': false,
          'createdAt': DateTime.now().toIso8601String(),
          'dateOfBirth': null,
          'gender': null,
          'isVerified': false,
          'blockedUsers': jsonEncode([]), // ✅ Now this works with the import
          'country': null,
          'migrated': true, // Supabase users are already "migrated"
          'supabase_uid': response.user!.id,
        });

        print('✅ User record created for Supabase user: ${response.user!.id}');

        // Check if email needs verification
        if (response.session == null) {
          // Email confirmation required
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Check your email'),
                content: const Text(
                  'We\'ve sent you a confirmation email. '
                  'Please check your inbox and verify your email address.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context); // Go back to login screen
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        } else {
          // Email already verified or not required
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AuthWrapper()),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          showSnackBar(context,
              "User created, but profile setup failed. Please contact support.");
        }
        print('Error creating user record: $e');
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      String errorMessage = "Sign-up failed";
      if (e.message?.contains('User already registered') ?? false) {
        errorMessage = "Email already registered. Please log in instead.";
      } else if (e.message?.contains('invalid email') ?? false) {
        errorMessage = "Please enter a valid email address.";
      }

      if (mounted) showSnackBar(context, errorMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) showSnackBar(context, "Sign-up failed. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: const Text(
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
        elevation: 0,
      ),
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
                  color: Color(0xFFd9d9d9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Email (read-only)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Password
              TextFieldInput(
                hintText: 'Enter your password',
                textInputType: TextInputType.text,
                textEditingController: _passwordController,
                isPass: true,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Inter',
                ),
                fillColor: const Color(0xFF333333),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  'Password must be at least 6 characters',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Confirm Password
              TextFieldInput(
                hintText: 'Confirm your password',
                textInputType: TextInputType.text,
                textEditingController: _passwordConfirmationController,
                isPass: true,
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Inter',
                ),
                fillColor: const Color(0xFF333333),
              ),

              const SizedBox(height: 24),

              // Sign Up Button
              ElevatedButton(
                onPressed:
                    _isLoading ? null : signUpWithEmailAndPasswordSupabase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
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
