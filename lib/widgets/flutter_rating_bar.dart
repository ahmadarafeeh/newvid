// RatingBar widget with animations + looping nudge + bouncing arrow
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Ratedly/providers/user_provider.dart';
import 'package:Ratedly/utils/theme_provider.dart';

// ── Custom thumb that renders the 👆 emoji + bouncing arrow above it ─────────
class _EmojiThumbShape extends SliderComponentShape {
  final String emoji;
  final double size;
  final double arrowBounce;
  final double arrowOpacity;
  final bool showArrow;

  const _EmojiThumbShape({
    this.emoji = '👆',
    this.size = 30.0,
    this.arrowBounce = 0.0,
    this.arrowOpacity = 0.0,
    this.showArrow = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    if (showArrow && arrowOpacity > 0) {
      const arrowSize = 48.0;
      const arrowScaleY = 2.2;
      const arrowH = arrowSize * arrowScaleY;
      final arrowTop = center.dy - size / 2 - arrowH - 8 - arrowBounce;
      final arrowCenter = Offset(center.dx, arrowTop + arrowH / 2);

      final arrowPainter = TextPainter(
        text: TextSpan(
          text: '↓',
          style: TextStyle(
            fontSize: arrowSize,
            height: 1.0,
            color: Colors.white.withOpacity(arrowOpacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(arrowCenter.dx, arrowCenter.dy);
      canvas.scale(1.0, arrowScaleY);
      canvas.translate(-arrowCenter.dx, -arrowCenter.dy);
      arrowPainter.paint(
        canvas,
        Offset(arrowCenter.dx - arrowPainter.width / 2,
            arrowCenter.dy - arrowPainter.height / 2),
      );
      canvas.restore();
    }

    final tp = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: size, height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
}

class RatingBar extends StatefulWidget {
  final double initialRating;
  final ValueChanged<double>? onRatingUpdate;
  final ValueChanged<double> onRatingEnd;
  final bool hasRated;
  final double userRating;
  final bool showSlider;
  final VoidCallback onEditRating;

  /// Optional override from parent.  When null (default) the widget
  /// self-resolves guidance by querying Supabase.
  final bool? showGuidance;

  const RatingBar({
    Key? key,
    this.initialRating = 5.0,
    this.onRatingUpdate,
    required this.onRatingEnd,
    required this.hasRated,
    required this.userRating,
    required this.showSlider,
    required this.onEditRating,
    this.showGuidance,        // nullable — null means "auto-detect"
  }) : super(key: key);

  @override
  State<RatingBar> createState() => _RatingBarState();
}

class _RatingBarState extends State<RatingBar> with TickerProviderStateMixin {
  // ── guidance (self-resolved) ─────────────────────────────────────────────
  /// True once we've finished loading, so we don't start nudging on a stale false.
  bool _guidanceLoaded = false;
  bool _resolvedGuidance = false;        // set by _loadGuidanceFlag()

  bool get _effectiveShowGuidance =>
      widget.showGuidance ?? _resolvedGuidance;

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

  late AnimationController _nudgeController;
  late Animation<double> _nudgeRating;
  late Animation<double> _nudgeThumbPos;

  late AnimationController _arrowBounceController;
  late Animation<double> _arrowBounce;

  late AnimationController _nudgeGlowController;
  late Animation<double> _nudgeGlow;

  late AnimationController _iconWiggleController;
  late Animation<double> _iconWiggle;

  bool _isNudging = false;
  late double _currentRating;
  bool _isDragging = false;
  bool _justSubmitted = false;

  Color? _cachedSliderActiveColor;
  Color? _cachedSliderInactiveColor;
  ThemeProvider? _lastThemeProvider;

  static const double _nudgeStart = 5.0;
  static const double _nudgePeak = 8.5;

  bool get _shouldNudge =>
      widget.showSlider && !widget.hasRated && _effectiveShowGuidance;

  // ── init ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;

    _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _scaleAnimation = CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut);

    _sliderEntranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _sliderSlide = Tween<double>(begin: 12.0, end: 0.0).animate(
        CurvedAnimation(parent: _sliderEntranceController, curve: Curves.easeOut));
    _sliderFade = CurvedAnimation(parent: _sliderEntranceController, curve: Curves.easeIn);

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _pulseScale = Tween<double>(begin: 1.0, end: 1.18).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    _shimmerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
        CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut));

    _nudgeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _nudgeRating = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(_nudgeStart), weight: 16.7),
      TweenSequenceItem(
          tween: Tween<double>(begin: _nudgeStart, end: _nudgePeak)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22.2),
      TweenSequenceItem(
          tween: Tween<double>(begin: _nudgePeak, end: _nudgeStart)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22.2),
      TweenSequenceItem(tween: ConstantTween<double>(_nudgeStart), weight: 38.9),
    ]).animate(_nudgeController);

