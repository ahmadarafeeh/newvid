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
  final TextEditingController _socialLinkController = TextEditingController();
  bool _isSubmitting = false;
  String _selectedPlatform = 'instagram';
  final List<String> _platforms = [
    'instagram',
    'twitter',
    'facebook',
    'linkedin',
    'youtube',
    'tiktok'
  ];

  final Map<String, String> _platformIcons = {
    'instagram': '📸',
    'twitter': '🐦',
    'facebook': '📘',
    'linkedin': '💼',
    'youtube': '🎥',
    'tiktok': '🎵',
  };

  Future<String?> _getRatedlyAccount() async {
    try {
      final ratedlyResponse = await _supabase
          .from('users')
          .select('uid, username, photoUrl')
          .eq('username', 'ratedly')
          .maybeSingle();

      if (ratedlyResponse != null && ratedlyResponse.isNotEmpty) {
        return ratedlyResponse['uid'];
      }

      return await _createRatedlyAccount();
    } catch (e) {
      debugPrint('Error getting Ratedly account: $e');
      return null;
    }
  }

  Future<String?> _createRatedlyAccount() async {
    try {
      final ratedlyUid = 'ratedly_${DateTime.now().millisecondsSinceEpoch}';

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
    if (_isSubmitting) return;

    if (_socialLinkController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please provide your social media link')),
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

      // Get or create Ratedly account
      final ratedlyUid = await _getRatedlyAccount();

      if (ratedlyUid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Unable to process verification request. Please try again.')),
        );
        return;
      }

      // Get or create chat with Ratedly account
      final chatId = await SupabaseMessagesMethods().getOrCreateChat(
        currentUserId,
        ratedlyUid,
      );

      // Send the verification request
      final platformName =
          _selectedPlatform[0].toUpperCase() + _selectedPlatform.substring(1);
      final link = _socialLinkController.text.trim();

      await SupabaseMessagesMethods().sendMessage(
        chatId,
        currentUserId,
        ratedlyUid,
        '🔵 **Blue Verification Request**\n'
        '**User:** @$currentUsername\n'
        '**Platform:** $platformName\n'
        '**Link:** $link\n\n'
        'Verification steps to follow:\n'
        '1. Check profile photos match\n'
        '2. Schedule video call if needed\n'
        '3. Set up weekly photo monitoring',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request submitted! We\'ll review within 24 hours.'),
            duration: Duration(seconds: 3),
          ),
        );

        _socialLinkController.clear();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildPlatformSelector(_ColorSet colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Platform',
          style: TextStyle(
            color: colors.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _platforms.map((platform) {
              final isSelected = platform == _selectedPlatform;
              return GestureDetector(
                onTap: () => setState(() => _selectedPlatform = platform),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue
                        : colors.cardColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue
                          : colors.textColor.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _platformIcons[platform]!,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        platform[0].toUpperCase() + platform.substring(1),
                        style: TextStyle(
                          color: isSelected ? Colors.white : colors.textColor,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkField(_ColorSet colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profile Link',
          style: TextStyle(
            color: colors.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _socialLinkController,
          style: TextStyle(color: colors.textColor),
          decoration: InputDecoration(
            hintText: 'https://${_selectedPlatform}.com/yourprofile',
            hintStyle: TextStyle(
              color: colors.textColor.withOpacity(0.5),
              fontSize: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colors.textColor.withOpacity(0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colors.textColor.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue),
            ),
            filled: true,
            fillColor: colors.cardColor.withOpacity(0.5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _socialLinkController.dispose();
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
        title: Text(
          'Get Verified',
          style: TextStyle(
            color: colors.textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colors.backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textColor),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue.shade50.withOpacity(0.3),
                            Colors.purple.shade50.withOpacity(0.3),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Simple & Fast Verification',
                            style: TextStyle(
                              color: colors.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Get verified in 3 simple steps. No complicated requirements.',
                            style: TextStyle(
                              color: colors.textColor.withOpacity(0.7),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Steps
                    _buildStep(
                      colors,
                      number: '1',
                      title: 'Link Social Account',
                      description:
                          'Connect one social media account (Instagram, Twitter, etc.)',
                      icon: Icons.link,
                    ),

                    const SizedBox(height: 20),

                    _buildStep(
                      colors,
                      number: '2',
                      title: 'Quick Review',
                      description:
                          'We check if your profile photo matches. Video call may be requested.',
                      icon: Icons.video_call,
                    ),

                    const SizedBox(height: 20),

                    _buildStep(
                      colors,
                      number: '3',
                      title: 'Weekly Monitoring',
                      description:
                          'We verify weekly that your photos still match. Verification removed if changed.',
                      icon: Icons.photo_camera,
                    ),

                    const SizedBox(height: 32),

                    // Form
                    Text(
                      'Connect Your Account',
                      style: TextStyle(
                        color: colors.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildPlatformSelector(colors),

                    const SizedBox(height: 20),

                    _buildLinkField(colors),

                    const SizedBox(height: 24),

                    // Info Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.cardColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.textColor.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'We only check profile photos weekly. Your data is secure.',
                              style: TextStyle(
                                color: colors.textColor.withOpacity(0.7),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Submit Button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.backgroundColor,
                border: Border(
                  top: BorderSide(
                    color: colors.textColor.withOpacity(0.1),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitVerificationRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Submit for Review',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(
    _ColorSet colors, {
    required String number,
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blue.shade600],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: colors.textColor.withOpacity(0.6),
                    fontSize: 14,
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

  _ColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
  });
}

class _DarkColors extends _ColorSet {
  _DarkColors()
      : super(
          textColor: const Color(0xFFE0E0E0),
          backgroundColor: const Color(0xFF0A0A0A),
          cardColor: const Color(0xFF1A1A1A),
        );
}

class _LightColors extends _ColorSet {
  _LightColors()
      : super(
          textColor: const Color(0xFF1A1A1A),
          backgroundColor: const Color(0xFFF8F9FA),
          cardColor: Colors.white,
        );
}
