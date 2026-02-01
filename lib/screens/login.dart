import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/resources/auth_methods.dart';
import 'package:Ratedly/screens/signup/signup_screen.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:Ratedly/widgets/text_filed_input.dart';
import 'package:Ratedly/responsive/mobile_screen_layout.dart';
import 'package:Ratedly/responsive/responsive_layout.dart';
import 'package:Ratedly/screens/terms_of_service_screen.dart';
import 'package:Ratedly/screens/privacy_policy_screen.dart';
import 'package:Ratedly/screens/signup/auth_wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:Ratedly/providers/user_provider.dart';

class LoginScreen extends StatefulWidget {
  final String? migrationEmail;
  final String? migrationUid;

  const LoginScreen({
    Key? key,
    this.migrationEmail,
    this.migrationUid,
  }) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _showMigrationForm = false;
  String _errorMessage = '';
  String? _migrationEmail;
  String? _migrationUid;
  bool _migrationCompleted = false;
  // Track authentication provider ('email', 'google', or 'apple')
  String? _migrationProvider;

  @override
  void initState() {
    super.initState();

    // Check if we were redirected here for migration
    if (widget.migrationEmail != null && widget.migrationUid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _showMigrationForm = true;
            _migrationEmail = widget.migrationEmail;
            _migrationUid = widget.migrationUid;
            _emailController.text = widget.migrationEmail!;
            // Default to email provider when redirected
            _migrationProvider = 'email';
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Safe method to show snackbars
  void _showSnackBarSafe(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> loginUser() async {
    if (!mounted) return;

    // If we're in migration mode, handle migration first
    if (_showMigrationForm) {
      await _handleMigration();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final String res = await AuthMethods().loginUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (res == 'success' || res == "onboarding_required") {
        // Get user data using the existing getUserDetails method
        final user = await AuthMethods().getUserDetails();
        if (user != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          userProvider.setUser(user);
        }

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const ResponsiveLayout(
              mobileScreenLayout: MobileScreenLayout(),
            ),
          ),
          (route) => false,
        );
      } else if (res == "needs_migration") {
        // Show migration form
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser == null) {
          if (!mounted) return;
          _showSnackBarSafe('Please log in first', isError: true);
          return;
        }

        if (!mounted) return;
        setState(() {
          _showMigrationForm = true;
          _migrationEmail = _emailController.text.trim();
          _migrationUid = firebaseUser.uid;
          // Check if user is email/password or social
          final isSocialUser = firebaseUser.providerData
              .any((userInfo) => userInfo.providerId != 'password');
          _migrationProvider = isSocialUser ? 'google' : 'email';
        });
      } else {
        if (!mounted) return;
        _showSnackBarSafe(res, isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBarSafe('An error occurred: $e', isError: true);
      }
    }
  }

  Future<void> _handleMigration() async {
    // Only handle email/password migration here
    if (_migrationProvider != 'email') {
      return;
    }

    // Validate inputs
    if (_newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Please enter password');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    if (_newPasswordController.text.length < 6) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await AuthMethods().migrateUser(
        email: _migrationEmail!,
        newPassword: _newPasswordController.text,
        firebaseUid: _migrationUid!,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _migrationCompleted = true;
      });

      if (result == 'success') {
        // Get updated user data after migration using getUserDetails
        final updatedUser = await AuthMethods().getUserDetails();
        if (updatedUser != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          userProvider.setUser(updatedUser);
        }

        // Show success message
        _showSnackBarSafe('Account updated successfully!');

        // Clear migration form
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        // Wait a moment for user to see success message
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        // Show message explaining they should use the new password
        _showSnackBarSafe('Please log in with your new password');

        // Reset the form and go back to login
        setState(() {
          _showMigrationForm = false;
          _migrationEmail = null;
          _migrationUid = null;
          _migrationProvider = null;
          _errorMessage = '';
        });

        // Clear all controllers
        _emailController.clear();
        _passwordController.clear();
      } else {
        // Show detailed error message
        String errorMsg = result;
        if (result.contains('accessToken option')) {
          errorMsg =
              'Configuration error. Please contact support. Error: $result';
        }
        if (mounted) {
          setState(() => _errorMessage = errorMsg);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An error occurred: $e';
        });
      }
    }
  }

  Future<void> _migrateWithGoogle() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Use the migrateGoogleUser method
      final result = await AuthMethods().migrateGoogleUser(
        firebaseUid: _migrationUid!,
        email: _migrationEmail!,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result == "oauth_initiated") {
        // OAuth flow started - show waiting message
        _showSnackBarSafe('Please complete Google sign-in in the browser...');

        // The OAuth completion will be handled by the deep link handler
      } else if (result == "needs_google_reauth") {
        // User needs to re-authenticate
        _showSnackBarSafe('Please re-authenticate with Google');
        await loginWithGoogle();
      } else {
        setState(() => _errorMessage = result);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Google migration failed: $e');
    }
  }

  void _cancelMigration() {
    if (!mounted) return;

    setState(() {
      _showMigrationForm = false;
      _migrationEmail = null;
      _migrationUid = null;
      _migrationProvider = null;
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _errorMessage = '';
    });

    // Go back to normal login
    _emailController.clear();
    _passwordController.clear();
  }

  Future<void> loginWithGoogle() async {
    if (_showMigrationForm) {
      if (!mounted) return;
      _showSnackBarSafe('Please complete migration first', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Note: Based on your AuthMethods class, this returns a String
      final String res = await AuthMethods().signInWithGoogle();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res == "success" || res == "onboarding_required") {
        // Get user data and set UserProvider
        final user = await AuthMethods().getUserDetails();
        if (user != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          userProvider.setUser(user);
        }

        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
          (route) => false,
        );
      } else if (res == "needs_migration") {
        // Show migration form for Google user
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser != null && firebaseUser.email != null) {
          // Check if this is a Google user
          final isGoogleUser = firebaseUser.providerData
              .any((userInfo) => userInfo.providerId == 'google.com');

          if (mounted) {
            setState(() {
              _showMigrationForm = true;
              _migrationEmail = firebaseUser.email!;
              _migrationUid = firebaseUser.uid;
              _emailController.text = firebaseUser.email!;
              // Set the correct provider
              _migrationProvider = isGoogleUser ? 'google' : 'email';
            });
          }
        }
      } else if (res == "cancelled") {
        if (!mounted) return;
        _showSnackBarSafe('Google sign-in cancelled', isError: true);
      } else {
        if (!mounted) return;
        _showSnackBarSafe(res, isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google sign-in failed: $e';
        });
      }
    }
  }

  Future<void> loginWithApple() async {
    if (_showMigrationForm) {
      if (!mounted) return;
      _showSnackBarSafe('Please complete migration first', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Note: Based on your AuthMethods class, this returns a String
      final String res = await AuthMethods().signInWithApple();

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res == "success" || res == "onboarding_required") {
        // Get user data and set UserProvider
        final user = await AuthMethods().getUserDetails();
        if (user != null) {
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          userProvider.setUser(user);
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthWrapper()),
        );
      } else if (res == "needs_migration") {
        // Show migration form for Apple user
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser != null && firebaseUser.email != null) {
          // Check if this is an Apple user
          final isAppleUser = firebaseUser.providerData
              .any((userInfo) => userInfo.providerId == 'apple.com');

          if (mounted) {
            setState(() {
              _showMigrationForm = true;
              _migrationEmail = firebaseUser.email!;
              _migrationUid = firebaseUser.uid;
              _emailController.text = firebaseUser.email!;
              // Set the correct provider
              _migrationProvider = isAppleUser ? 'apple' : 'email';
            });
          }
        }
      } else if (res == "cancelled") {
        if (!mounted) return;
        _showSnackBarSafe('Apple sign-in cancelled', isError: true);
      } else {
        if (!mounted) return;
        _showSnackBarSafe(res, isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Apple sign-in failed: $e';
        });
      }
    }
  }

  // Build password migration form
  Widget _buildPasswordMigrationForm() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          'We\'re upgrading our security system. Please set a new password for your account to continue.',
          style: TextStyle(
            color: Colors.grey[400],
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Email: $_migrationEmail',
          style: TextStyle(
            color: Colors.grey[600],
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextFieldInput(
          hintText: 'New Password',
          textInputType: TextInputType.text,
          textEditingController: _newPasswordController,
          isPass: true,
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontFamily: 'Inter',
          ),
          fillColor: const Color(0xFF333333),
        ),
        const SizedBox(height: 16),
        TextFieldInput(
          hintText: 'Confirm New Password',
          textInputType: TextInputType.text,
          textEditingController: _confirmPasswordController,
          isPass: true,
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontFamily: 'Inter',
          ),
          fillColor: const Color(0xFF333333),
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _cancelMigration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF444444),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleMigration,
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
                        'Update Account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Build Google migration form
  Widget _buildGoogleMigrationForm() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          'We\'re upgrading our security system. Please re-authenticate with Google to migrate your account.',
          style: TextStyle(
            color: Colors.grey[400],
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Account: $_migrationEmail',
          style: TextStyle(
            color: Colors.grey[600],
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _migrateWithGoogle,
          icon: Image.asset(
            'assets/logo/google-logo.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
          label: _isLoading
              ? const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                )
              : const Text(
                  'Migrate with Google',
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
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _cancelMigration,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF444444),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }

  // Build Apple migration form (placeholder - you can implement Apple migration later)
  Widget _buildAppleMigrationForm() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          'Apple account migration is not yet implemented. Please use email/password login for now.',
          style: TextStyle(
            color: Colors.grey[400],
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Account: $_migrationEmail',
          style: TextStyle(
            color: Colors.grey[600],
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _cancelMigration,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF444444),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 1),
                  Image.asset(
                    'assets/logo/22.png',
                    width: 100,
                    height: 100,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showMigrationForm ? 'Account Update Required' : 'Log In',
                    style: const TextStyle(
                      color: Color(0xFFd9d9d9),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_showMigrationForm) ...[
                    // Show different forms based on provider
                    if (_migrationProvider == 'email') ...[
                      _buildPasswordMigrationForm(),
                    ] else if (_migrationProvider == 'google') ...[
                      _buildGoogleMigrationForm(),
                    ] else if (_migrationProvider == 'apple') ...[
                      _buildAppleMigrationForm(),
                    ],
                    const SizedBox(height: 16),
                  ] else ...[
                    // Normal login form
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
                    const SizedBox(height: 24),
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
                            const TextSpan(
                                text: 'By logging in, you agree to our '),
                            TextSpan(
                              text: 'Terms of Service',
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
                          ],
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : loginUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF333333),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            )
                          : const Text(
                              'Log In',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Inter',
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),
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
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : loginWithGoogle,
                      icon: Image.asset(
                        'assets/logo/google-logo.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                      label: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Log in with Google',
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
                    const SizedBox(height: 16),
                    if (!isAndroid || kIsWeb)
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : loginWithApple,
                        icon: Image.asset(
                          'assets/logo/apple-logo.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                          color: Colors.white,
                        ),
                        label: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                'Log in with Apple',
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
                    if (!isAndroid || kIsWeb) const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const SignupScreen()),
                      ),
                      child: const Text(
                        'Don\'t have an account? Signup',
                        style: TextStyle(
                          color: Color(0xFFd9d9d9),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
