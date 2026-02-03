// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/screens/Profile_page/current_profile_screen.dart';
import 'package:Ratedly/screens/Profile_page/other_user_profile.dart'; // Fixed import
import 'package:Ratedly/providers/user_provider.dart';

class ProfileScreen extends StatefulWidget {
  final String uid;
  const ProfileScreen({Key? key, required this.uid}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _currentUserId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeCurrentUserId();
  }

  Future<void> _initializeCurrentUserId() async {
    try {
      // Try to get current user ID from FirebaseAuth
      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser != null) {
        setState(() {
          _currentUserId = firebaseUser.uid;
          _isLoading = false;
        });
      } else {
        // If FirebaseAuth doesn't have user, check UserProvider
        // We need to wait a bit for UserProvider to be initialized
        await Future.delayed(Duration(milliseconds: 500));

        // Use context.read to get UserProvider without listening
        // We'll get it in build method instead
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we're still loading, show loading indicator
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Get current user ID from multiple sources
    String? resolvedCurrentUserId = _currentUserId;

    if (resolvedCurrentUserId == null) {
      // Try to get from UserProvider
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      resolvedCurrentUserId =
          userProvider.firebaseUid ?? userProvider.supabaseUid;

      if (resolvedCurrentUserId == null) {
        // Last resort: try FirebaseAuth again
        final firebaseUser = FirebaseAuth.instance.currentUser;
        resolvedCurrentUserId = firebaseUser?.uid;
      }
    }

    // If we still don't have a current user ID, show error
    if (resolvedCurrentUserId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Unable to load profile',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Please try logging in again',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Validate the widget.uid parameter
    if (widget.uid.isEmpty) {
      return Center(
        child: Text('Invalid user ID'),
      );
    }

    // Determine which profile screen to show
    return widget.uid == resolvedCurrentUserId
        ? CurrentUserProfileScreen(uid: widget.uid)
        : OtherUserProfileScreen(uid: widget.uid);
  }
}