    _nudgeThumbPos = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(_ratingToNorm(_nudgeStart)), weight: 16.7),
      TweenSequenceItem(
          tween: Tween<double>(begin: _ratingToNorm(_nudgeStart), end: _ratingToNorm(_nudgePeak))
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22.2),
      TweenSequenceItem(
          tween: Tween<double>(begin: _ratingToNorm(_nudgePeak), end: _ratingToNorm(_nudgeStart))
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22.2),
      TweenSequenceItem(tween: ConstantTween<double>(_ratingToNorm(_nudgeStart)), weight: 38.9),
    ]).animate(_nudgeController);

    _nudgeController.addListener(() {
      if (_isNudging && mounted && !_isDragging) {
        setState(() => _currentRating = _nudgeRating.value);
      }
    });

    _arrowBounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _arrowBounce = Tween<double>(begin: 0.0, end: 10.0).animate(
        CurvedAnimation(parent: _arrowBounceController, curve: Curves.easeInOut));

    _nudgeGlowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _nudgeGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _nudgeGlowController, curve: Curves.easeInOut));

    _iconWiggleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _iconWiggle = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 16.7),
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.0, end: 5.0).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22.2),
      TweenSequenceItem(
          tween: Tween<double>(begin: 5.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 22.2),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 38.9),
    ]).animate(_iconWiggleController);

    // ── Boot ─────────────────────────────────────────────────────────────
    if (widget.showSlider) {
      // Run entrance anim, then load guidance flag, then maybe start nudge.
      _sliderEntranceController.forward().then((_) {
        if (mounted) _loadGuidanceFlag();
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

  // ── Guidance flag loader (self-contained, no parent needed) ──────────────

  Future<void> _loadGuidanceFlag() async {
    // If parent already overrides, skip the DB query.
    if (widget.showGuidance != null) {
      setState(() => _guidanceLoaded = true);
      if (_shouldNudge) _startNudge();
      return;
    }

    try {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) return;

      final supabase = Supabase.instance.client;

      // 1. Check if user is in the test group (test = true → threshold 3, false → 1)
      final userRow = await supabase
          .from('users')
          .select('test')
          .eq('uid', user.uid)
          .maybeSingle();

      final bool isTestGroup = userRow?['test'] ?? true; // default to test group
      final int threshold = isTestGroup ? 3 : 1;

      // 2. Count how many ratings this user has submitted
      final ratingsRes = await supabase
          .from('post_rating')
          .select('userid')
          .eq('userid', user.uid);

      final int ratingCount = (ratingsRes as List).length;

      if (!mounted) return;

      final bool shouldShow = ratingCount < threshold;
      setState(() {
        _resolvedGuidance = shouldShow;
        _guidanceLoaded = true;
      });

      if (_shouldNudge) _startNudge();
    } catch (_) {
      // On any error fall back to showing guidance (safer for new users)
      if (mounted) {
        setState(() {
          _resolvedGuidance = true;
          _guidanceLoaded = true;
        });
        if (_shouldNudge) _startNudge();
      }
    }
  }

  double _ratingToNorm(double rating) => (rating - 1) / 9.0;

  void _startNudge() {
    if (_isDragging || !mounted) return;
    setState(() {
      _isNudging = true;
      _currentRating = _nudgeStart;
    });
    _nudgeGlowController.repeat(reverse: true);
    _nudgeController.repeat();
    _iconWiggleController.repeat();
  }

  void _stopNudge() {
    _nudgeController.stop();
    _nudgeGlowController.stop();
    _iconWiggleController.stop();
    _nudgeGlowController.animateTo(0.0, duration: const Duration(milliseconds: 150));
    if (mounted) setState(() => _isNudging = false);
  }

  // ── didUpdateWidget ──────────────────────────────────────────────────────

  @override
  void didUpdateWidget(covariant RatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.showSlider && !oldWidget.showSlider) {
      _sliderEntranceController.forward(from: 0.0).then((_) {
        if (mounted) {
          if (_guidanceLoaded) {
            if (_shouldNudge) _startNudge();
          } else {
            _loadGuidanceFlag();
          }
        }
      });
      if (!_isDragging) {
        _currentRating = widget.userRating > 0 ? widget.userRating : widget.initialRating;
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

    // Re-check guidance if onRatingEnd just fired (rating count changed)
    if (widget.hasRated && !oldWidget.hasRated && widget.showGuidance == null) {
      _loadGuidanceFlag();
    }
  }

  // ── interaction ──────────────────────────────────────────────────────────

  void _onRatingChanged(double newRating) {
    if (_isNudging) _stopNudge();
    setState(() { _currentRating = newRating; _isDragging = true; });
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
      _cachedSliderActiveColor = isDark ? const Color(0xFFd9d9d9) : Colors.black;
      _cachedSliderInactiveColor = isDark ? const Color(0xFF333333) : Colors.grey[400]!;
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
    _iconWiggleController.dispose();
    super.dispose();
  }

  // ── "You rated" button ───────────────────────────────────────────────────

  Widget _buildRatingButton() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double buttonWidth = (constraints.maxWidth * 0.6).clamp(200.0, 250.0);
          return Container(
            width: buttonWidth,
            height: 40.0,
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: _justSubmitted ? _buildShimmerButton() : _buildStaticButton(),
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
          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
        ),
      ),
    );
  }

  Widget _buildShimmerButton() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
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
                          colors: [Colors.transparent, Colors.white.withOpacity(0.25), Colors.transparent],
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
          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
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
          child: Opacity(opacity: _sliderFade.value.clamp(0.0, 1.0), child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── "Slide to rate" hint ─────────────────────────────────────
            AnimatedOpacity(
              opacity: _isNudging ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
                child: AnimatedBuilder(
                  animation: _nudgeGlow,
                  builder: (context, _) {
                    final glow = _nudgeGlow.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9 + 0.1 * glow),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.white.withOpacity(0.35 * glow), blurRadius: 10, spreadRadius: 1),
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
                              color: Colors.black.withOpacity(0.5 + 0.5 * glow),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2 * glow), blurRadius: 4, spreadRadius: 1)],
                            ),
                          ),
                          Text(
                            'Slide to rate',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.75 + 0.25 * glow),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Slider ───────────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: Listenable.merge([_nudgeGlow, _arrowBounceController, _nudgeController]),
                  builder: (context, child) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: _effectiveShowGuidance
                            ? _EmojiThumbShape(
                                emoji: '👆',
                                size: 30.0,
                                showArrow: _isNudging && _effectiveShowGuidance,
                                arrowBounce: _arrowBounce.value,
                                arrowOpacity: (_isNudging && _effectiveShowGuidance)
                                    ? 0.6 + 0.4 * _nudgeGlow.value
                                    : 0.0,
                              )
                            : const RoundSliderThumbShape(enabledThumbRadius: 10.0),
                        overlayShape: SliderComponentShape.noOverlay,
                        trackHeight: 3.0,
                        activeTrackColor: _isNudging
                            ? (_cachedSliderActiveColor ?? Colors.white).withOpacity(0.85)
                            : _cachedSliderActiveColor,
                        inactiveTrackColor: _cachedSliderInactiveColor,
                      ),
                      child: Container(
                        decoration: _isNudging
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.07 * _nudgeGlow.value), blurRadius: 12, spreadRadius: 2)],
                              )
                            : const BoxDecoration(),
                        child: Slider(
                          value: _isNudging ? _nudgeRating.value.clamp(1.0, 10.0) : _currentRating,
                          min: 1,
                          max: 10,
                          divisions: 100,
                          label: (_isNudging ? _nudgeRating.value : _currentRating).toStringAsFixed(1),
                          activeColor: _isNudging
                              ? (_cachedSliderActiveColor ?? Colors.white).withOpacity(0.85)
                              : _cachedSliderActiveColor,
                          inactiveColor: _cachedSliderInactiveColor,
                          onChanged: _onRatingChanged,
                          onChangeEnd: _onRatingEnd,
                        ),
                      ),
                    );
                  },
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
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: !widget.showSlider && widget.hasRated
              ? Center(key: const ValueKey('button'), child: _buildRatingButton())
              : widget.showSlider
                  ? SizedBox(key: const ValueKey('slider'), width: double.infinity, child: _buildRatingSlider(themeProvider))
                  : const SizedBox.shrink(key: ValueKey('empty')),
        ),
      ],
    );
  }
}
