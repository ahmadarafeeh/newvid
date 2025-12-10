// lib/screens/edit_profile_screen.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:Ratedly/resources/storage_methods.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/services/firebase_supabase_service.dart';
import 'package:Ratedly/widgets/verified_username_widget.dart';
import 'package:video_trimmer/video_trimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';

// Define color schemes for both themes at top level
class _EditProfileColorSet {
  final Color textColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color iconColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color borderColor;
  final Color hintTextColor;
  final Color progressIndicatorColor;

  _EditProfileColorSet({
    required this.textColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.iconColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.borderColor,
    required this.hintTextColor,
    required this.progressIndicatorColor,
  });
}

class _EditProfileDarkColors extends _EditProfileColorSet {
  _EditProfileDarkColors()
      : super(
          textColor: const Color(0xFFd9d9d9),
          backgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF333333),
          iconColor: const Color(0xFFd9d9d9),
          buttonBackgroundColor: const Color(0xFF333333),
          buttonTextColor: const Color(0xFFd9d9d9),
          borderColor: const Color(0xFFd9d9d9),
          hintTextColor: const Color(0xFFd9d9d9).withOpacity(0.7),
          progressIndicatorColor: const Color(0xFFd9d9d9),
        );
}

class _EditProfileLightColors extends _EditProfileColorSet {
  _EditProfileLightColors()
      : super(
          textColor: Colors.black,
          backgroundColor: Colors.white,
          cardColor: Colors.grey[200]!,
          iconColor: Colors.black,
          buttonBackgroundColor: Colors.grey[300]!,
          buttonTextColor: Colors.black,
          borderColor: Colors.black,
          hintTextColor: Colors.black.withOpacity(0.7),
          progressIndicatorColor: Colors.black,
        );
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _bioController = TextEditingController();
  Uint8List? _image;
  File? _videoFile;
  bool _isLoading = false;
  bool _isVideo = false;
  String? _initialPhotoUrl;
  String? _currentPhotoUrl;
  final supabase.SupabaseClient _supabase = supabase.Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  bool _hasAgreedToWarning = false;

  // Video trimming variables
  final Trimmer _trimmer = Trimmer();
  bool _isTrimming = false;
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;
  bool _showSaveButton = true;

  // User data for username display
  String? _username;
  String? _countryCode;
  bool _isVerified = false;

  // Track the picked file name
  String? _pickedFileName;

  // Helper method to get the appropriate color scheme
  _EditProfileColorSet _getColors(ThemeProvider themeProvider) {
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;
    return isDarkMode ? _EditProfileDarkColors() : _EditProfileLightColors();
  }

  // Helper methods to identify photo types
  bool _isGooglePhoto(String? url) {
    if (url == null || url == 'default') return false;
    return url.contains('googleusercontent.com') ||
        url.contains('lh3.googleusercontent.com');
  }

  bool _isSupabasePhoto(String? url) {
    if (url == null || url == 'default') return false;
    return url.contains('supabase.co/storage');
  }

  // Check if URL is a video (by extension)
  bool _isVideoUrl(String? url) {
    if (url == null || url == 'default') return false;
    final urlLower = url.toLowerCase();
    return urlLower.endsWith('.mp4') ||
        urlLower.endsWith('.mov') ||
        urlLower.endsWith('.avi') ||
        urlLower.endsWith('.mkv') ||
        urlLower.endsWith('.webm');
  }

  Widget _buildDefaultAvatar(_EditProfileColorSet colors) {
    return Center(
      child: Icon(
        Icons.account_circle,
        size: 96,
        color: colors.iconColor,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _testFirebaseAuth();
    _checkIfUserAgreed();
  }

  @override
  void dispose() {
    _trimmer.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _checkIfUserAgreed() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasAgreedToWarning = prefs.getBool('hasAgreedToProfileWarning') ?? false;
    });
  }

