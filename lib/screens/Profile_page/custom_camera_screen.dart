// lib/screens/Profile_page/custom_camera_screen.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:Ratedly/screens/Profile_page/media_edit_screen.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:provider/provider.dart';

class CustomCameraScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;
  const CustomCameraScreen({Key? key, this.onPostUploaded}) : super(key: key);

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _isFrontCamera = true;
  bool _isInitialized = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isRecordingVideo = false;
  bool _isCapturing = false;

  // Gallery thumbnail
  Uint8List? _galleryThumbnail;
  bool _lastGalleryAssetIsVideo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _loadGalleryThumbnail();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ===========================================================================
  // CAMERA INIT
  // ===========================================================================

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _isFrontCamera
          ? _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => _cameras.first)
          : _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first);

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFlashMode(_flashMode);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
        });
      }
    } catch (e) {
      await _logError('_initCamera', e);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _isInitialized = false);
    await _controller?.dispose();
    _controller = null;
    _isFrontCamera = !_isFrontCamera;
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    FlashMode next;
    switch (_flashMode) {
      case FlashMode.off:
        next = FlashMode.auto;
        break;
      case FlashMode.auto:
        next = FlashMode.always;
        break;
      default:
        next = FlashMode.off;
    }
    try {
      await _controller!.setFlashMode(next);
      setState(() => _flashMode = next);
    } catch (_) {}
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      default:
        return Icons.flash_off;
    }
  }

  // ===========================================================================
  // GALLERY THUMBNAIL
  // ===========================================================================

  Future<void> _loadGalleryThumbnail() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return;

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (albums.isEmpty) return;

      final assets = await albums.first.getAssetListRange(start: 0, end: 1);
      if (assets.isEmpty) return;

      final asset = assets.first;
      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
      );

      if (mounted && thumb != null) {
        setState(() {
          _galleryThumbnail = thumb;
          _lastGalleryAssetIsVideo = asset.type == AssetType.video;
        });
      }
    } catch (e) {
      // Gallery thumbnail is optional — fail silently
    }
  }

  // ===========================================================================
  // CAPTURE
  // ===========================================================================

  Future<void> _capturePhoto() async {
    if (_controller == null || !_isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final XFile photo = await _controller!.takePicture();
      // Read bytes as-is — the camera package on iOS already saves
      // front camera photos correctly without mirroring.
      final Uint8List bytes = await photo.readAsBytes();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaEditScreen(
              imageBytes: bytes,
              onPostUploaded: widget.onPostUploaded,
            ),
          ),
        );
      }
    } catch (e) {
      await _logError('_capturePhoto', e);
      if (mounted) {
        _showError('Could not capture photo. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_isInitialized || _isRecordingVideo) return;
    try {
      await _controller!.startVideoRecording();
      setState(() => _isRecordingVideo = true);
    } catch (e) {
      await _logError('_startVideoRecording', e);
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_isRecordingVideo) return;
    try {
      final XFile video = await _controller!.stopVideoRecording();
      setState(() => _isRecordingVideo = false);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddPostScreen(
              initialVideoFile: File(video.path),
              onPostUploaded: widget.onPostUploaded,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isRecordingVideo = false);
      await _logError('_stopVideoRecording', e);
    }
  }

  // ===========================================================================
  // GALLERY PICKER
  // ===========================================================================

  Future<void> _openGallery() async {
    try {
      if (_lastGalleryAssetIsVideo) {
        final picked = await ImagePicker().pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 5),
        );
        if (picked != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddPostScreen(
                initialVideoFile: File(picked.path),
                onPostUploaded: widget.onPostUploaded,
              ),
            ),
          );
        }
      } else {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 90,
        );
        if (picked != null && mounted) {
          final bytes = await picked.readAsBytes();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MediaEditScreen(
                imageBytes: bytes,
                onPostUploaded: widget.onPostUploaded,
              ),
            ),
          );
        }
      }
    } catch (e) {
      await _logError('_openGallery', e);
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Future<void> _logError(String operation, dynamic error) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      await Supabase.instance.client.from('posts_errors').insert({
        'user_id': user?.uid,
        'operation_type': 'camera/$operation',
        'error_message': error.toString(),
      });
    } catch (_) {}
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera preview ───────────────────────────────────────────────
          if (_isInitialized && _controller != null)
            Positioned.fill(
              child: CameraPreview(_controller!),
            )
          else
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // ── Top bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CircleIconButton(
                      icon: Icons.close,
                      onTap: () => Navigator.pop(context),
                    ),
                    _CircleIconButton(
                      icon: _flashIcon,
                      onTap: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Recording indicator ──────────────────────────────────────────
          if (_isRecordingVideo)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 0,
              right: 0,
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.red, size: 12),
                    SizedBox(width: 6),
                    Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom controls ──────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Gallery thumbnail
                    GestureDetector(
                      onTap: _openGallery,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.6),
                              width: 1.5),
                          color: Colors.grey[900],
                          image: _galleryThumbnail != null
                              ? DecorationImage(
                                  image: MemoryImage(_galleryThumbnail!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _galleryThumbnail == null
                            ? Icon(Icons.photo_library_rounded,
                                color: Colors.white.withOpacity(0.6),
                                size: 22)
                            : _lastGalleryAssetIsVideo
                                ? const Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(3),
                                      child: Icon(Icons.play_circle_fill,
                                          color: Colors.white, size: 14),
                                    ),
                                  )
                                : null,
                      ),
                    ),

                    // Shutter button
                    GestureDetector(
                      onTap: _capturePhoto,
                      onLongPressStart: (_) => _startVideoRecording(),
                      onLongPressEnd: (_) => _stopVideoRecording(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: _isRecordingVideo ? 64 : 76,
                        height: _isRecordingVideo ? 64 : 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecordingVideo
                              ? Colors.red
                              : Colors.white,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.8),
                            width: _isRecordingVideo ? 4 : 5,
                          ),
                        ),
                        child: _isCapturing
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : _isRecordingVideo
                                ? const Icon(Icons.stop_rounded,
                                    color: Colors.white, size: 28)
                                : null,
                      ),
                    ),

                    // Flip camera
                    _CircleIconButton(
                      icon: Icons.flip_camera_ios_rounded,
                      size: 28,
                      onTap: _switchCamera,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Hint: hold for video ─────────────────────────────────────────
          if (!_isRecordingVideo)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 120,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Hold for video',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.35),
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}
