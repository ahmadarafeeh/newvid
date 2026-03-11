// RatingBar widget with animations + looping nudge + bouncing arrow
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

class _RatingBarState extends State<RatingBar> with TickerProviderStateMixin {
  // ── existing controllers ─────────────────────────────────────────────────
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  late AnimationController _sliderEntranceController;
  late Animation<double> _sliderSlide;
  late Animation<double> _sliderFade;

  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  // ── nudge: loops forever until user touches ──────────────────────────────
  // One cycle: hold 300ms → sweep right to 8.5 (400ms) → return to 5 (400ms)
  //            → pause 700ms before repeating
  late AnimationController _nudgeController;
  late Animation<double> _nudgeRating; // drives slider value
  late Animation<double> _nudgeThumbPos; // 0..1 normalised position for arrow

  // ── bouncing down-arrow ──────────────────────────────────────────────────
  late AnimationController _arrowBounceController;
  late Animation<double> _arrowBounce; // vertical offset in pixels

  // ── glow ─────────────────────────────────────────────────────────────────
  late AnimationController _nudgeGlowController;
  late Animation<double> _nudgeGlow;

  bool _isNudging = false;

  late double _currentRating;
  bool _isDragging = false;
  bool _justSubmitted = false;

  Color? _cachedSliderActiveColor;
  Color? _cachedSliderInactiveColor;
  ThemeProvider? _lastThemeProvider;

  // Slider track padding used by Flutter's Slider widget (thumb radius = 10,
  // track is inset by that on each side).
  static const double _thumbRadius = 10.0;

  // Nudge always starts/returns to the middle (5.0)
  static const double _nudgeStart = 5.0;
  static const double _nudgePeak = 8.5;

  bool get _shouldNudge => widget.showSlider && !widget.hasRated;

  // ── init ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;

    // Scale bounce
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Slider entrance
    _sliderEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sliderSlide = Tween<double>(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(parent: _sliderEntranceController, curve: Curves.easeOut),
    );
    _sliderFade = CurvedAnimation(
      parent: _sliderEntranceController,
      curve: Curves.easeIn,
    );