  Future<void> _saveUserAgreement() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasAgreedToProfileWarning', true);
    setState(() {
      _hasAgreedToWarning = true;
    });
  }

  Future<void> _showWarningDialog() async {
    if (_hasAgreedToWarning) {
      _selectMedia(context);
      return;
    }

    final colors =
        _getColors(Provider.of<ThemeProvider>(context, listen: false));

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: colors.cardColor,
          title: Text(
            'Profile Picture Guidelines',
            style: TextStyle(
              color: colors.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      'Using inappropriate content as your profile picture will get your device ',
                  style: TextStyle(color: colors.textColor),
                ),
                TextSpan(
                  text: 'permanently banned',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '.',
                  style: TextStyle(color: colors.textColor),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'I Understand',
                style: TextStyle(
                  color: colors.textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () async {
                await _saveUserAgreement();
                Navigator.of(context).pop();
                _selectMedia(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }

      await FirebaseSupabaseService.debugAuthState();

      String uid = currentUser.uid;
      final userData =
          await _supabase.from('users').select().eq('uid', uid).single();

      setState(() {
        _bioController.text = userData['bio'] ?? '';
        _initialPhotoUrl = userData['photoUrl'];
        _currentPhotoUrl = _initialPhotoUrl ?? 'default';
        _username = userData['username'] ?? 'User';
        _countryCode = userData['country']?.toString();
        _isVerified = userData['isVerified'] == true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _testFirebaseAuth() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseSupabaseService.debugAuthState();
      final response = await _supabase
          .from('users')
          .select('uid, email')
          .eq('uid', currentUser.uid);
    } catch (e) {}
  }

  void _showEditOptions(_EditProfileColorSet colors) {
    final bool hasAnyPhoto =
        _currentPhotoUrl != null && _currentPhotoUrl != 'default';

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.cardColor,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library, color: colors.iconColor),
                title: Text('Choose Photo from Gallery',
                    style: TextStyle(color: colors.textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _showWarningDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.video_library, color: colors.iconColor),
                title: Text('Choose Video from Gallery (max 3 seconds)',
                    style: TextStyle(color: colors.textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _showWarningDialog();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: colors.iconColor),
                title: Text('Take Photo',
                    style: TextStyle(color: colors.textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.videocam, color: colors.iconColor),
                title: Text('Record Video (max 3 seconds)',
                    style: TextStyle(color: colors.textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.camera);
                },
              ),
              if (hasAnyPhoto)
                ListTile(
                  leading: Icon(Icons.delete, color: colors.iconColor),
                  title: Text(
                    'Remove Current Picture',
                    style: TextStyle(color: colors.textColor),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectMedia(BuildContext parentContext) async {
    final colors =
        _getColors(Provider.of<ThemeProvider>(context, listen: false));

    return showDialog<void>(
      context: parentContext,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: colors.cardColor,
          title: Text(
            'Choose Profile Media',
            style: TextStyle(color: colors.textColor),
          ),
          children: <Widget>[
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Photo from Gallery',
                  style: TextStyle(color: colors.textColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.gallery);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Video from Gallery (max 3 seconds)',
                  style: TextStyle(color: colors.textColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickVideo(ImageSource.gallery);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text("Cancel", style: TextStyle(color: colors.textColor)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _isVideo = false;
        _isLoading = true;
        _isTrimming = false;
        _videoFile = null;
      });

      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final Uint8List imageBytes = await pickedFile.readAsBytes();
        setState(() {
          _image = imageBytes;
          _videoFile = null;
          _pickedFileName = pickedFile.name;
          _currentPhotoUrl = null;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      setState(() {
        _isVideo = true;
        _isLoading = true;
        _image = null;
      });

      final pickedFile = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 10),
      );

      if (pickedFile != null) {
        final File videoFile = File(pickedFile.path);

        // Load video into trimmer
        await _trimmer.loadVideo(videoFile: videoFile);

        setState(() {
          _videoFile = videoFile;
          _image = null;
          _pickedFileName = pickedFile.name;
          _currentPhotoUrl = null;
          _isTrimming = true;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick video: $e')),
        );
      }
    }
  }

  void _loadVideo() {
    if (_videoFile != null) {
      _trimmer.loadVideo(videoFile: _videoFile!);
    }
  }

  Future<String?> _trimVideo() async {
    setState(() {
      _progressVisibility = true;
    });

    String? trimmedPath;

    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (String? value) {
        setState(() {
          _progressVisibility = false;
          trimmedPath = value;
        });
      },
    );

    return trimmedPath;
  }

  void _removePhoto() {
    setState(() {
      _image = null;
      _videoFile = null;
      _isVideo = false;
      _pickedFileName = null;
      _currentPhotoUrl = 'default';
      _isTrimming = false;
    });
  }

  Future<void> _saveProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    if (_bioController.text.length > 250) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Bio cannot exceed 250 characters. Your bio is ${_bioController.text.length} characters.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      String uid = currentUser.uid;
      Map<String, dynamic> updatedData = {
        'bio': _bioController.text,
      };

      // Handle profile picture changes
      if (_image != null) {
        // User selected a new image
        String fileName = _pickedFileName ??
            'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
        String photoUrl = await StorageMethods().uploadImageToSupabase(
          _image!,
          fileName,
          useUserFolder: true,
        );
        updatedData['photoUrl'] = photoUrl;

        // Delete old media if it exists
        if (_initialPhotoUrl != null && _initialPhotoUrl != 'default') {
          await _deleteOldMedia(_initialPhotoUrl!);
        }
      } else if (_videoFile != null) {
        // User selected a new video - trim if needed
        if (_isTrimming) {
          setState(() => _progressVisibility = true);
          final String? trimmedPath = await _trimVideo();
          setState(() => _progressVisibility = false);

          if (trimmedPath == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to trim video')),
            );
            setState(() => _isLoading = false);
            return;
          }

          _videoFile = File(trimmedPath);
        }

        // Upload video
        String fileName = _pickedFileName ??
            'profile_video_${DateTime.now().millisecondsSinceEpoch}.mp4';

        // Read video file as bytes
        Uint8List videoBytes = await _videoFile!.readAsBytes();

        String videoUrl = await StorageMethods().uploadVideoToSupabase(
          videoBytes,
          fileName,
          useUserFolder: true,
        );
        updatedData['photoUrl'] = videoUrl;

        // Delete old media if it exists
        if (_initialPhotoUrl != null && _initialPhotoUrl != 'default') {
          await _deleteOldMedia(_initialPhotoUrl!);
        }
      } else if (_currentPhotoUrl == 'default') {
        // User wants to remove current photo/video
        if (_initialPhotoUrl != null && _initialPhotoUrl != 'default') {
          await _deleteOldMedia(_initialPhotoUrl!);
        }
        updatedData['photoUrl'] = 'default';
      }

      // Update user data
      await FirebaseSupabaseService.update(
        'users',
        updates: updatedData,
        filters: {'uid': uid},
      );

      setState(() {
        if (updatedData.containsKey('photoUrl')) {
          _initialPhotoUrl = updatedData['photoUrl'];
        }
        _currentPhotoUrl = _initialPhotoUrl;
        _image = null;
        _videoFile = null;
        _isTrimming = false;
        _pickedFileName = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated successfully!')),
        );

        Navigator.pop(context, {
          'bio': _bioController.text,
          'photoUrl': updatedData['photoUrl'] ?? _initialPhotoUrl,
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _deleteOldMedia(String mediaUrl) async {
    try {
      if (mediaUrl.contains('supabase.co/storage')) {
        await StorageMethods().deleteImage(mediaUrl);
      }
    } catch (e) {
      print('Error deleting old media: $e');
    }
  }

  Widget _buildVideoTrimmer() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.iconColor),
        backgroundColor: colors.backgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.iconColor),
          onPressed: () {
            setState(() {
              _isTrimming = false;
              _videoFile = null;
            });
          },
        ),
        title: Text('Trim Video (max 3s)',
            style: TextStyle(color: colors.textColor)),
        actions: [
          if (_showSaveButton && !_isLoading)
            TextButton(
              onPressed: () => _saveProfile(),
              child: Text(
                'Save',
                style: TextStyle(
                  color: colors.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16.0,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_progressVisibility || _isLoading)
            LinearProgressIndicator(
              color: colors.progressIndicatorColor,
              backgroundColor: colors.progressIndicatorColor.withOpacity(0.2),
            ),
          Expanded(
            child: Container(
              padding: EdgeInsets.only(bottom: 16.0),
              color: colors.backgroundColor,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: VideoViewer(trimmer: _trimmer),
                  ),
                  Center(
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 50.0,
                      viewerWidth: MediaQuery.of(context).size.width,
                      maxVideoLength: const Duration(seconds: 3),
                      onChangeStart: (value) => _startValue = value,
                      onChangeEnd: (value) => _endValue = value,
                      onChangePlaybackState: (value) =>
                          setState(() => _isPlaying = value),
                    ),
                  ),
                  TextButton(
                    child: _isPlaying
                        ? Icon(
                            Icons.pause,
                            size: 60.0,
                            color: colors.iconColor,
                          )
                        : Icon(
                            Icons.play_arrow,
                            size: 60.0,
                            color: colors.iconColor,
                          ),
                    onPressed: () async {
                      bool playbackState = await _trimmer.videoPlaybackControl(
                        startValue: _startValue,
                        endValue: _endValue,
                      );
                      setState(() {
                        _isPlaying = playbackState;
                      });
                    },
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Container(
            color: colors.cardColor,
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentUser != null && _username != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: VerifiedUsernameWidget(
                      username: _username!,
                      uid: currentUser.uid,
                      countryCode: _countryCode,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textColor,
                      ),
                    ),
                  ),
                TextField(
                  controller: _bioController,
                  decoration: InputDecoration(
                    labelText: 'Bio',
                    labelStyle: TextStyle(color: colors.textColor),
                    hintText: 'Write something about yourself...',
                    hintStyle: TextStyle(color: colors.hintTextColor),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.borderColor),
                    ),
                    filled: true,
                    fillColor: colors.backgroundColor,
                  ),
                  style: TextStyle(color: colors.textColor),
                  maxLines: 3,
                  maxLength: 250,
                ),
                SizedBox(height: 10),
                Text(
                  'Note: Video will be trimmed to 3 seconds maximum for profile picture',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.hintTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileImage(_EditProfileColorSet colors) {
    if (_image != null) {
      return Image.memory(
        _image!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      );
    }

    if (_videoFile != null && !_isTrimming) {
      return Container(
        color: colors.backgroundColor,
        child: Icon(
          Icons.videocam,
          size: 60,
          color: colors.iconColor,
        ),
      );
    }

    if (_currentPhotoUrl != null && _currentPhotoUrl != 'default') {
      return Image.network(
        _currentPhotoUrl!,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildDefaultAvatar(colors),
      );
    }

    return _buildDefaultAvatar(colors);
  }

  Widget _buildPostButton(
      bool isLoading, VoidCallback onPressed, _EditProfileColorSet colors) {
    return IgnorePointer(
      ignoring: isLoading,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        child: Text(
          isLoading ? "Saving..." : "Save",
          style: TextStyle(
            color: isLoading
                ? colors.textColor.withOpacity(0.5)
                : colors.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16.0,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isTrimming) {
      return _buildVideoTrimmer();
    }

    final themeProvider = Provider.of<ThemeProvider>(context);
    final colors = _getColors(themeProvider);
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: colors.backgroundColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: colors.iconColor),
        title: Text(
          'Edit Profile',
          style: TextStyle(color: colors.textColor),
        ),
        centerTitle: true,
        backgroundColor: colors.backgroundColor,
        elevation: 0,
        actions: [
          if (_image != null || _videoFile != null)
            _buildPostButton(_isLoading, _saveProfile, colors),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: colors.progressIndicatorColor))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Username with flag and verification badge
                  if (currentUser != null && _username != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: VerifiedUsernameWidget(
                        username: _username!,
                        uid: currentUser.uid,
                        countryCode: _countryCode,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colors.textColor,
                        ),
                      ),
                    ),
                  Center(
                    child: GestureDetector(
                      onTap: () => _showEditOptions(colors),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: colors.cardColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.borderColor,
                            width: 2.0,
                          ),
                        ),
                        child: Stack(
                          children: [
                            ClipOval(
                              child: _buildProfileImage(colors),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colors.cardColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.backgroundColor,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 14,
                                  color: colors.iconColor,
                                ),
                              ),
                            ),
                            if (_videoFile != null)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.videocam,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_videoFile != null && !_isTrimming)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Video selected (will be trimmed to 3s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textColor.withOpacity(0.7),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _bioController,
                    decoration: InputDecoration(
                      labelText: 'Bio',
                      labelStyle: TextStyle(color: colors.textColor),
                      hintText: 'Write something about yourself...',
                      hintStyle: TextStyle(color: colors.hintTextColor),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.borderColor),
                      ),
                      filled: true,
                      fillColor: colors.cardColor,
                    ),
                    style: TextStyle(color: colors.textColor),
                    maxLines: 3,
                    maxLength: 250,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.buttonBackgroundColor,
                      foregroundColor: colors.buttonTextColor,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
