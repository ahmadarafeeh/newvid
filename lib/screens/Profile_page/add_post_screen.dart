// lib/screens/Profile_page/add_post_screen.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/resources/supabase_posts_methods.dart';
import 'package:Ratedly/utils/colors.dart';
import 'package:Ratedly/utils/utils.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/models/user.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_trimmer/video_trimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class AddPostScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;

  /// Pre-captured / pre-edited image bytes.
  /// When provided, the camera/gallery picker is skipped entirely.
  final Uint8List? initialFile;

  /// Pre-captured video file (e.g. from custom camera or gallery).
  /// When provided, the video trimmer is shown directly.
  final File? initialVideoFile;

  const AddPostScreen({
    Key? key,
    this.onPostUploaded,
    this.initialFile,
    this.initialVideoFile,
  }) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _file;
  File? _videoFile;
  bool isLoading = false;
  bool _isVideo = false;
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _captionFocusNode = FocusNode();
  final double _maxFileSize = 2.5 * 1024 * 1024;
  final double _maxVideoSize = 50 * 1024 * 1024;
  bool _hasAgreedToWarning = false;

  // Video trimming
  final Trimmer _trimmer = Trimmer();
  bool _isTrimming = false;
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;

  // Pulse animation for upload button
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ===========================================================================
  // ERROR LOGGING
  // ===========================================================================
  Future<void> _logError({
    required String operation,
    required dynamic error,
    StackTrace? stack,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      await Supabase.instance.client.from('posts_errors').insert({
        'user_id': user?.uid,
        'operation_type': operation,
        'error_message': error.toString(),
        'stack_trace': stack?.toString(),
        'additional_data': additionalData,
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(() => setState(() {}));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // If initial media was passed in (from CustomCameraScreen/MediaEditScreen),
    // load it immediately without any picker dialogs.
    if (widget.initialFile != null) {
      _file = widget.initialFile;
      _isVideo = false;
    } else if (widget.initialVideoFile != null) {
      _videoFile = widget.initialVideoFile;
      _isVideo = true;
      _isTrimming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadVideo());
    } else {
      _checkIfUserAgreed();
    }
  }

  @override
  void dispose() {
    _trimmer.dispose();
    _descriptionController.dispose();
    _captionFocusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkIfUserAgreed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hasAgreedToWarning =
            prefs.getBool('hasAgreedToPostingWarning') ?? false;
      });
    } catch (e, stack) {
      await _logError(operation: '_checkIfUserAgreed', error: e, stack: stack);
    }
  }

  Future<void> _saveUserAgreement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasAgreedToPostingWarning', true);
      setState(() => _hasAgreedToWarning = true);
    } catch (e, stack) {
      await _logError(operation: '_saveUserAgreement', error: e, stack: stack);
    }
  }

  // ===========================================================================
  // ENTRY POINT (fallback — used when opened directly, not from camera)
  // ===========================================================================

  Future<void> _onUploadButtonPressed() async {
    if (!_hasAgreedToWarning) {
      final agreed = await _showWarningDialog();
      if (agreed != true) return;
      await _saveUserAgreement();
    }
    await _launchCamera();
  }

  Future<bool?> _showWarningDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: mobileBackgroundColor,
        title: Text(
          'Ratedly Guidelines',
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        ),
        content: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'Posting inappropriate content will get your device ',
              style: TextStyle(color: primaryColor),
            ),
            TextSpan(
              text: 'permanently banned',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            TextSpan(text: '.', style: TextStyle(color: primaryColor)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'I Understand',
              style:
                  TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchCamera() async {
    try {
      await _pickAndProcessImage(ImageSource.camera);
    } catch (e) {
      final String errStr = e.toString().toLowerCase();
      final bool isPermissionError = errStr.contains('permission') ||
          errStr.contains('denied') ||
          errStr.contains('access') ||
          errStr.contains('not authorized');

      if (isPermissionError) {
        final status = await Permission.camera.status;
        await _showPermissionSheet(
          isPermanent: status.isPermanentlyDenied,
          needsMic: false,
        );
      } else {
        await _logError(
          operation: '_launchCamera',
          error: e,
          additionalData: {'errorString': e.toString()},
        );
        if (context.mounted) {
          showSnackBar(context, 'Could not open camera. Please try again.');
        }
      }
    }
  }

  Future<void> _showPermissionSheet({
    required bool isPermanent,
    required bool needsMic,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PermissionSheet(
        isPermanent: isPermanent,
        needsMic: needsMic,
        onOpenGallery: () {
          Navigator.pop(ctx);
          if (needsMic) {
            _pickVideoFromGallery();
          } else {
            _pickAndProcessImage(ImageSource.gallery);
          }
        },
        onOpenSettings: isPermanent
            ? () async {
                Navigator.pop(ctx);
                await openAppSettings();
              }
            : null,
      ),
    );
  }

  // ===========================================================================
  // MEDIA PICKING (fallback when no initial media)
  // ===========================================================================

  Future<void> _pickAndProcessImage(ImageSource source) async {
    try {
      setState(() {
        _isVideo = false;
        isLoading = true;
        _isTrimming = false;
        _videoFile = null;
      });

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final int rawSize = await File(pickedFile.path).length();

        Uint8List? compressedImage =
            await FlutterImageCompress.compressWithFile(
          pickedFile.path,
          minWidth: 800,
          minHeight: 800,
          quality: 80,
          format: CompressFormat.jpeg,
        );

        if (compressedImage == null) {
          await _logError(
            operation: '_pickAndProcessImage/compress_returned_null',
            error: 'FlutterImageCompress returned null',
            additionalData: {
              'source': source.toString(),
              'rawFileSizeBytes': rawSize,
            },
          );
        }

        if (compressedImage != null && compressedImage.length > _maxFileSize) {
          compressedImage = await _compressUntilUnderLimit(compressedImage);
        }

        if (compressedImage != null) {
          setState(() {
            _file = compressedImage;
            isLoading = false;
          });
        } else {
          final Uint8List fallback = await pickedFile.readAsBytes();
          setState(() {
            _file = fallback;
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e, stack) {
      setState(() => isLoading = false);
      rethrow;
    }
  }

  Future<void> _pickVideoFromGallery() async {
    try {
      setState(() {
        _isVideo = true;
        isLoading = true;
        _file = null;
      });

      final pickedFile = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile != null) {
        final File videoFile = File(pickedFile.path);
        final int videoSize = await videoFile.length();

        if (videoSize > _maxVideoSize) {
          if (context.mounted) {
            showSnackBar(context,
                'Video too large (max 50MB). Please choose a shorter video.');
          }
          setState(() => isLoading = false);
          return;
        }

        _videoFile = videoFile;
        _loadVideo();
        setState(() {
          _isTrimming = true;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e, stack) {
      setState(() => isLoading = false);
      await _logError(
          operation: '_pickVideoFromGallery', error: e, stack: stack);
      if (context.mounted) {
        showSnackBar(context, 'Failed to pick video: $e');
      }
    }
  }

  void _loadVideo() {
    if (_videoFile != null) {
      try {
        _trimmer.loadVideo(videoFile: _videoFile!);
      } catch (e, stack) {
        _logError(
          operation: '_loadVideo',
          error: e,
          stack: stack,
          additionalData: {'filePath': _videoFile?.path},
        );
      }
    }
  }

  Future<String?> _trimVideo() async {
    setState(() => _progressVisibility = true);
    String? trimmedPath;
    try {
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
    } catch (e, stack) {
      setState(() => _progressVisibility = false);
      await _logError(
        operation: '_trimVideo',
        error: e,
        stack: stack,
        additionalData: {
          'startValue': _startValue,
          'endValue': _endValue,
          'videoFilePath': _videoFile?.path,
        },
      );
    }
    return trimmedPath;
  }

  Future<Uint8List?> _compressUntilUnderLimit(Uint8List imageBytes) async {
    int quality = 75;
    Uint8List? compressedImage = imageBytes;
    try {
      while (quality >= 50 &&
          compressedImage != null &&
          compressedImage.length > _maxFileSize) {
        compressedImage = await FlutterImageCompress.compressWithList(
          compressedImage,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        quality -= 5;
      }
    } catch (e, stack) {
      await _logError(
        operation: '_compressUntilUnderLimit',
        error: e,
        stack: stack,
      );
    }
    return compressedImage;
  }

  void _rotateImage() {
    if (_file == null || _isVideo) return;
    try {
      final image = img.decodeImage(_file!);
      if (image == null) return;
      final rotated = img.copyRotate(image, angle: 90);
      setState(() =>
          _file = Uint8List.fromList(img.encodeJpg(rotated, quality: 80)));
    } catch (e, stack) {
      _logError(operation: '_rotateImage', error: e, stack: stack);
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

  // ===========================================================================
  // POST UPLOAD
  // ===========================================================================
  void postMedia(AppUser user) async {
    if (_descriptionController.text.length > 250) {
      if (context.mounted) {
        showSnackBar(context,
            'Caption cannot exceed 250 characters. Your caption is ${_descriptionController.text.length} characters.');
      }
      return;
    }
    if (isLoading) return;
    if (user.uid.isEmpty) {
      if (context.mounted) showSnackBar(context, "User information missing");
      return;
    }
    if (!_isVideo && _file == null) {
      if (context.mounted) showSnackBar(context, "Please select media first.");
      return;
    }
    if (_isVideo && _videoFile == null) {
      if (context.mounted)
        showSnackBar(context, "Please select a video first.");
      return;
    }

    setState(() => isLoading = true);

    try {
      final String res;

      if (_isVideo) {
        if (_isTrimming) {
          setState(() => _progressVisibility = true);
          final String? trimmedPath = await _trimVideo();
          setState(() => _progressVisibility = false);

          if (trimmedPath == null) {
            if (context.mounted) showSnackBar(context, 'Failed to trim video');
            setState(() => isLoading = false);
            return;
          }
          _videoFile = File(trimmedPath);
        }

        res = await SupabasePostsMethods().uploadVideoPostFromFile(
          _descriptionController.text,
          _videoFile!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );
      } else {
        res = await SupabasePostsMethods().uploadPost(
          _descriptionController.text,
          _file!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );
      }

      if (res == "success" && context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, _isVideo ? 'Video Posted!' : 'Posted!');
        clearMedia();
        widget.onPostUploaded?.call();
        Navigator.pop(context);
      } else if (context.mounted) {
        setState(() => isLoading = false);
        showSnackBar(context, 'Error: $res');
      }
    } catch (err, stack) {
      setState(() => isLoading = false);
      await _logError(
        operation: 'postMedia/unexpected_exception',
        error: err,
        stack: stack,
      );
      if (context.mounted) showSnackBar(context, err.toString());
    }
  }

  void clearMedia() {
    setState(() {
      _file = null;
      _videoFile = null;
      _isVideo = false;
      _isTrimming = false;
      _isPlaying = false;
      _progressVisibility = false;
      _descriptionController.clear();
    });
  }

  // ===========================================================================
  // WIDGETS
  // ===========================================================================

  Widget _buildPostButton(bool isLoading, VoidCallback onPressed) {
    return IgnorePointer(
      ignoring: isLoading,
      child: TextButton(
        onPressed: isLoading ? null : onPressed,
        child: Text(
          isLoading ? "Posting..." : "Post",
          style: TextStyle(
            color: isLoading ? primaryColor.withOpacity(0.5) : primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 16.0,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionInput(AppUser user) {
    final bool isNearLimit = _descriptionController.text.length > 200;
    final bool isOverLimit = _descriptionController.text.length > 250;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.transparent,
              backgroundImage: (user.photoUrl?.isNotEmpty == true &&
                      user.photoUrl != "default")
                  ? NetworkImage(user.photoUrl!)
                  : null,
              child: (user.photoUrl?.isEmpty == true ||
                      user.photoUrl == "default")
                  ? Icon(Icons.account_circle, size: 40, color: primaryColor)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _descriptionController,
                focusNode: _captionFocusNode,
                decoration: InputDecoration(
                  hintText: "Write a caption...",
                  hintStyle: TextStyle(color: primaryColor.withOpacity(0.6)),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                style: TextStyle(color: primaryColor),
                maxLines: 3,
                maxLength: 250,
              ),
            ),
            const SizedBox(width: 8),
            if (_captionFocusNode.hasFocus)
              TextButton(
                onPressed: () => FocusScope.of(context).unfocus(),
                child: Text("OK",
                    style: TextStyle(
                        color: primaryColor, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        if (isNearLimit)
          Padding(
            padding: const EdgeInsets.only(left: 56.0, top: 4.0),
            child: Text(
              '${_descriptionController.text.length}/250',
              style: TextStyle(
                color: isOverLimit ? Colors.red : primaryColor.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoTrimmer(AppUser user) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: primaryColor),
        backgroundColor: mobileBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            clearMedia();
            Navigator.pop(context);
          },
        ),
        title: Text('Trim Video', style: TextStyle(color: primaryColor)),
        actions: [_buildPostButton(isLoading, () => postMedia(user))],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 16.0),
              color: Colors.black,
              child: Column(
                children: [
                  if (_progressVisibility || isLoading)
                    LinearProgressIndicator(
                      color: primaryColor,
                      backgroundColor: primaryColor.withOpacity(0.2),
                    ),
                  Expanded(child: VideoViewer(trimmer: _trimmer)),
                  Center(
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 50.0,
                      viewerWidth: MediaQuery.of(context).size.width,
                      maxVideoLength: const Duration(seconds: 20),
                      onChangeStart: (value) => _startValue = value,
                      onChangeEnd: (value) => _endValue = value,
                      onChangePlaybackState: (value) =>
                          setState(() => _isPlaying = value),
                    ),
                  ),
                  TextButton(
                    child: _isPlaying
                        ? const Icon(Icons.pause,
                            size: 80.0, color: Colors.white)
                        : const Icon(Icons.play_arrow,
                            size: 80.0, color: Colors.white),
                    onPressed: () async {
                      try {
                        bool playbackState =
                            await _trimmer.videoPlaybackControl(
                          startValue: _startValue,
                          endValue: _endValue,
                        );
                        setState(() => _isPlaying = playbackState);
                      } catch (e, stack) {
                        await _logError(
                          operation: '_buildVideoTrimmer/playbackControl',
                          error: e,
                          stack: stack,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Container(
            color: mobileBackgroundColor,
            padding: const EdgeInsets.all(16.0),
            child: _buildCaptionInput(user),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    if (_isTrimming) return _buildVideoTrimmer(user);

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: primaryColor),
        backgroundColor: mobileBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryColor),
          onPressed: () {
            clearMedia();
            Navigator.pop(context);
          },
        ),
        title: Text('Ratedly', style: TextStyle(color: primaryColor)),
        actions: [
          if (_file != null && !_isVideo)
            _buildPostButton(isLoading, () => postMedia(user)),
        ],
      ),
      body: _file == null && _videoFile == null
          ? Center(
              child: ScaleTransition(
                scale: _pulseAnimation,
                child: IconButton(
                  icon: Icon(Icons.upload, color: primaryColor, size: 50),
                  onPressed: _onUploadButtonPressed,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (isLoading)
                    LinearProgressIndicator(
                      color: primaryColor,
                      backgroundColor: primaryColor.withOpacity(0.2),
                    ),
                  if (!_isVideo && _file != null)
                    Container(
                      height: MediaQuery.of(context).size.height * 0.5,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: primaryColor),
                      ),
                      child: Image.memory(_file!, fit: BoxFit.cover),
                    ),
                  if (!_isVideo && _file != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blueColor,
                          foregroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: Text('Edit Image',
                                style: TextStyle(color: primaryColor)),
                            backgroundColor: mobileBackgroundColor,
                            children: [
                              SimpleDialogOption(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _rotateImage();
                                },
                                child: Text('Rotate 90°',
                                    style: TextStyle(color: primaryColor)),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('Edit Photo'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: _buildCaptionInput(user),
                  ),
                ],
              ),
            ),
    );
  }
}

// =============================================================================
// PERMISSION DENIED SHEET
// =============================================================================

class _PermissionSheet extends StatelessWidget {
  final bool isPermanent;
  final bool needsMic;
  final VoidCallback onOpenGallery;
  final VoidCallback? onOpenSettings;

  const _PermissionSheet({
    required this.isPermanent,
    required this.needsMic,
    required this.onOpenGallery,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final String title =
        needsMic ? 'Camera & Microphone Access' : 'Camera Access';
    final String description = needsMic
        ? 'To record videos, Ratedly needs access to your camera and microphone.'
        : 'To take photos, Ratedly needs access to your camera.';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              needsMic ? Icons.mic_off_rounded : Icons.no_photography_rounded,
              color: Colors.white.withOpacity(0.55),
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(description,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  height: 1.55),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          if (isPermanent && onOpenSettings != null)
            _Btn(
                label: 'Open Settings', isPrimary: true, onTap: onOpenSettings!)
          else
            _Btn(
                label: 'Allow Access',
                isPrimary: true,
                onTap: () => Navigator.pop(context)),
          const SizedBox(height: 10),
          _Btn(
              label: needsMic
                  ? 'Upload Video from Library'
                  : 'Upload Photo from Library',
              isPrimary: false,
              onTap: onOpenGallery),
          const SizedBox(height: 10),
          _Btn(
              label: 'Not Now',
              isPrimary: false,
              isDim: true,
              onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final bool isDim;
  final VoidCallback onTap;

  const _Btn({
    required this.label,
    required this.isPrimary,
    this.isDim = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: isPrimary
              ? Colors.white
              : Colors.white.withOpacity(isDim ? 0.05 : 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isPrimary
                  ? Colors.black
                  : Colors.white.withOpacity(isDim ? 0.45 : 0.9),
              fontSize: 15,
              fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
