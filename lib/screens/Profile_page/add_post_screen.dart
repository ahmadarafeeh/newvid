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

class AddPostScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;
  const AddPostScreen({Key? key, this.onPostUploaded}) : super(key: key);

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  Uint8List? _file;
  File? _videoFile;
  bool isLoading = false;
  bool _isVideo = false;
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _captionFocusNode = FocusNode();
  final double _maxFileSize = 2.5 * 1024 * 1024;
  final double _maxVideoSize = 50 * 1024 * 1024;
  bool _hasAgreedToWarning = false;

  // Video trimming variables
  final Trimmer _trimmer = Trimmer();
  bool _isTrimming = false;
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;

  // ===========================================================================
  // ERROR LOGGING HELPER
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
    } catch (_) {
      // Silently ignore logging failures
    }
  }

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(() {
      setState(() {});
    });
    _checkIfUserAgreed();
  }

  Future<void> _checkIfUserAgreed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hasAgreedToWarning =
            prefs.getBool('hasAgreedToPostingWarning') ?? false;
      });
    } catch (e, stack) {
      await _logError(
        operation: '_checkIfUserAgreed',
        error: e,
        stack: stack,
      );
    }
  }

  Future<void> _saveUserAgreement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasAgreedToPostingWarning', true);
      setState(() {
        _hasAgreedToWarning = true;
      });
    } catch (e, stack) {
      await _logError(
        operation: '_saveUserAgreement',
        error: e,
        stack: stack,
      );
    }
  }

  Future<void> _showWarningDialog() async {
    if (_hasAgreedToWarning) {
      _selectMedia(context);
      return;
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: mobileBackgroundColor,
          title: Text(
            'Ratedly Guidlines',
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Posting inappropriate content will get your device ',
                  style: TextStyle(color: primaryColor),
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
                  style: TextStyle(color: primaryColor),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'I Understand',
                style: TextStyle(
                  color: primaryColor,
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

  @override
  void dispose() {
    _trimmer.dispose();
    _descriptionController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _selectMedia(BuildContext parentContext) async {
    return showDialog<void>(
      context: parentContext,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: mobileBackgroundColor,
          title: Text(
            'Create a Post',
            style: TextStyle(color: primaryColor),
          ),
          children: <Widget>[
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child:
                  Text('Take a Photo', style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickAndProcessImage(ImageSource.camera);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child:
                  Text('Record a Video', style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _recordVideoFromCamera();
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Image from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickAndProcessImage(ImageSource.gallery);
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text('Choose Video from Gallery',
                  style: TextStyle(color: primaryColor)),
              onPressed: () async {
                Navigator.pop(context);
                await _pickVideoFromGallery();
              },
            ),
            SimpleDialogOption(
              padding: const EdgeInsets.all(20),
              child: Text("Cancel", style: TextStyle(color: primaryColor)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

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
              'filePath': pickedFile.path,
            },
          );
        }

        if (compressedImage != null && compressedImage.length > _maxFileSize) {
          await _logError(
            operation:
                '_pickAndProcessImage/still_over_limit_before_extra_compress',
            error: 'Image still over limit after initial compress, retrying',
            additionalData: {
              'source': source.toString(),
              'compressedSizeBytes': compressedImage.length,
              'maxFileSizeBytes': _maxFileSize,
            },
          );
          compressedImage = await _compressUntilUnderLimit(compressedImage);
        }

        if (compressedImage != null) {
          setState(() {
            _file = compressedImage;
            isLoading = false;
          });
        } else {
          await _logError(
            operation: '_pickAndProcessImage/fallback_to_raw',
            error: 'Compression failed entirely, using raw bytes as fallback',
            additionalData: {
              'source': source.toString(),
              'rawFileSizeBytes': rawSize,
            },
          );
          final Uint8List fallback = await pickedFile.readAsBytes();
          setState(() {
            _file = fallback;
            isLoading = false;
          });
        }
      } else {
        await _logError(
          operation: '_pickAndProcessImage/user_cancelled',
          error: 'User cancelled image picker',
          additionalData: {'source': source.toString()},
        );
        setState(() => isLoading = false);
      }
    } catch (e, stack) {
      setState(() => isLoading = false);
      await _logError(
        operation: '_pickAndProcessImage',
        error: e,
        stack: stack,
        additionalData: {'source': source.toString()},
      );
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
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
          await _logError(
            operation: '_pickVideoFromGallery/video_too_large',
            error: 'Video exceeds max size',
            additionalData: {
              'videoSizeBytes': videoSize,
              'maxVideoSizeBytes': _maxVideoSize,
              'filePath': pickedFile.path,
            },
          );
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
        await _logError(
          operation: '_pickVideoFromGallery/user_cancelled',
          error: 'User cancelled video picker',
          additionalData: {'source': 'gallery'},
        );
        setState(() => isLoading = false);
      }
    } catch (e, stack) {
      setState(() => isLoading = false);
      await _logError(
        operation: '_pickVideoFromGallery',
        error: e,
        stack: stack,
      );
      if (context.mounted) {
        showSnackBar(context, 'Failed to pick video: $e');
      }
    }
  }

  Future<void> _recordVideoFromCamera() async {
    try {
      setState(() {
        _isVideo = true;
        isLoading = true;
        _file = null;
      });

      final pickedFile = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxDuration: const Duration(seconds: 20),
      );

      if (pickedFile != null) {
        final File videoFile = File(pickedFile.path);
        final int videoSize = await videoFile.length();

        if (videoSize > _maxVideoSize) {
          await _logError(
            operation: '_recordVideoFromCamera/video_too_large',
            error: 'Recorded video exceeds max size',
            additionalData: {
              'videoSizeBytes': videoSize,
              'maxVideoSizeBytes': _maxVideoSize,
              'filePath': pickedFile.path,
            },
          );
          if (context.mounted) {
            showSnackBar(context,
                'Video too large (max 50MB). Please record a shorter video.');
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
        await _logError(
          operation: '_recordVideoFromCamera/user_cancelled',
          error: 'User cancelled camera recording',
          additionalData: {'source': 'camera'},
        );
        setState(() => isLoading = false);
      }
    } catch (e, stack) {
      setState(() => isLoading = false);
      await _logError(
        operation: '_recordVideoFromCamera',
        error: e,
        stack: stack,
      );
      if (context.mounted) {
        showSnackBar(context, 'Failed to record video: $e');
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
    setState(() {
      _progressVisibility = true;
    });

    String? trimmedPath;

    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (String? value) {
          if (value == null) {
            _logError(
              operation: '_trimVideo/onSave_null',
              error: 'saveTrimmedVideo returned null path',
              additionalData: {
                'startValue': _startValue,
                'endValue': _endValue,
              },
            );
          }
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

      if (compressedImage != null && compressedImage.length > _maxFileSize) {
        await _logError(
          operation: '_compressUntilUnderLimit/still_over_limit',
          error: 'Image still over limit after aggressive compression',
          additionalData: {
            'finalSizeBytes': compressedImage.length,
            'maxFileSizeBytes': _maxFileSize,
            'finalQuality': quality,
          },
        );
      }
    } catch (e, stack) {
      await _logError(
        operation: '_compressUntilUnderLimit',
        error: e,
        stack: stack,
        additionalData: {
          'quality': quality,
          'imageSizeBytes': imageBytes.length,
        },
      );
    }

    return compressedImage;
  }

  void _rotateImage() {
    if (_file == null || _isVideo) return;

    try {
      final image = img.decodeImage(_file!);
      if (image == null) {
        _logError(
          operation: '_rotateImage/decode_null',
          error: 'img.decodeImage returned null',
          additionalData: {'fileSizeBytes': _file?.length},
        );
        return;
      }
      final rotated = img.copyRotate(image, angle: 90);
      setState(() =>
          _file = Uint8List.fromList(img.encodeJpg(rotated, quality: 80)));
    } catch (e, stack) {
      _logError(
        operation: '_rotateImage',
        error: e,
        stack: stack,
        additionalData: {'fileSizeBytes': _file?.length},
      );
      if (context.mounted) {
        showSnackBar(
            context, 'Please try again or contact us at ratedly9@gmail.com');
      }
    }
  }

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
      await _logError(
        operation: 'postMedia/missing_uid',
        error: 'User UID is empty at time of posting',
      );
      if (context.mounted) {
        showSnackBar(context, "User information missing");
      }
      return;
    }

    if (!_isVideo && _file == null) {
      await _logError(
        operation: 'postMedia/no_image_selected',
        error: 'Post attempted with no image file',
        additionalData: {'isVideo': _isVideo},
      );
      if (context.mounted) {
        showSnackBar(context, "Please select media first.");
      }
      return;
    }

    if (_isVideo && _videoFile == null) {
      await _logError(
        operation: 'postMedia/no_video_selected',
        error: 'Post attempted with no video file',
        additionalData: {'isVideo': _isVideo},
      );
      if (context.mounted) {
        showSnackBar(context, "Please select a video first.");
      }
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
            await _logError(
              operation: 'postMedia/trim_returned_null',
              error: 'Video trim returned null path',
              additionalData: {
                'startValue': _startValue,
                'endValue': _endValue,
                'videoFilePath': _videoFile?.path,
              },
            );
            if (context.mounted) {
              showSnackBar(context, 'Failed to trim video');
            }
            setState(() => isLoading = false);
            return;
          }

          _videoFile = File(trimmedPath);
        }

        final int videoSize = await _videoFile!.length();

        res = await SupabasePostsMethods().uploadVideoPostFromFile(
          _descriptionController.text,
          _videoFile!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );

        if (res != 'success') {
          await _logError(
            operation: 'postMedia/upload_video_failed',
            error: res,
            additionalData: {
              'uid': user.uid,
              'username': user.username,
              'videoSizeBytes': videoSize,
              'isTrimming': _isTrimming,
            },
          );
        }
      } else {
        final int imageSize = _file!.length;

        res = await SupabasePostsMethods().uploadPost(
          _descriptionController.text,
          _file!,
          user.uid,
          user.username ?? '',
          user.photoUrl ?? '',
          user.gender ?? '',
        );

        if (res != 'success') {
          await _logError(
            operation: 'postMedia/upload_image_failed',
            error: res,
            additionalData: {
              'uid': user.uid,
              'username': user.username,
              'imageSizeBytes': imageSize,
            },
          );
        }
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
        additionalData: {
          'isVideo': _isVideo,
          'isTrimming': _isTrimming,
          'uid': user.uid,
          'username': user.username,
          'captionLength': _descriptionController.text.length,
        },
      );
      if (context.mounted) {
        showSnackBar(context, err.toString());
      }
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
            SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _descriptionController,
                focusNode: _captionFocusNode,
                decoration: InputDecoration(
                  hintText: "Write a caption...",
                  hintStyle: TextStyle(color: primaryColor.withOpacity(0.6)),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                style: TextStyle(color: primaryColor),
                maxLines: 3,
                maxLength: 250,
              ),
            ),
            SizedBox(width: 8),
            if (_captionFocusNode.hasFocus)
              TextButton(
                onPressed: _dismissKeyboard,
                child: Text(
                  "OK",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
        actions: [
          _buildPostButton(isLoading, () => postMedia(user)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.only(bottom: 16.0),
              color: Colors.black,
              child: Column(
                children: <Widget>[
                  if (_progressVisibility || isLoading)
                    LinearProgressIndicator(
                      color: primaryColor,
                      backgroundColor: primaryColor.withOpacity(0.2),
                    ),
                  Expanded(
                    child: VideoViewer(trimmer: _trimmer),
                  ),
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
                        ? Icon(Icons.pause, size: 80.0, color: Colors.white)
                        : Icon(Icons.play_arrow,
                            size: 80.0, color: Colors.white),
                    onPressed: () async {
                      try {
                        bool playbackState =
                            await _trimmer.videoPlaybackControl(
                          startValue: _startValue,
                          endValue: _endValue,
                        );
                        setState(() {
                          _isPlaying = playbackState;
                        });
                      } catch (e, stack) {
                        await _logError(
                          operation: '_buildVideoTrimmer/playbackControl',
                          error: e,
                          stack: stack,
                          additionalData: {
                            'startValue': _startValue,
                            'endValue': _endValue,
                          },
                        );
                      }
                    },
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Container(
            color: mobileBackgroundColor,
            padding: EdgeInsets.all(16.0),
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

    if (_isTrimming) {
      return _buildVideoTrimmer(user);
    }

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
              child: IconButton(
                icon: Icon(Icons.upload, color: primaryColor, size: 50),
                onPressed: () => _showWarningDialog(),
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
                      child: Image.memory(
                        _file!,
                        fit: BoxFit.cover,
                      ),
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
