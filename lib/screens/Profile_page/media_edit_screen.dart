// lib/screens/Profile_page/media_edit_screen.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';

// =============================================================================
// FILTER MODEL
// =============================================================================

class _Filter {
  final String name;
  final List<double> matrix;
  const _Filter({required this.name, required this.matrix});
}

const List<_Filter> _filters = [
  _Filter(name: 'Normal', matrix: [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Filter(name: 'Vivid', matrix: [
    1.4, -0.1, -0.1, 0, 0,
    -0.1, 1.3, -0.1, 0, 0,
    -0.1, -0.1, 1.4, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Filter(name: 'Warm', matrix: [
    1.2, 0.0, 0.0, 0, 15,
    0.0, 1.0, 0.0, 0, 5,
    0.0, 0.0, 0.8, 0, -10,
    0, 0, 0, 1, 0,
  ]),
  _Filter(name: 'Cool', matrix: [
    0.8, 0.0, 0.0, 0, -10,
    0.0, 1.0, 0.0, 0, 5,
    0.0, 0.0, 1.2, 0, 15,
    0, 0, 0, 1, 0,
  ]),
  _Filter(name: 'Noir', matrix: [
    0.33, 0.59, 0.11, 0, 0,
    0.33, 0.59, 0.11, 0, 0,
    0.33, 0.59, 0.11, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Filter(name: 'Fade', matrix: [
    1.0, 0, 0, 0, 40,
    0, 1.0, 0, 0, 40,
    0, 0, 1.0, 0, 40,
    0, 0, 0, 0.85, 0,
  ]),
  _Filter(name: 'Chrome', matrix: [
    0.78, 0.15, 0.07, 0, 0,
    0.07, 0.84, 0.09, 0, 0,
    0.07, 0.07, 0.86, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Filter(name: 'Lush', matrix: [
    0.9, 0.1, 0.0, 0, 10,
    0.0, 1.1, 0.0, 0, 5,
    0.0, 0.1, 0.9, 0, 10,
    0, 0, 0, 1, 0,
  ]),
];

// =============================================================================
// FONT MODEL
// =============================================================================

class _FontOption {
  final String label;
  final String? family; // null = default system font
  final FontWeight weight;

  const _FontOption({
    required this.label,
    this.family,
    this.weight = FontWeight.w800,
  });
}

const List<_FontOption> _fonts = [
  _FontOption(label: 'Default', family: null),
  _FontOption(label: 'Serif', family: 'Georgia'),
  _FontOption(label: 'Mono', family: 'Courier'),
  _FontOption(label: 'Classic', family: 'Times New Roman'),
  _FontOption(label: 'Round', family: 'Helvetica Neue', weight: FontWeight.w700),
];

// =============================================================================
// TEXT OVERLAY MODEL
// =============================================================================

class _TextOverlay {
  String text;
  Offset position; // fractional 0..1
  Color color;
  double fontSize;
  bool isBold;
  int fontIndex;

  _TextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
    this.fontSize = 28.0,
    this.isBold = true,
    this.fontIndex = 0,
  });

  _TextOverlay copyWith({
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
    bool? isBold,
    int? fontIndex,
  }) {
    return _TextOverlay(
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      fontIndex: fontIndex ?? this.fontIndex,
    );
  }
}

// =============================================================================
// COLOUR PALETTE
// =============================================================================

const List<Color> _textColors = [
  Colors.white,
  Colors.black,
  Colors.yellow,
  Colors.red,
  Colors.blue,
  Colors.green,
  Colors.pink,
  Colors.orange,
  Colors.cyan,
  Colors.purple,
];

// =============================================================================
// CONSTANTS
// =============================================================================

const double _topBarHeight   = 56.0;
const double _toolBarHeight  = 76.0;  // slightly taller so label is not cut
const double _filterHeight   = 100.0;

const double _minFontSize = 16.0;
const double _maxFontSize = 72.0;

// =============================================================================
// MEDIA EDIT SCREEN
// =============================================================================

class MediaEditScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final VoidCallback? onPostUploaded;

  const MediaEditScreen({
    Key? key,
    required this.imageBytes,
    this.onPostUploaded,
  }) : super(key: key);

  @override
  State<MediaEditScreen> createState() => _MediaEditScreenState();
}

class _MediaEditScreenState extends State<MediaEditScreen> {
  final GlobalKey _previewKey = GlobalKey();

  int _selectedFilterIndex = 0;
  final List<_TextOverlay> _textOverlays = [];
  int? _selectedOverlayIndex;
  bool _isRendering = false;
  int _rotationQuarters = 0;

  // ── Text-editing state ───────────────────────────────────────────────────
  bool _isTyping = false;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Color _currentTextColor = Colors.white;
  double _currentFontSize = 32.0;
  bool _currentIsBold = true;
  int _currentFontIndex = 0;

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  // ===========================================================================
  // ROTATION
  // ===========================================================================

  void _rotate() =>
      setState(() => _rotationQuarters = (_rotationQuarters + 1) % 4);

  Uint8List _applyRotation(Uint8List bytes) {
    if (_rotationQuarters == 0) return bytes;
    final decoded = img.decodeJpg(bytes);
    if (decoded == null) return bytes;
    var rotated = decoded;
    for (int i = 0; i < _rotationQuarters; i++) {
      rotated = img.copyRotate(rotated, angle: 90);
    }
    return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
  }

  // ===========================================================================
  // TEXT MODE
  // ===========================================================================

  void _enterTextMode() {
    _textController.clear();
    setState(() {
      _isTyping = true;
      _currentTextColor = Colors.white;
      _currentFontSize = 32.0;
      _currentIsBold = true;
      _currentFontIndex = 0;
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  void _confirmText() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _textOverlays.add(_TextOverlay(
          text: text,
          position: const Offset(0.5, 0.45),
          color: _currentTextColor,
          fontSize: _currentFontSize,
          isBold: _currentIsBold,
          fontIndex: _currentFontIndex,
        ));
      });
    }
    _textController.clear();
    _textFocusNode.unfocus();
    setState(() => _isTyping = false);
  }

  void _cancelText() {
    _textController.clear();
    _textFocusNode.unfocus();
    setState(() => _isTyping = false);
  }

  // ===========================================================================
  // RENDER & NEXT
  // ===========================================================================

  Future<Uint8List> _renderFinalImage() async {
    setState(() {
      _isRendering = true;
      _selectedOverlayIndex = null;
    });
    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final boundary = _previewKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final uiImage = await boundary.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final decoded = img.decodePng(pngBytes);
      if (decoded != null) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
      }
      return pngBytes;
    } finally {
      if (mounted) setState(() => _isRendering = false);
    }
  }

  Future<void> _onNext() async {
    try {
      final bytes = await _renderFinalImage();
      final rotated = _applyRotation(bytes);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddPostScreen(
              initialFile: rotated,
              onPostUploaded: widget.onPostUploaded,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to process image.')),
        );
      }
    }
  }

  // ===========================================================================
  // OVERLAY TEXT STYLE HELPER
  // ===========================================================================

  TextStyle _overlayStyle(_TextOverlay overlay) {
    final font = _fonts[overlay.fontIndex];
    return TextStyle(
      fontFamily: font.family,
      fontSize: overlay.fontSize,
      fontWeight: overlay.isBold ? FontWeight.w800 : FontWeight.w400,
      color: overlay.color,
      shadows: const [
        Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54),
      ],
    );
  }

  TextStyle _overlayShadowStyle(_TextOverlay overlay) {
    final font = _fonts[overlay.fontIndex];
    return TextStyle(
      fontFamily: font.family,
      fontSize: overlay.fontSize,
      fontWeight: overlay.isBold ? FontWeight.w800 : FontWeight.w400,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withOpacity(0.45),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final imageHeight = screenSize.height -
        topPadding -
        _topBarHeight -
        _toolBarHeight -
        _filterHeight -
        bottomPadding -
        8;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Main editing UI ────────────────────────────────────────────
          Column(
            children: [
              SizedBox(height: topPadding),

              // ── Top bar ──────────────────────────────────────────────
              SizedBox(
                height: _topBarHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      const Text('Edit',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                      GestureDetector(
                        onTap: _isRendering ? null : _onNext,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _isRendering
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2),
                                )
                              : const Text('Next',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Image + overlays ─────────────────────────────────────
              SizedBox(
                height: imageHeight,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _selectedOverlayIndex = null),
                  child: RepaintBoundary(
                    key: _previewKey,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                                _filters[_selectedFilterIndex].matrix),
                            child: Transform.rotate(
                              angle: _rotationQuarters * 3.14159265 / 2,
                              child: Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                          ),
                        ),
                        ..._textOverlays.asMap().entries.map((entry) {
                          final index = entry.key;
                          final overlay = entry.value;
                          final isSelected =
                              _selectedOverlayIndex == index;

                          return Positioned(
                            left: (overlay.position.dx *
                                    screenSize.width)
                                .clamp(0.0, screenSize.width - 10),
                            top: (overlay.position.dy * imageHeight)
                                .clamp(0.0, imageHeight - 10),
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _selectedOverlayIndex = index),
                              onPanUpdate: (d) {
                                setState(() {
                                  _textOverlays[index] =
                                      overlay.copyWith(
                                    position: Offset(
                                      (overlay.position.dx +
                                              d.delta.dx /
                                                  screenSize.width)
                                          .clamp(0.0, 0.9),
                                      (overlay.position.dy +
                                              d.delta.dy /
                                                  imageHeight)
                                          .clamp(0.0, 0.9),
                                    ),
                                  );
                                });
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Text(overlay.text,
                                      style: _overlayShadowStyle(overlay)),
                                  Text(overlay.text,
                                      style: _overlayStyle(overlay)),
                                  if (isSelected)
                                    Positioned(
                                      top: -14,
                                      right: -14,
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _textOverlays.removeAt(index);
                                          _selectedOverlayIndex = null;
                                        }),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle),
                                          child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 14),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Tool bar ─────────────────────────────────────────────
              // FIX 6: explicit height + padding ensures labels are never
              // overlapped by the filter strip below.
              Container(
                height: _toolBarHeight,
                color: const Color(0xFF111111),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ToolButton(
                      icon: Icons.text_fields_rounded,
                      label: 'Text',
                      onTap: _enterTextMode,
                    ),
                    const SizedBox(width: 40),
                    _ToolButton(
                      icon: Icons.rotate_90_degrees_cw_rounded,
                      label: 'Rotate',
                      onTap: _rotate,
                    ),
                  ],
                ),
              ),

              // ── Filter strip ─────────────────────────────────────────
              Container(
                height: _filterHeight,
                color: Colors.black,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: _filters.length,
                  itemBuilder: (ctx, i) {
                    final isSelected = _selectedFilterIndex == i;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedFilterIndex = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: ColorFiltered(
                                  colorFilter: ColorFilter.matrix(
                                      _filters[i].matrix),
                                  child: Image.memory(
                                    widget.imageBytes,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _filters[i].name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.45),
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              SizedBox(height: bottomPadding),
            ],
          ),

          // ── Text entry overlay ─────────────────────────────────────────
          if (_isTyping)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.55),
                child: Column(
                  children: [
                    // FIX 5: push controls down from the very top
                    SizedBox(height: topPadding + 12),

                    // Cancel | colours | bold | Done
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      child: Row(
                        children: [
                          // Cancel
                          GestureDetector(
                            onTap: _cancelText,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Text('Cancel',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 15)),
                            ),
                          ),

                          // Colour swatches
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children:
                                    _textColors.map((c) {
                                  final selected =
                                      _currentTextColor == c;
                                  return GestureDetector(
                                    onTap: () => setState(
                                        () => _currentTextColor = c),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 150),
                                      margin: const EdgeInsets
                                          .symmetric(horizontal: 4),
                                      width: selected ? 28 : 22,
                                      height: selected ? 28 : 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                        border: Border.all(
                                          color: selected
                                              ? Colors.white
                                              : Colors.white
                                                  .withOpacity(0.3),
                                          width:
                                              selected ? 2.5 : 1.5,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          // FIX 2: Bold toggle button
                          GestureDetector(
                            onTap: () => setState(
                                () => _currentIsBold = !_currentIsBold),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentIsBold
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.15),
                              ),
                              child: Center(
                                child: Text(
                                  'B',
                                  style: TextStyle(
                                    color: _currentIsBold
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Done
                          GestureDetector(
                            onTap: _confirmText,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Text('Done',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // FIX 4: Font selector row
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12),
                        itemCount: _fonts.length,
                        itemBuilder: (ctx, i) {
                          final isSelected = _currentFontIndex == i;
                          return GestureDetector(
                            onTap: () => setState(
                                () => _currentFontIndex = i),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.12),
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: Text(
                                _fonts[i].label,
                                style: TextStyle(
                                  fontFamily: _fonts[i].family,
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Centred text field + FIX 3: size slider on the right
                    Expanded(
                      child: GestureDetector(
                        onTap: () {},
                        child: Stack(
                          children: [
                            // Text field centred in the available space
                            Center(
                              child: IntrinsicWidth(
                                child: TextField(
                                  controller: _textController,
                                  focusNode: _textFocusNode,
                                  autofocus: true,
                                  textAlign: TextAlign.center,
                                  maxLines: null,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _confirmText(),
                                  // FIX 1: no hintText — completely removed
                                  style: TextStyle(
                                    fontFamily: _fonts[_currentFontIndex].family,
                                    color: _currentTextColor,
                                    fontSize: _currentFontSize,
                                    fontWeight: _currentIsBold
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black
                                            .withOpacity(0.6),
                                        offset: const Offset(1, 1),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    // FIX 1: hintText is empty/absent
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  cursorColor: Colors.white,
                                ),
                              ),
                            ),

                            // FIX 3: Vertical font-size slider — right side
                            Positioned(
                              right: 16,
                              top: 0,
                              bottom: 0,
                              child: _VerticalSizeSlider(
                                value: _currentFontSize,
                                min: _minFontSize,
                                max: _maxFontSize,
                                onChanged: (v) =>
                                    setState(() => _currentFontSize = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 300),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// VERTICAL SIZE SLIDER  (TikTok-style)
// =============================================================================

class _VerticalSizeSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _VerticalSizeSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Track height — use LayoutBuilder to get the available vertical space
    return LayoutBuilder(builder: (ctx, constraints) {
      final trackH = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : 200.0;
      // fraction: 0 = smallest (bottom), 1 = largest (top)
      final fraction = (value - min) / (max - min);
      final handleY = trackH * (1 - fraction); // top offset of handle centre

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) {
          final newFraction =
              ((1 - (handleY + d.delta.dy) / trackH)).clamp(0.0, 1.0);
          final newSize = min + newFraction * (max - min);
          onChanged(newSize);
        },
        onTapDown: (d) {
          final newFraction =
              (1 - d.localPosition.dy / trackH).clamp(0.0, 1.0);
          final newSize = min + newFraction * (max - min);
          onChanged(newSize);
        },
        child: SizedBox(
          width: 36,
          height: trackH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Track line
              Positioned(
                left: 17,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Filled portion (bottom to handle)
              Positioned(
                left: 17,
                top: handleY,
                bottom: 0,
                width: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Handle circle
              Positioned(
                left: 0,
                top: handleY - 12,
                child: Container(
                  width: 36,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.unfold_more,
                      size: 14, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// =============================================================================
// TOOL BUTTON
// =============================================================================

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
