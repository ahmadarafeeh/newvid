// RatingBar widget with improved responsive design and performance optimizations
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

class RatingBar extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double>? onRatingUpdate;
  final ValueChanged<double> onRatingEnd;
  final bool hasRated;
  final double userRating;
  final bool showSlider;
  final VoidCallback onEditRating;

  const RatingBar({
    Key? key,
    this.initialRating = 5.0,
    this.onRatingUpdate,
    required this.onRatingEnd,
    required this.hasRated,
    required this.userRating,
    required this.showSlider,
    required this.onEditRating,
  }) : super(key: key);

  @override
  State<RatingBar> createState() => _RatingBarState();
}

class _RatingBarState extends State<RatingBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late double _currentRating;
  bool _isDragging = false; // ADDED: Track dragging state

  // Cache theme colors to avoid recalculating every build
  Color? _cachedTextColor;
  Color? _cachedBackgroundColor;
  Color? _cachedSliderActiveColor;
  Color? _cachedSliderInactiveColor;
  ThemeProvider? _lastThemeProvider;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1, end: 1.1).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant RatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // CRITICAL FIX: Only update _currentRating when we're NOT dragging
    if (!_isDragging) {
      final bool sliderJustAppeared =
          widget.showSlider && !oldWidget.showSlider;

      if (sliderJustAppeared) {
        // When slider first appears, set to user's previous rating
        _currentRating = widget.userRating;
      } else if (widget.userRating != _currentRating &&
          widget.userRating != oldWidget.userRating) {
        // Only update if userRating changed from outside (not from our own drag)
        _currentRating = widget.userRating;
      }
    }
  }

  void _onRatingChanged(double newRating) {
    setState(() {
      _currentRating = newRating;
      _isDragging = true; // SET DRAGGING FLAG WHEN USER STARTS DRAGGING
    });
    widget.onRatingUpdate?.call(newRating);
    _controller.forward().then((_) => _controller.reverse());
  }

  void _onRatingEnd(double rating) {
    setState(() {
      _isDragging = false; // CLEAR DRAGGING FLAG WHEN USER STOPS DRAGGING
    });
    widget.onRatingEnd(rating);
  }

  // Cache theme colors to avoid recalculating every build
  void _updateCachedColors(ThemeProvider themeProvider) {
    if (_lastThemeProvider != themeProvider) {
      _lastThemeProvider = themeProvider;
      final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

      _cachedTextColor = isDarkMode ? const Color(0xFFd9d9d9) : Colors.black;
      _cachedBackgroundColor =
          isDarkMode ? const Color(0xFF333333) : Colors.grey[300]!;
      _cachedSliderActiveColor =
          isDarkMode ? const Color(0xFFd9d9d9) : Colors.black;
      _cachedSliderInactiveColor =
          isDarkMode ? const Color(0xFF333333) : Colors.grey[400]!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildRatingButton(ThemeProvider themeProvider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive button width with constraints - made smaller
        final double buttonWidth = (constraints.maxWidth * 0.6)
            .clamp(200.0, 250.0); // Reduced from 0.7 to 0.6 and clamp range

        return Container(
          width: buttonWidth,
          height: 40.0, // Reduced from 50.0 to 40.0
          padding:
              const EdgeInsets.symmetric(horizontal: 10.0), // Reduced from 12.0
          child: ElevatedButton(
            onPressed: () {
              widget.onEditRating();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black54,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4), // Reduced padding
              minimumSize: const Size(80, 32), // Reduced minimum size
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'You rated: ${widget.userRating.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 13, // Slightly reduced font size
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRatingSlider(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Slider(
        value: _currentRating,
        min: 1,
        max: 10,
        divisions: 100,
        label: _currentRating.toStringAsFixed(1),
        activeColor: _cachedSliderActiveColor,
        inactiveColor: _cachedSliderInactiveColor,
        onChanged: _onRatingChanged,
        onChangeEnd: _onRatingEnd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Update cached colors if theme changed
    _updateCachedColors(themeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showSlider && widget.hasRated)
          Center(
            child: _buildRatingButton(themeProvider),
          ),
        if (widget.showSlider) _buildRatingSlider(themeProvider),
      ],
    );
  }
}
