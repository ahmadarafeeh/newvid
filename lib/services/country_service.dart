import 'dart:async';
import 'package:country_detector/country_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

class CountryService {
  // Keys for SharedPreferences
  static const String _lastCheckKey = 'last_country_check_';
  static const String _countryUpdateEnabledKey = 'country_update_enabled';

  // Configuration
  static const int _checkIntervalDays = 3; // Check every 3 days
  static const int _millisecondsInDay = 24 * 60 * 60 * 1000;

  // Singleton instance
  static CountryService? _instance;
  factory CountryService() {
    _instance ??= CountryService._internal();
    return _instance!;
  }

  CountryService._internal();

  // Service dependencies
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final CountryDetector _detector = CountryDetector();
  SharedPreferences? _prefs;

  // Initialize SharedPreferences
  Future<void> _initPrefs() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  // ========================
  // MAIN PUBLIC METHODS
  // ========================

  // Check and update country if 3 days have passed
  Future<void> checkAndUpdateCountryIfNeeded() async {
    try {
      await _initPrefs();

      final user = _auth.currentUser;
      if (user == null) {
        print('CountryService: No user logged in');
        return;
      }

      // Check if feature is enabled
      final isEnabled = _prefs!.getBool(_countryUpdateEnabledKey) ?? true;
      if (!isEnabled) {
        print('CountryService: Country updates disabled by user');
        return;
      }

      final userId = user.uid;
      final lastCheckKey = '$_lastCheckKey$userId';
      final lastCheckTime = _prefs!.getInt(lastCheckKey) ?? 0;
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      // Calculate days since last check
      final daysSinceLastCheck =
          (currentTime - lastCheckTime) / _millisecondsInDay;

      if (daysSinceLastCheck >= _checkIntervalDays) {
        print(
            'CountryService: Checking country - $daysSinceLastCheck days since last check');
        await _updateCountryForUser(userId);

        // Update last check time
        await _prefs!.setInt(lastCheckKey, currentTime);
        print('CountryService: Country check completed');
      } else {
        print(
            'CountryService: Skipping country check - only $daysSinceLastCheck days since last check');
      }
    } catch (e) {
      print('CountryService error in checkAndUpdateCountryIfNeeded: $e');
    }
  }