    // Drag pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Shimmer
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // ── Nudge (loops) ────────────────────────────────────────────────────
    // Total cycle = 1800 ms
    //   hold-start   300ms → 16.7%
    //   sweep right  400ms → 22.2%
    //   return mid   400ms → 22.2%
    //   hold-end     700ms → 38.9%
    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _nudgeRating = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(_nudgeStart),
        weight: 16.7,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: _nudgeStart, end: _nudgePeak)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22.2,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: _nudgePeak, end: _nudgeStart)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22.2,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(_nudgeStart),
        weight: 38.9,
      ),
    ]).animate(_nudgeController);

    // Normalised thumb position (0 = left, 1 = right) mirrors _nudgeRating
    // but mapped from [1..10] → [0..1].
    _nudgeThumbPos = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(_ratingToNorm(_nudgeStart)),
        weight: 16.7,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
                begin: _ratingToNorm(_nudgeStart),
                end: _ratingToNorm(_nudgePeak))
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22.2,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
                begin: _ratingToNorm(_nudgePeak),
                end: _ratingToNorm(_nudgeStart))
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 22.2,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(_ratingToNorm(_nudgeStart)),
        weight: 38.9,
      ),
    ]).animate(_nudgeController);

    _nudgeController.addListener(() {
      if (_isNudging && mounted && !_isDragging) {
        setState(() => _currentRating = _nudgeRating.value);
      }
    });

    // ── Bouncing down arrow ──────────────────────────────────────────────
    _arrowBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _arrowBounce = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _arrowBounceController, curve: Curves.easeInOut),
    );

    // ── Glow ─────────────────────────────────────────────────────────────
    _nudgeGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _nudgeGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _nudgeGlowController, curve: Curves.easeInOut),
    );

    // ── Boot ─────────────────────────────────────────────────────────────
    if (widget.showSlider) {
      _sliderEntranceController.forward().then((_) {
        if (mounted && _shouldNudge) _startNudge();
      });
    } else if (!widget.showSlider && widget.hasRated) {
      _scaleController.forward();
      _justSubmitted = true;
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) {
          _shimmerController.forward(from: 0.0).then((_) {
            if (mounted) setState(() => _justSubmitted = false);
          });
        }
      });
    }
  }

  double _ratingToNorm(double rating) => (rating - 1) / 9.0;

  void _startNudge() {
    if (_isDragging || !mounted) return;
    // Snap slider to the nudge start position (5.0 / middle)
    setState(() {
      _isNudging = true;
      _currentRating = _nudgeStart;
    });
    _nudgeGlowController.repeat(reverse: true);
    _nudgeController.repeat(); // ← loops forever until stopped
  }

  void _stopNudge() {
    _nudgeController.stop();
    _nudgeGlowController.stop();
    _nudgeGlowController.animateTo(0.0,
        duration: const Duration(milliseconds: 150));
    if (mounted) setState(() => _isNudging = false);
  }

  // ── didUpdateWidget ──────────────────────────────────────────────────────

  @override
  void didUpdateWidget(covariant RatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.showSlider && !oldWidget.showSlider) {
      _sliderEntranceController.forward(from: 0.0).then((_) {
        if (mounted && _shouldNudge) _startNudge();
      });
      if (!_isDragging) {
        _currentRating =
            widget.userRating > 0 ? widget.userRating : widget.initialRating;
      }
    }

    if (!widget.showSlider && oldWidget.showSlider) {
      _stopNudge();
      _scaleController.forward(from: 0.0);
      _justSubmitted = true;
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) {
          _shimmerController.forward(from: 0.0).then((_) {
            if (mounted) setState(() => _justSubmitted = false);
          });
        }
      });
    }

    if (!_isDragging && !_isNudging) {
      if (widget.userRating != oldWidget.userRating) {
        _currentRating = widget.userRating;
      }
    }
  }

  // ── interaction ──────────────────────────────────────────────────────────

  void _onRatingChanged(double newRating) {
    if (_isNudging) _stopNudge();
    setState(() {
      _currentRating = newRating;
      _isDragging = true;
    });
    widget.onRatingUpdate?.call(newRating);
    _pulseController.forward(from: 0.0).then((_) => _pulseController.reverse());
  }

  void _onRatingEnd(double rating) {
    setState(() => _isDragging = false);
    widget.onRatingEnd(rating);
  }

  // ── colors ───────────────────────────────────────────────────────────────

  void _updateCachedColors(ThemeProvider themeProvider) {
    if (_lastThemeProvider != themeProvider) {
      _lastThemeProvider = themeProvider;
      final isDark = themeProvider.themeMode == ThemeMode.dark;
      _cachedSliderActiveColor =
          isDark ? const Color(0xFFd9d9d9) : Colors.black;
      _cachedSliderInactiveColor =
          isDark ? const Color(0xFF333333) : Colors.grey[400]!;
    }
  }

  // ── dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _scaleController.dispose();
    _sliderEntranceController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    _nudgeController.dispose();
    _arrowBounceController.dispose();
    _nudgeGlowController.dispose();
    super.dispose();
  }

  // ── "You rated" button ───────────────────────────────────────────────────

  Widget _buildRatingButton() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double buttonWidth =
              (constraints.maxWidth * 0.6).clamp(200.0, 250.0);
          return Container(
            width: buttonWidth,
            height: 40.0,
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child:
                _justSubmitted ? _buildShimmerButton() : _buildStaticButton(),
          );
        },
      ),
    );
  }

  Widget _buildStaticButton() {
    return ElevatedButton(
      onPressed: widget.onEditRating,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black54,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(80, 32),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'You rated: ${widget.userRating.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerButton() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                child!,
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: 0.4,
                    alignment: Alignment(_shimmerAnimation.value, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: Center(
        child: Text(
          'You rated: ${widget.userRating.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }

  // ── Slider ───────────────────────────────────────────────────────────────

  Widget _buildRatingSlider(ThemeProvider themeProvider) {
    return AnimatedBuilder(
      animation: _sliderEntranceController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _sliderSlide.value),
          child: Opacity(
            opacity: _sliderFade.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── "Slide to rate" hint (original pulsing-dot style) ─────────
            AnimatedOpacity(
              opacity: _isNudging ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
                child: AnimatedBuilder(
                  animation: _nudgeGlow,
                  builder: (context, _) {
                    final glow = _nudgeGlow.value;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9 + 0.1 * glow),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.35 * glow),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black
                                      .withOpacity(0.5 + 0.5 * glow),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withOpacity(0.2 * glow),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Slide to rate',
                                style: TextStyle(
                                  color: Colors.black
                                      .withOpacity(0.75 + 0.25 * glow),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Inter',
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ── Slider + bouncing arrow overlay ───────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth - _thumbRadius * 2;

                return AnimatedBuilder(
                  animation:
                      Listenable.merge([_nudgeGlow, _arrowBounceController]),
                  builder: (context, child) {
                    // Arrow horizontal position tracks thumb
                    final thumbX = _isNudging
                        ? _thumbRadius + _nudgeThumbPos.value * trackWidth
                        : _thumbRadius +
                            _ratingToNorm(_currentRating) * trackWidth;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        child!, // the slider itself

                        // Bouncing ↓ arrow above thumb, only while nudging
                        if (_isNudging)
                          Positioned(
                            top: -22 - _arrowBounce.value,
                            left: thumbX - 24,
                            child: Material(
                              type: MaterialType.transparency,
                              child: IgnorePointer(
                                child: AnimatedBuilder(
                                  animation: _nudgeGlow,
                                  builder: (_, __) => Transform(
                                    alignment: Alignment.center,
                                    transform:
                                        Matrix4.diagonal3Values(1.0, 2.2, 1.0),
                                    child: Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 48,
                                      color: Colors.white.withOpacity(
                                          0.6 + 0.4 * _nudgeGlow.value),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  child: Container(
                    decoration: _isNudging
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white
                                    .withOpacity(0.07 * _nudgeGlow.value),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          )
                        : const BoxDecoration(),
                    child: Slider(
                      value: _currentRating,
                      min: 1,
                      max: 10,
                      divisions: 100,
                      label: _currentRating.toStringAsFixed(1),
                      activeColor: _isNudging
                          ? (_cachedSliderActiveColor ?? Colors.white)
                              .withOpacity(0.85)
                          : _cachedSliderActiveColor,
                      inactiveColor: _cachedSliderInactiveColor,
                      onChanged: _onRatingChanged,
                      onChangeEnd: _onRatingEnd,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    _updateCachedColors(themeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: !widget.showSlider && widget.hasRated
              ? Center(
                  key: const ValueKey('button'),
                  child: _buildRatingButton(),
                )
              : widget.showSlider
                  ? SizedBox(
                      key: const ValueKey('slider'),
                      width: double.infinity,
                      child: _buildRatingSlider(themeProvider),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
        ),
      ],
    );
  }
}
