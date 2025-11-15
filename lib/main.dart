import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';
import 'package:Ratedly/resources/profile_firestore_methods.dart';
import 'package:Ratedly/screens/signup/auth_wrapper.dart';
import 'package:Ratedly/utils/colors.dart';
import 'package:Ratedly/services/analytics_service.dart';
import 'package:Ratedly/services/notification_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const bool useDebugHome = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🚀 ULTRA-FAST: Start app INSTANTLY without waiting for anything
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );

  // 🚀 BACKGROUND: Initialize everything after UI is visible
  _initializeEverythingInBackground();
}

// 🚀 NEW: Everything happens after UI renders
Future<void> _initializeEverythingInBackground() async {
  try {
    // 1. Firebase - essential but non-blocking
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyAFpbPiK6u8KMIfob0pu44ca8YLGYKJHDk",
          authDomain: "rateapp-3b78e.firebaseapp.com",
          projectId: "rateapp-3b78e",
          storageBucket: "rateapp-3b78e.appspot.com",
          messagingSenderId: "411393947451",
          appId: "1:411393947451:web:62e5c1b57a3c7a66da691e",
          measurementId: "G-JSXVSH5PB8",
        ),
      );
    } else {
      await Firebase.initializeApp();
    }

    // 2. Supabase - non-blocking
    unawaited(Supabase.initialize(
      url: 'https://tbiemcbqjjjsgumnjlqq.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiaWVtY2Jxampqc2d1bW5qbHFxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMTQ2NjQsImV4cCI6MjA2OTg5MDY2NH0.JAgFU3fDBGAlMFuHQDqiu35GFe-QYMJfoaIc3mI26yM',
    ));

    // 3. Mobile Ads - lowest priority
    if (!kIsWeb) {
      unawaited(MobileAds.instance.initialize());
    }

    // 4. Other services - don't even await
    if (!kIsWeb) {
      unawaited(AnalyticsService.init());
      unawaited(NotificationService().init());
    }
  } catch (e) {
    // Complete silence - user should never know
  }
}

// 🚀 Helper to completely ignore futures
void unawaited(Future<void> future) {
  // Absolutely nothing - let it complete in void
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        Provider(create: (_) => SupabaseProfileMethods(), lazy: true),
        Provider(create: (_) => NotificationService(), lazy: true),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Ratedly',

        // 🚀 CRITICAL: Disable ALL debug features
        checkerboardOffscreenLayers: false,
        checkerboardRasterCacheImages: false,
        showPerformanceOverlay: false,
        debugShowMaterialGrid: false,

        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.grey[100],
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: primaryColor,
            unselectedItemColor: Colors.grey[600],
            selectedLabelStyle: const TextStyle(color: primaryColor),
            unselectedLabelStyle: TextStyle(color: Colors.grey[600]),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
          ),
        ),
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: mobileBackgroundColor,
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: mobileBackgroundColor,
            selectedItemColor: primaryColor,
            unselectedItemColor: Colors.grey[600],
            selectedLabelStyle: const TextStyle(color: primaryColor),
            unselectedLabelStyle: TextStyle(color: Colors.grey[600]),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
          ),
        ),
        themeMode: themeProvider.themeMode,
        home: useDebugHome
            ? const DebugHome()
            : const OrientationPersistentWrapper(),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, color: Colors.red, size: 64),
              SizedBox(height: 20),
              Text('App initialization failed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                    'Please check your internet connection and try again.',
                    textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrientationPersistentWrapper extends StatefulWidget {
  const OrientationPersistentWrapper({super.key});

  @override
  State<OrientationPersistentWrapper> createState() =>
      _OrientationPersistentWrapperState();
}

class _OrientationPersistentWrapperState
    extends State<OrientationPersistentWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setSystemUIOverlayStyle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _setSystemUIOverlayStyle();
    super.didChangeMetrics();
  }

  void _setSystemUIOverlayStyle() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          isDarkMode ? const Color(0xFF121212) : Colors.white,
      systemNavigationBarIconBrightness:
          isDarkMode ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _setSystemUIOverlayStyle());
    return const AuthWrapper();
  }
}

class DebugHome extends StatefulWidget {
  const DebugHome({Key? key}) : super(key: key);

  @override
  State<DebugHome> createState() => _DebugHomeState();
}

class _DebugHomeState extends State<DebugHome> {
  final SupabaseClient _supabase = Supabase.instance.client;
  String _msg = 'starting...';

  @override
  void initState() {
    super.initState();
    _checkSupabase();
  }

  Future<void> _checkSupabase() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      debugPrint('DebugHome: firebase currentUser = $firebaseUser');
      setState(() => _msg = 'Firebase UID: ${firebaseUser?.uid ?? "null"}');

      final resp =
          await _supabase.from('posts').select('postId').limit(1).maybeSingle();

      debugPrint('Supabase response: $resp');

      setState(
          () => _msg = 'Supabase query result: ${resp?.toString() ?? "null"}');
    } catch (e, st) {
      debugPrint('DebugHome error: $e\n$st');
      setState(() => _msg = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Supabase + Firebase'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _msg,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
