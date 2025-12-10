import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StorageMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // ===========================================================================
  // IMAGE METHODS - SUPABASE ONLY
  // ===========================================================================

  // Upload image to Supabase Storage
  Future<String> uploadImageToSupabase(Uint8List file, String fileName,
      {bool useUserFolder = true}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload image');
      }

      // Get file extension
      String extension = fileName.split('.').last.toLowerCase();

      // Validate it's an image
      if (!['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
        throw Exception(
            'Invalid image file type. Supported: jpg, jpeg, png, gif, webp, bmp');
      }

      // Create unique filename
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create path
      final String filePath;
      if (useUserFolder) {
        filePath = '${user.uid}/$uniqueFileName';
      } else {
        filePath = uniqueFileName;
      }

      // Convert Uint8List to File (temporary file)
      final tempFile = await _createTempFile(uniqueFileName, file);

      // Upload to Supabase Storage
      await _supabase.storage.from('Images').upload(filePath, tempFile,
          fileOptions: FileOptions(
            contentType: _getMimeType(extension),
            upsert: true,
          ));

      // Clean up temp file
      await tempFile.delete();

      // Get public URL
      final String publicUrl =
          _supabase.storage.from('Images').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload image to Supabase: $e');
    }
  }

  // Upload image file to Supabase (from File object)
  Future<String> uploadImageFileToSupabase(File imageFile, String fileName,
      {bool useUserFolder = true}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload image');
      }

      // Get file extension
      String extension = fileName.split('.').last.toLowerCase();

      // Validate it's an image
      if (!['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(extension)) {
        throw Exception('Invalid image file type');
      }

      // Create unique filename
      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      // Create path
      final String filePath;
      if (useUserFolder) {
        filePath = '${user.uid}/$uniqueFileName';
      } else {
        filePath = uniqueFileName;
      }

      // Upload to Supabase Storage
      await _supabase.storage.from('Images').upload(filePath, imageFile,
          fileOptions: FileOptions(
            contentType: _getMimeType(extension),
            upsert: true,
          ));

      // Get public URL
      final String publicUrl =
          _supabase.storage.from('Images').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload image file to Supabase: $e');
    }
  }

  // Pick image from gallery and upload to Supabase
  Future<String?> pickAndUploadImageToSupabase() async {
    try {
      // Pick image from gallery
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
      );

      if (pickedFile == null) return null;

      // Get the file
      final File imageFile = File(pickedFile.path);
      final fileName = pickedFile.name;

      // Upload to Supabase
      final url = await uploadImageFileToSupabase(
        imageFile,
        fileName,
        useUserFolder: true,
      );

      return url;
    } catch (e) {
      throw Exception('Failed to pick and upload image: $e');
    }
  }

  // Capture image from camera and upload to Supabase
  Future<String?> captureAndUploadImageToSupabase() async {
    try {
      // Capture image from camera
      final XFile? capturedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1080,
      );

      if (capturedFile == null) return null;

      // Get the file
      final File imageFile = File(capturedFile.path);
      final fileName = capturedFile.name;

      // Upload to Supabase
      final url = await uploadImageFileToSupabase(
        imageFile,
        fileName,
        useUserFolder: true,
      );

      return url;
    } catch (e) {
      throw Exception('Failed to capture and upload image: $e');
    }
  }

  // ===========================================================================
  // IMAGE DELETION METHODS
  // ===========================================================================

  // Delete image from Supabase Storage by file path
  Future<void> deleteImageFromSupabase(String filePath) async {
    try {
      await _supabase.storage.from('Images').remove([filePath]);
    } catch (e) {
      // Fallback to REST API if needed
      await _deleteViaRestApi('Images', filePath);
    }
  }

  // MAIN DELETE IMAGE METHOD - For compatibility with existing code
  Future<void> deleteImage(String imageUrl) async {
    try {
      if (imageUrl.isEmpty || imageUrl == 'default') {
        return; // Nothing to delete
      }

      // Check if it's a Supabase URL
      if (_isSupabaseUrl(imageUrl)) {
        await deleteImageByUrl(imageUrl);
      } else if (_isFirebaseUrl(imageUrl)) {
        // Firebase URL - log warning but don't throw
        print(
            'WARNING: Firebase Storage URL detected. Please migrate to Supabase first.');
        print('URL: $imageUrl');
        // Optionally, you could download and re-upload to Supabase here
      } else if (_isGooglePhoto(imageUrl)) {
        // Google photo - nothing to delete
        return;
      } else {
        throw Exception('Unknown storage provider for URL: $imageUrl');
      }
    } catch (e) {
      throw Exception('Failed to delete image: $e');
    }
  }

  // Delete image by URL (extracts path from URL)
  Future<void> deleteImageByUrl(String imageUrl) async {
    try {
      // Extract file path from Supabase URL
      final pattern = RegExp(r'storage/v1/object/public/Images/(.+)');
      final match = pattern.firstMatch(imageUrl);

      if (match == null || match.groupCount < 1) {
        throw Exception('Invalid Supabase image URL');
      }

      final filePath = match.group(1)!;
      await deleteImageFromSupabase(filePath);
    } catch (e) {
      throw Exception('Failed to delete image by URL: $e');
    }
  }

  // ===========================================================================
  // PROFILE IMAGE METHODS
  // ===========================================================================

  // Update user profile image in users table
  Future<void> updateUserProfileImage(String imageUrl) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in');
      }

      await _supabase
          .from('users')
          .update({'photoUrl': imageUrl}).eq('uid', user.uid);
    } catch (e) {
      throw Exception('Failed to update user profile image: $e');
    }
  }

  // Upload and set as profile image (all in one)
  Future<String> uploadProfileImage(
      Uint8List imageBytes, String fileName) async {
    try {
      // Upload to Supabase
      final imageUrl = await uploadImageToSupabase(
        imageBytes,
        fileName,
        useUserFolder: true,
      );

      // Update user profile in database
      await updateUserProfileImage(imageUrl);

      return imageUrl;
    } catch (e) {
      throw Exception('Failed to upload and set profile image: $e');
    }
  }

  // Upload and set as profile image from File
  Future<String> uploadProfileImageFile(File imageFile, String fileName) async {
    try {
      // Upload to Supabase
      final imageUrl = await uploadImageFileToSupabase(
        imageFile,
        fileName,
        useUserFolder: true,
      );

      // Update user profile in database
      await updateUserProfileImage(imageUrl);

      return imageUrl;
    } catch (e) {
      throw Exception('Failed to upload and set profile image: $e');
    }
  }

  // ===========================================================================
  // IMAGE LISTING & INFO METHODS
  // ===========================================================================

  // List user's images from Supabase
  Future<List<String>> listUserImages() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in');
      }

      final response =
          await _supabase.storage.from('Images').list(path: user.uid);

      // Get public URLs for each file
      final List<String> imageUrls = [];
      for (final file in response) {
        final publicUrl = _supabase.storage
            .from('Images')
            .getPublicUrl('${user.uid}/${file.name}');
        imageUrls.add(publicUrl);
      }

      return imageUrls;
    } catch (e) {
      throw Exception('Failed to list user images: $e');
    }
  }

  // Check if file exists in Supabase
  Future<bool> imageExists(String filePath) async {
    try {
      final response = await _supabase.storage
          .from('Images')
          .list(path: filePath.contains('/') ? filePath.split('/').first : '');

      final fileName = filePath.split('/').last;
      return response.any((file) => file.name == fileName);
    } catch (e) {
      return false;
    }
  }

  // Get image info
  Future<Map<String, dynamic>> getImageInfo(String filePath) async {
    try {
      final response = await _supabase.storage
          .from('Images')
          .list(path: filePath.contains('/') ? filePath.split('/').first : '');

      final file = response.firstWhere(
          (f) => f.name == filePath.split('/').last,
          orElse: () => throw Exception('File not found'));

      return {
        'name': file.name,
        'size': file.metadata?['size'] ?? 0,
        'mimeType': file.metadata?['mimetype'] ?? 'unknown',
        'createdAt': file.createdAt,
        'updatedAt': file.updatedAt,
      };
    } catch (e) {
      throw Exception('Failed to get image info: $e');
    }
  }

  // ===========================================================================
  // VIDEO METHODS - SUPABASE ONLY
  // ===========================================================================

  // Upload video to Supabase
  Future<String> uploadVideoToSupabase(Uint8List file, String fileName,
      {bool useUserFolder = true}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last.toLowerCase();

      // Validate it's a video
      if (!['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'].contains(extension)) {
        throw Exception(
            'Invalid video file type. Supported: mp4, mov, avi, mkv, webm, flv');
      }

      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      final String filePath;
      if (useUserFolder) {
        filePath = '${user.uid}/$uniqueFileName';
      } else {
        filePath = uniqueFileName;
      }

      final tempFile = await _createTempFile(uniqueFileName, file);

      await _supabase.storage.from('videos').upload(filePath, tempFile);

      await tempFile.delete();

      final String publicUrl =
          _supabase.storage.from('videos').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video to Supabase: $e');
    }
  }

  // Upload video from File
  Future<String> uploadVideoFileToSupabase(File videoFile, String fileName,
      {bool useUserFolder = true}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to upload video');
      }

      String extension = fileName.split('.').last.toLowerCase();

      // Validate it's a video
      if (!['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'].contains(extension)) {
        throw Exception('Invalid video file type');
      }

      final String uniqueFileName = '${const Uuid().v1()}.$extension';

      final String filePath;
      if (useUserFolder) {
        filePath = '${user.uid}/$uniqueFileName';
      } else {
        filePath = uniqueFileName;
      }

      await _supabase.storage.from('videos').upload(filePath, videoFile);

      final String publicUrl =
          _supabase.storage.from('videos').getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload video file to Supabase: $e');
    }
  }

  // Pick video from gallery and upload to Supabase
  Future<String?> pickAndUploadVideoToSupabase() async {
    try {
      // Pick video from gallery
      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (pickedFile == null) return null;

      // Get the file
      final File videoFile = File(pickedFile.path);
      final fileName = pickedFile.name;

      // Upload to Supabase
      final url = await uploadVideoFileToSupabase(
        videoFile,
        fileName,
        useUserFolder: true,
      );

      return url;
    } catch (e) {
      throw Exception('Failed to pick and upload video: $e');
    }
  }

  // MAIN DELETE VIDEO METHOD
  Future<void> deleteVideoFromSupabase(
      String bucketName, String filePath) async {
    try {
      // METHOD 1: Try standard storage API first
      try {
        final response =
            await _supabase.storage.from(bucketName).remove([filePath]);

        if (response.isNotEmpty) {
          await _verifyDeletion(bucketName, filePath);
          return;
        }
      } catch (e) {
        // Continue to next method
      }

      // METHOD 2: Try REST API with multiple endpoints
      await _deleteViaRestApi(bucketName, filePath);
    } catch (e) {
      throw Exception('Failed to delete video: $e');
    }
  }

  // Get signed URL for video
  Future<String> getSignedUrlForVideo(String fileName,
      {int expiresIn = 60}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in to get signed URL');
      }

      String actualFileName = fileName;
      if (fileName.contains('/')) {
        actualFileName = fileName.split('/').last;
      }

      final String userFolderPath = '${user.uid}/$actualFileName';

      final String signedUrl = await _supabase.storage
          .from('videos')
          .createSignedUrl(userFolderPath, expiresIn);
      return signedUrl;
    } catch (e) {
      throw Exception('Failed to get signed URL: $e');
    }
  }

  // List user's videos
  Future<List<String>> listUserVideos() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be logged in');
      }

      final response =
          await _supabase.storage.from('videos').list(path: user.uid);

      final List<String> videoFiles = [];
      for (final file in response) {
        final fileName = file.name;
        if (fileName != null && fileName is String && _isVideoFile(fileName)) {
          videoFiles.add(fileName);
        }
      }
      return videoFiles;
    } catch (e) {
      throw Exception('Failed to list user videos: $e');
    }
  }

  // Get video info
  Future<Map<String, dynamic>> getVideoInfo(String filePath) async {
    try {
      final response = await _supabase.storage
          .from('videos')
          .list(path: filePath.contains('/') ? filePath.split('/').first : '');

      final file = response.firstWhere(
          (f) => f.name == filePath.split('/').last,
          orElse: () => throw Exception('File not found'));

      return {
        'name': file.name,
        'size': file.metadata?['size'] ?? 0,
        'mimeType': file.metadata?['mimetype'] ?? 'unknown',
        'createdAt': file.createdAt,
        'updatedAt': file.updatedAt,
      };
    } catch (e) {
      throw Exception('Failed to get video info: $e');
    }
  }

  // ===========================================================================
  // HELPER METHODS
  // ===========================================================================

  // Helper method to create a temporary file
  Future<File> _createTempFile(String fileName, Uint8List data) async {
    try {
      final systemTemp = Directory.systemTemp;
      if (await systemTemp.exists()) {
        final tempFile = File('${systemTemp.path}/$fileName');
        await tempFile.writeAsBytes(data);
        return tempFile;
      }
    } catch (e) {
      // Fall through to next method
    }

    try {
      final currentDir = Directory.current;
      final tempFile = File('${currentDir.path}/$fileName');
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      // Fall through to next method
    }

    try {
      final tempFile = File(fileName);
      await tempFile.writeAsBytes(data);
      return tempFile;
    } catch (e) {
      throw Exception('Cannot create temporary file: $e');
    }
  }

  // Get MIME type from extension
  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }

  // Helper to check if file is a video
  bool _isVideoFile(String fileName) {
    final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'];
    final extension = fileName.split('.').last.toLowerCase();
    return videoExtensions.contains(extension);
  }

  // Helper to check URL types
  bool _isSupabaseUrl(String url) {
    return url.contains('supabase.co/storage');
  }

  bool _isFirebaseUrl(String url) {
    return url.contains('firebasestorage.googleapis.com');
  }

  bool _isGooglePhoto(String url) {
    return url.contains('googleusercontent.com') ||
        url.contains('lh3.googleusercontent.com');
  }

  // ===========================================================================
  // MIGRATION HELPERS
  // ===========================================================================

  // Download from Firebase and upload to Supabase
  Future<String> migrateImageToSupabase(String firebaseUrl) async {
    try {
      // Download from Firebase
      final response = await http.get(Uri.parse(firebaseUrl));
      if (response.statusCode != 200) {
        throw Exception(
            'Failed to download image from Firebase: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final fileName = firebaseUrl.split('/').last.split('?').first;

      // Upload to Supabase
      final supabaseUrl = await uploadImageToSupabase(
        Uint8List.fromList(bytes),
        fileName,
        useUserFolder: true,
      );

      return supabaseUrl;
    } catch (e) {
      throw Exception('Failed to migrate image to Supabase: $e');
    }
  }

  // ===========================================================================
  // REST API METHODS (INTERNAL)
  // ===========================================================================

  // Delete via REST API
  Future<void> _deleteViaRestApi(String bucketName, String filePath) async {
    try {
      final projectRef = 'tbiemcbqjjjsgumnjlqq';
      final anonKey =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiaWVtY2Jxampqc3VtbmpscXEiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcyODU1OTY0NywiZXhwIjoyMDQ0MTM1NjQ3fQ.0t_lxOQkF4K9cEEmhJ4w1b2q6y6q2q9Q2q9Q2q9Q2q9Q';

      final List<Map<String, dynamic>> endpoints = [
        {
          'name': 'Single file DELETE',
          'url':
              'https://$projectRef.supabase.co/storage/v1/object/$bucketName/${Uri.encodeComponent(filePath)}',
          'method': 'DELETE',
          'body': null
        },
        {
          'name': 'Batch deletion POST',
          'url':
              'https://$projectRef.supabase.co/storage/v1/object/$bucketName',
          'method': 'POST',
          'body': {
            'prefixes': [filePath]
          }
        },
      ];

      for (var endpoint in endpoints) {
        final String name = endpoint['name'] as String;
        final String url = endpoint['url'] as String;
        final String method = endpoint['method'] as String;
        final dynamic body = endpoint['body'];

        try {
          final uri = Uri.parse(url);
          final http.Response response = method == 'POST'
              ? await http.post(
                  uri,
                  headers: {
                    'Authorization': 'Bearer $anonKey',
                    'Content-Type': 'application/json',
                  },
                  body: body != null ? json.encode(body) : null,
                )
              : await http.delete(
                  uri,
                  headers: {
                    'Authorization': 'Bearer $anonKey',
                  },
                );

          if (response.statusCode == 200 || response.statusCode == 204) {
            await _verifyDeletion(bucketName, filePath);
            return;
          } else if (response.statusCode == 401) {
            throw Exception('Authentication failed - check your anon key');
          } else {
            // Continue to next endpoint
          }
        } catch (e) {
          // Continue to next endpoint
        }

        await Future.delayed(Duration(milliseconds: 500));
      }

      throw Exception('All REST API endpoints failed');
    } catch (e) {
      rethrow;
    }
  }

  // Verify deletion
  Future<void> _verifyDeletion(String bucketName, String filePath) async {
    try {
      await Future.delayed(Duration(seconds: 2));

      bool deletionVerified = false;

      // Method 1: Try to access via public URL
      try {
        final publicUrl =
            _supabase.storage.from(bucketName).getPublicUrl(filePath);
        final headResponse = await http.head(Uri.parse(publicUrl));

        if (headResponse.statusCode == 200) {
          // File still exists
        } else if (headResponse.statusCode == 404) {
          deletionVerified = true;
        } else {
          // Other status
        }
      } catch (e) {
        deletionVerified = true;
      }

      // Method 2: Check via storage API list
      if (!deletionVerified) {
        try {
          final userFolder = filePath.split('/').first;
          final files =
              await _supabase.storage.from(bucketName).list(path: userFolder);

          bool fileExists = false;
          for (final file in files) {
            final fileName = file.name;
            if (fileName != null &&
                fileName is String &&
                fileName == filePath.split('/').last) {
              fileExists = true;
              break;
            }
          }

          if (!fileExists) {
            deletionVerified = true;
          } else {
            // File still exists
          }
        } catch (e) {
          // Error checking, assume deleted
          deletionVerified = true;
        }
      }

      if (!deletionVerified) {
        print(
            'Warning: Could not verify deletion of $filePath from $bucketName');
      }
    } catch (e) {
      print('Error verifying deletion: $e');
    }
  }
}
