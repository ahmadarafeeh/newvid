import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/resources/messages_firestore_methods.dart';

class BlueVerificationScreen extends StatefulWidget {
  const BlueVerificationScreen({Key? key}) : super(key: key);

  @override
  State<BlueVerificationScreen> createState() => _BlueVerificationScreenState();
}

class _BlueVerificationScreenState extends State<BlueVerificationScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _linkController = TextEditingController();
  bool _isLoading = false;
  bool _isSubmitting = false;

  Future<String?> _getRatedlyAccount() async {
    try {
      // Try to find the Ratedly account
      final ratedlyResponse = await _supabase
          .from('users')
          .select('uid, username, photoUrl')
          .eq('username', 'ratedly')
          .maybeSingle(); // Use maybeSingle instead of single

      if (ratedlyResponse != null && ratedlyResponse.isNotEmpty) {
        return ratedlyResponse['uid'];
      }

      // If Ratedly account doesn't exist, create it
      return await _createRatedlyAccount();
    } catch (e) {
      debugPrint('Error getting Ratedly account: $e');
      return null;
    }
  }

  Future<String?> _createRatedlyAccount() async {
    try {
      // Create a unique UID for the Ratedly account
      final ratedlyUid = 'ratedly_${DateTime.now().millisecondsSinceEpoch}';

      // Insert the Ratedly account into the users table
      final response = await _supabase
          .from('users')
          .insert({
            'uid': ratedlyUid,
            'username': 'Ratedly',
            'photoUrl': 'default',
            'email': 'support@ratedly.com',
            'created_at': DateTime.now().toIso8601String(),
            'isVerified': true,
          })
          .select('uid')
          .single();

      return response['uid'];
    } catch (e) {
      debugPrint('Error creating Ratedly account: $e');
      return null;
    }
  }

  Future<void> _submitVerificationRequest() async {
    if (_isLoading || _isSubmitting) return;

    // Validate that the link is provided
    if (_linkController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please provide your TikTok Content link')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Get current user info
      final userResponse = await _supabase
          .from('users')
          .select('username, photoUrl')
          .eq('uid', currentUserId)
          .single();

      final currentUsername = userResponse['username'] ?? 'Unknown User';
      final currentPhotoUrl = userResponse['photoUrl'] ?? 'default';

      // Get or create Ratedly account
      final ratedlyUid = await _getRatedlyAccount();

      if (ratedlyUid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Unable to process verification request. Please try again later.')),
        );
        return;
      }

      // Get or create chat with Ratedly account
      final chatId = await SupabaseMessagesMethods().getOrCreateChat(
        currentUserId,
        ratedlyUid,
      );

      // Send the verification request message
      await SupabaseMessagesMethods().sendMessage(
        chatId,
        currentUserId,
        ratedlyUid,
        '🔵 Blue Verification Request from @$currentUsername\n\n'
        'I have posted a TikTok Content promoting Ratedly and would like to apply for verification.\n\n'
        'Here is my TikTok Content link:',
      );

      // Send the TikTok link
      final link = _linkController.text.trim();
      if (link.isNotEmpty) {
        await SupabaseMessagesMethods().sendMessage(
          chatId,
          currentUserId,
          ratedlyUid,
          'TikTok Content: $link',
        );
      }

      // Send final message with user info and identity verification requirement
      await SupabaseMessagesMethods().sendMessage(
        chatId,
        currentUserId,
        ratedlyUid,
        'User ID: $currentUserId\n'
        'Username: @$currentUsername\n\n'
        '⚠️ IDENTITY VERIFICATION REQUIRED\n'
        'After reviewing the TikTok Content, we will contact you to verify that you are the real owner of this account. '
        'This may require providing additional proof of identity.\n\n'
        'Please review my application and contact me for the identity verification step. Thank you! 🙏',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Verification request submitted successfully! We will review your TikTok link and contact you for identity verification within 24 hours.'),
            duration: Duration(seconds: 5),
          ),
        );

        // Clear form after successful submission
        _linkController.clear();

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to submit verification request: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildLinkField(_ColorSet colors) {
    return TextField(
      controller: _linkController,
      style: TextStyle(color: colors.textColor),
      decoration: InputDecoration(
        labelText: 'TikTok Content Link',
        labelStyle: TextStyle(color: colors.textColor.withOpacity(0.7)),
        hintText: 'https://www.tiktok.com/@username/Content/...',
        hintStyle: TextStyle(color: colors.textColor.withOpacity(0.5)),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colors.textColor.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.textColor.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.textColor),
        ),
        filled: true,
        fillColor: colors.cardColor.withOpacity(0.5),
      ),
    );
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    final colors = isDarkMode ? _DarkColors() : _LightColors();

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        title: Text('Blue Verification',
            style: TextStyle(color: colors.textColor)),
        centerTitle: true,
        backgroundColor: colors.backgroundColor,
        elevation: 1,
        iconTheme: IconThemeData(color: colors.textColor),
      ),
      body: _isSubmitting
          ? Center(child: CircularProgressIndicator(color: colors.textColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with verification badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Get verified to show other users your account is authentic and build trust in the Ratedly community!',
                            style: TextStyle(
                              color: colors.textColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Instructions
                  Text(
                    'How to Get Verified',
                    style: TextStyle(
                      color: colors.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // STEP 1: Create TikTok Post
                  _buildInstructionStep(
                    colors,
                    '1',
                    'Create TikTok Post',
                    'Create a TikTok post about Ratedly. It can be simple - share what you like about the app, how you use it, or invite others to join. Post any content that shows your experience with Ratedly.',
                  ),
                  const SizedBox(height: 16),

                  // STEP 2: Identity Verification
                  _buildInstructionStep(
                    colors,
                    '2',
                    'Identity Verification',
                    'After submitting your TikTok link, our team will contact you to verify that you are the real owner of this account. You may need to provide additional proof of identity.',
                  ),
                  const SizedBox(height: 16),

                  // STEP 3: Submit for Review
                  _buildInstructionStep(
                    colors,
                    '3',
                    'Submit for Review',
                    'Copy and paste the link to your TikTok post below. We will review your content and contact you for identity verification within 24 hours.',
                  ),

                  const SizedBox(height: 24),

                  // Link Input Field
                  Text(
                    'Submit Your TikTok Post Link',
                    style: TextStyle(
                      color: colors.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildLinkField(colors),

                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          _isSubmitting ? null : _submitVerificationRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Submit for Verification',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Note
                  Text(
                    'Note: After submission, your TikTok link will be automatically sent to the Ratedly team via direct message. '
                    'We will review your content and contact you for identity verification within 24 hours. '
                    'The entire verification process is typically completed within 24 hours.',
                    style: TextStyle(
                      color: colors.textColor.withOpacity(0.6),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInstructionStep(
      _ColorSet colors, String number, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: colors.textColor.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Color classes
class _ColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.grey[100]!,
          cardColor: Colors.white,
          iconColor: Colors.grey[700]!,
        );
}