  // Force update country immediately (for manual refresh)
  Future<void> forceUpdateCountry() async {
    try {
      await _initPrefs();

      final user = _auth.currentUser;
      if (user == null) return;

      final userId = user.uid;
      await _updateCountryForUser(userId);

      // Update last check time
      final lastCheckKey = '$_lastCheckKey$userId';
      await _prefs!.setInt(lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('CountryService error in forceUpdateCountry: $e');
    }
  }

  // Set up timer for existing users with country
  Future<void> setupCountryTimer(String userId) async {
    try {
      await _initPrefs();

      // Set initial check time (now)
      final lastCheckKey = '$_lastCheckKey$userId';
      await _prefs!.setInt(lastCheckKey, DateTime.now().millisecondsSinceEpoch);

      // Enable country updates by default
      await _prefs!.setBool(_countryUpdateEnabledKey, true);

      print('CountryService: Timer setup for user $userId');
    } catch (e) {
      print('CountryService error in setupCountryTimer: $e');
    }
  }

  // Set country for user (call this from completeProfile)
  Future<void> setCountryForUser(String userId) async {
    try {
      // Detect country
      final String? countryCode = await _detectCurrentCountry();

      if (countryCode != null) {
        // Update database
        await _supabase
            .from('users')
            .update({'country': countryCode}).eq('uid', userId);

        print('CountryService: Set country $countryCode for user $userId');

        // Set up the timer
        await setupCountryTimer(userId);
      } else {
        print('CountryService: Could not detect country for user $userId');
      }
    } catch (e) {
      print('CountryService error in setCountryForUser: $e');
    }
  }

  // Backfill country for existing users who completed onboarding
  Future<void> backfillCountryForOnboardedUsers() async {
    try {
      await _initPrefs();

      final user = _auth.currentUser;
      if (user == null) return;

      final userId = user.uid;

      // Check if user has completed onboarding but doesn't have country
      final userData = await _supabase
          .from('users')
          .select('onboardingComplete, country, username')
          .eq('uid', userId)
          .maybeSingle();

      if (userData != null) {
        final bool onboardingComplete = userData['onboardingComplete'] == true;
        final bool hasUsername = userData['username'] != null &&
            userData['username'].toString().isNotEmpty;
        final String? currentCountry = userData['country'] as String?;

        // If user has completed onboarding (has username) but no country
        if (onboardingComplete && hasUsername && currentCountry == null) {
          print(
              'CountryService: Backfilling country for onboarded user $userId');
          await setCountryForUser(userId);
        }
      }
    } catch (e) {
      print('Error in backfillCountryForOnboardedUsers: $e');
    }
  }

  // Get time until next check (for debugging/UI)
  Future<Duration> getTimeUntilNextCheck() async {
    try {
      await _initPrefs();

      final user = _auth.currentUser;
      if (user == null) return Duration.zero;

      final lastCheckKey = '$_lastCheckKey${user.uid}';
      final lastCheckTime = _prefs!.getInt(lastCheckKey) ?? 0;
      final nextCheckTime =
          lastCheckTime + (_checkIntervalDays * _millisecondsInDay);
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      if (currentTime >= nextCheckTime) {
        return Duration.zero;
      } else {
        return Duration(milliseconds: nextCheckTime - currentTime);
      }
    } catch (e) {
      return Duration.zero;
    }
  }

  // Enable/disable country updates
  Future<void> setCountryUpdatesEnabled(bool enabled) async {
    try {
      await _initPrefs();
      await _prefs!.setBool(_countryUpdateEnabledKey, enabled);
    } catch (e) {
      print('CountryService error in setCountryUpdatesEnabled: $e');
    }
  }

  // Check if country updates are enabled
  Future<bool> areCountryUpdatesEnabled() async {
    try {
      await _initPrefs();
      return _prefs!.getBool(_countryUpdateEnabledKey) ?? true;
    } catch (e) {
      return true;
    }
  }

  // Reset the check timer (for debugging)
  Future<void> resetCheckTimer() async {
    try {
      await _initPrefs();

      final user = _auth.currentUser;
      if (user == null) return;

      final lastCheckKey = '$_lastCheckKey${user.uid}';
      await _prefs!.remove(lastCheckKey);
    } catch (e) {
      print('CountryService error in resetCheckTimer: $e');
    }
  }

  // ========================
  // PRIVATE HELPER METHODS
  // ========================

  // Core country detection and update logic
  Future<void> _updateCountryForUser(String userId) async {
    try {
      // Detect current country
      final String? newCountryCode = await _detectCurrentCountry();

      if (newCountryCode == null) {
        print('CountryService: Could not detect country');
        return;
      }

      // Get current country from database
      final currentData = await _supabase
          .from('users')
          .select('country')
          .eq('uid', userId)
          .maybeSingle();

      final String? currentCountry = currentData?['country'] as String?;

      // Only update if country has changed or is null
      if (currentCountry == null || currentCountry != newCountryCode) {
        print(
            'CountryService: Updating country from $currentCountry to $newCountryCode');

        await _supabase
            .from('users')
            .update({'country': newCountryCode}).eq('uid', userId);

        print('CountryService: Country updated successfully');
      } else {
        print('CountryService: Country unchanged: $currentCountry');
      }
    } catch (e) {
      print('CountryService error in _updateCountryForUser: $e');
    }
  }

  // Country detection with fallback
  Future<String?> _detectCurrentCountry() async {
    try {
      final countryCode = await _detector.isoCountryCode();

      // Validate the country code
      if (countryCode != null &&
          countryCode.isNotEmpty &&
          countryCode != "--") {
        return countryCode;
      }

      // Fallback: Try all detection sources
      final allCodes = await _detector.detectAll();
      final sources = [
        allCodes.sim,
        allCodes.network,
        allCodes.locale,
      ];

      for (final code in sources) {
        if (code != null && code.isNotEmpty && code != "--") {
          return code;
        }
      }

      return null;
    } catch (e) {
      print('CountryService error in _detectCurrentCountry: $e');
      return null;
    }
  }

  // Get last check time for debugging
  Future<DateTime?> getLastCheckTime() async {
    try {
      await _initPrefs();

      final user = _auth.currentUser;
      if (user == null) return null;

      final lastCheckKey = '$_lastCheckKey${user.uid}';
      final lastCheckTime = _prefs!.getInt(lastCheckKey) ?? 0;

      if (lastCheckTime == 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(lastCheckTime);
    } catch (e) {
      return null;
    }
  }
}
