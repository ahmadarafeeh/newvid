// lib/screens/Profile_page/media_edit_screen.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
// TEXT OVERLAY MODEL
// =============================================================================

class _TextOverlay {
  String text;
  Offset position; // fractional 0..1 within image area
  Color color;
  double fontSize;

  _TextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
    this.fontSize = 28.0,
  });

  _TextOverlay copyWith({
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
  }) {
    return _TextOverlay(
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

// =============================================================================
// AVAILABLE TEXT COLOURS
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

class _MediaEditScreenState extends State<MediaEditScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _previewKey = GlobalKey();

  int _selectedFilterIndex = 0;
  final List<_TextOverlay> _textOverlays = [];
  int? _selectedOverlayIndex;
  bool _isRendering = false;
  int _rotationQuarters = 0;

  // ── Text editing overlay state ────────────────────────────────────────
  bool _isTyping = false;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Color _currentTextColor = Colors.white;

  static const double _topBarHeight = 56.0;
  static const double _toolBarHeight = 72.0;
  static const double _filterStripHeight = 100.0;

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
  // TEXT — Instagram/TikTok style: type directly on image
  // ===========================================================================

  void _enterTextMode() {
    _textController.clear();
    setState(() {
      _isTyping = true;
      _currentTextColor = Colors.white;
    });
    // Small delay so the overlay is built before requesting focus
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
          // Place in centre of image by default; user can drag later
          position: const Offset(0.5, 0.45),
          color: _currentTextColor,
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
        _filterStripHeight -
        bottomPadding -
        8;

    return Scaffold(
      // resizeToAvoidBottomInset false so the image doesn't jump when
      // keyboard opens during text entry
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Main editing UI ────────────────────────────────────────────
          Column(
            children: [
              SizedBox(height: topPadding),

              // Top bar
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

              // Image + overlays
              SizedBox(
                height: imageHeight,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _selectedOverlayIndex = null),
                  child: RepaintBoundary(
                    key: _previewKey,
                    child: Stack(
                      children: [
                        // Filtered image
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

                        // Placed text overlays
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
                                              d.delta.dy / imageHeight)
                                          .clamp(0.0, 0.9),
                                    ),
                                  );
                                });
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Shadow
                                  Text(overlay.text,
                                      style: TextStyle(
                                        fontSize: overlay.fontSize,
                                        fontWeight: FontWeight.w800,
                                        foreground: Paint()
                                          ..style = PaintingStyle.stroke
                                          ..strokeWidth = 3
                                          ..color =
                                              Colors.black.withOpacity(0.5),
                                      )),
                                  // Fill
                                  Text(overlay.text,
                                      style: TextStyle(
                                        fontSize: overlay.fontSize,
                                        fontWeight: FontWeight.w800,
                                        color: overlay.color,
                                      )),
                                  // Delete handle
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
                                          child: const Icon(Icons.close,
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

              // Tool bar
              Container(
                height: _toolBarHeight,
                color: const Color(0xFF111111),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
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

              // Filter strip
              Container(
                height: _filterStripHeight,
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
                        margin:
                            const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
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

          // ── Instagram/TikTok-style text entry overlay ──────────────────
          // Shown on top of everything when _isTyping == true
          if (_isTyping)
            Positioned.fill(
              child: GestureDetector(
                onTap: _confirmText, // tap outside = done
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  child: Column(
                    children: [
                      // Top row: Cancel | colour swatches | Done
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              // Cancel
                              GestureDetector(
                                onTap: _cancelText,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('Cancel',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15)),
                                ),
                              ),

                              // Colour swatches
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: _textColors.map((c) {
                                      final selected =
                                          _currentTextColor == c;
                                      return GestureDetector(
                                        onTap: () => setState(
                                            () => _currentTextColor = c),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 150),
                                          margin: const EdgeInsets
                                              .symmetric(horizontal: 5),
                                          width: selected ? 30 : 24,
                                          height: selected ? 30 : 24,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: c,
                                            border: Border.all(
                                              color: selected
                                                  ? Colors.white
                                                  : Colors.white
                                                      .withOpacity(0.3),
                                              width: selected ? 2.5 : 1.5,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),

                              // Done
                              GestureDetector(
                                onTap: _confirmText,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
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
                      ),

                      // Centred text field — renders text in the chosen colour
                      // so it looks like you're typing directly on the photo
                      Expanded(
                        child: Center(
                          child: GestureDetector(
                            onTap: () {}, // prevent tap-outside dismiss here
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
                                style: TextStyle(
                                  color: _currentTextColor,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withOpacity(0.6),
                                      offset: const Offset(1, 1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Add text...',
                                  hintStyle: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                cursorColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Space at the bottom so keyboard doesn't overlap
                      const SizedBox(height: 300),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
