import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerifiedUsernameWidget extends StatelessWidget {
  final String username;
  final String uid;
  final TextStyle? style;
  final bool showVerification;

  const VerifiedUsernameWidget({
    Key? key,
    required this.username,
    required this.uid,
    this.style,
    this.showVerification = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!showVerification) {
      return Text(username, style: style);
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchUserVerification(uid),
      builder: (context, snapshot) {
        final isVerified = snapshot.data?['isVerified'] == true;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(username, style: style),
            if (isVerified) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.verified,
                color: Colors.blue,
                size: (style?.fontSize ?? 14) * 0.9,
              ),
            ],
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _fetchUserVerification(String uid) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('isVerified')
          .eq('uid', uid)
          .single();
      return response;
    } catch (e) {
      return null;
    }
  }
}

// Cached version for better performance in lists
class CachedVerifiedUsernameWidget extends StatelessWidget {
  final String username;
  final bool isVerified;
  final TextStyle? style;

  const CachedVerifiedUsernameWidget({
    Key? key,
    required this.username,
    required this.isVerified,
    this.style,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(username, style: style),
        if (isVerified) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified,
            color: Colors.blue,
            size: (style?.fontSize ?? 14) * 0.9,
          ),
        ],
      ],
    );
  }
}
