// country_flag_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:country_code_picker/country_code_picker.dart';

class CountryFlagScreen extends StatefulWidget {
  const CountryFlagScreen({Key? key}) : super(key: key);

  @override
  State<CountryFlagScreen> createState() => _CountryFlagScreenState();
}

class _CountryFlagScreenState extends State<CountryFlagScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _selectedCountryCode;
  String? _selectedCountryName;

  @override
  void initState() {
    super.initState();
    _loadCurrentCountry();
  }

  Future<void> _loadCurrentCountry() async {
    try {
      final response = await _supabase
          .from('users')
          .select('country')
          .eq('uid', FirebaseAuth.instance.currentUser!.uid)
          .single();

      if (mounted) {
        final dbCountry = response['country'];
        setState(() {
          _selectedCountryCode =
              (dbCountry == null || dbCountry == '') ? null : dbCountry;
        });
      }
    } catch (e) {
      debugPrint('Error loading current country: $e');
    }
  }

  Future<void> _updateCountry(String countryCode, String countryName) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // First check if the column exists by trying to update
      final response = await _supabase
          .from('users')
          .update({'country': countryCode}).eq('uid', currentUserId);

      if (mounted) {
        setState(() {
          _selectedCountryCode = countryCode;
          _selectedCountryName = countryName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Country updated to $countryName'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back after successful update
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error updating country: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update country: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(
          'Display Country Flag',
          style: TextStyle(
            color: const Color(0xFFd9d9d9),
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: const Color(0xFFd9d9d9),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              Image.asset(
                'assets/logo/22.png',
                width: 100,
                height: 100,
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Select Your Country',
                style: TextStyle(
                  color: Color(0xFFd9d9d9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Improved Country Picker Container
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF444444),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: CountryCodePicker(
                    onChanged: (CountryCode countryCode) {
                      _updateCountry(countryCode.code!, countryCode.name!);
                    },
                    initialSelection: _selectedCountryCode ?? '',
                    favorite: ['US', 'GB', 'CA', 'AU', 'DE', 'FR'],
                    countryFilter: const [],
                    showCountryOnly: true,
                    showOnlyCountryWhenClosed: true,
                    alignLeft: false,
                    backgroundColor: const Color(0xFF1E1E1E),
                    textStyle: const TextStyle(
                      color: Color(0xFFd9d9d9),
                      fontFamily: 'Montserrat',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    dialogBackgroundColor: const Color(0xFF121212),
                    dialogTextStyle: const TextStyle(
                      color: Color(0xFFd9d9d9),
                      fontFamily: 'Montserrat',
                    ),
                    searchDecoration: const InputDecoration(
                      hintText: 'Search country...',
                      hintStyle: TextStyle(
                        color: Color(0xFF888888),
                        fontFamily: 'Montserrat',
                      ),
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Color(0xFF1E1E1E),
                      prefixIcon: Icon(Icons.search, color: Color(0xFF888888)),
                    ),
                    searchStyle: const TextStyle(
                      color: Color(0xFFd9d9d9),
                      fontFamily: 'Montserrat',
                    ),
                    builder: (CountryCode? country) {
                      final showPlaceholder = _selectedCountryCode == null;

                      return Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            // Icon/Flag Section
                            Container(
                              width: 40,
                              height: 30,
                              decoration: BoxDecoration(
                                color: showPlaceholder
                                    ? const Color(0xFF333333)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: showPlaceholder
                                    ? Border.all(
                                        color: const Color(0xFF444444),
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: Center(
                                child: showPlaceholder
                                    ? const Icon(
                                        Icons.public,
                                        size: 18,
                                        color: Color(0xFFd9d9d9),
                                      )
                                    : (country != null &&
                                            country.flagUri != null)
                                        ? Image.asset(
                                            country.flagUri!,
                                            package: 'country_code_picker',
                                            width: 28,
                                            height: 21,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF222222),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Text Section
                            Expanded(
                              child: showPlaceholder
                                  ? const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Choose a country',
                                          style: TextStyle(
                                            color: Color(0xFFd9d9d9),
                                            fontSize: 16,
                                            fontFamily: 'Montserrat',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Tap to select your country',
                                          style: TextStyle(
                                            color: Color(0xFFb0b0b0),
                                            fontSize: 12,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          country?.name ??
                                              _selectedCountryName ??
                                              _selectedCountryCode ??
                                              '',
                                          style: const TextStyle(
                                            color: Color(0xFFd9d9d9),
                                            fontSize: 16,
                                            fontFamily: 'Montserrat',
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Selected country',
                                          style: TextStyle(
                                            color: Color(0xFFb0b0b0),
                                            fontSize: 12,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ],
                                    ),
                            ),

                            // Dropdown Icon
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF333333),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.arrow_drop_down,
                                color: Color(0xFFd9d9d9),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Continue Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF333333),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(double.infinity, 56),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.3),
                ),
                onPressed: () {
                  if (_selectedCountryCode != null) {
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a country first'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Montserrat',
                        ),
                      ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
