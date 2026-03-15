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
// TEXT OVERLAY MODEL
// =============================================================================

class _TextOverlay {
  String text;
  Offset position;
  Color color;
  double fontSize;
  bool isBold;

  _TextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
    this.fontSize = 28.0,
    this.isBold = true,
  });

  _TextOverlay copyWith({
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
    bool? isBold,
  }) {
    return _TextOverlay(
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
    );
  }
}

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

  final TextEditingController _textController = TextEditingController();
  Color _textColor = Colors.white;

  int _rotationQuarters = 0;

  // Fixed heights for the bottom panel so image always gets the remaining space
  static const double _topBarHeight = 56.0;
  static const double _toolBarHeight = 72.0;
  static const double _filterStripHeight = 100.0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // ROTATION
  // ===========================================================================

  void _rotate() => setState(() => _rotationQuarters = (_rotationQuarters + 1) % 4);

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
  // TEXT OVERLAY
  // ===========================================================================

  void _addTextOverlay() {
    _textController.clear();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        Color pickedColor = _textColor;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              'Add Text',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _textController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type something...',
                    hintStyle:
                        TextStyle(color: Colors.white.withOpacity(0.4)),
                    border: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54)),
                    enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24)),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Colors.white,
                      Colors.black,
                      Colors.yellow,
                      Colors.red,
                      Colors.blue,
                      Colors.green,
                      Colors.pink,
                      Colors.orange,
                    ].map((c) {
                      final selected = pickedColor == c;
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => pickedColor = c),
                        child: Container(
                          margin:
                              const EdgeInsets.symmetric(horizontal: 4),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _textController.clear();
                  Navigator.pop(ctx);
                },
                child: Text('Cancel',
                    style:
                        TextStyle(color: Colors.white.withOpacity(0.5))),
              ),
              TextButton(
                onPressed: () {
                  final text = _textController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _textColor = pickedColor;
                      _textOverlays.add(_TextOverlay(
                        text: text,
                        position: const Offset(0.1, 0.35),
                        color: pickedColor,
                      ));
                    });
                  }
                  _textController.clear();
                  Navigator.pop(ctx);
                },
                child: const Text('Add',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
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

    // Image preview gets whatever space is left after the fixed panels
    final imageHeight = screenSize.height -
        topPadding -
        _topBarHeight -
        _toolBarHeight -
        _filterStripHeight -
        bottomPadding -
        8; // small gap

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Safe area top spacer ─────────────────────────────────────
          SizedBox(height: topPadding),

          // ── Top bar ──────────────────────────────────────────────────
          SizedBox(
            height: _topBarHeight,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Text(
                    'Edit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                          : const Text(
                              'Next',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Image preview ─────────────────────────────────────────────
          SizedBox(
            height: imageHeight,
            child: GestureDetector(
              onTap: () =>
                  setState(() => _selectedOverlayIndex = null),
              child: RepaintBoundary(
                key: _previewKey,
                child: Stack(
                  children: [
                    // Filtered + rotated image
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

                    // Draggable text overlays
                    ..._textOverlays.asMap().entries.map((entry) {
                      final index = entry.key;
                      final overlay = entry.value;
                      final isSelected =
                          _selectedOverlayIndex == index;

                      return Positioned(
                        left: overlay.position.dx * screenSize.width,
                        top: overlay.position.dy * imageHeight,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _selectedOverlayIndex = index),
                          onPanUpdate: (details) {
                            setState(() {
                              _textOverlays[index] =
                                  overlay.copyWith(
                                position: Offset(
                                  (overlay.position.dx +
                                          details.delta.dx /
                                              screenSize.width)
                                      .clamp(0.0, 0.85),
                                  (overlay.position.dy +
                                          details.delta.dy /
                                              imageHeight)
                                      .clamp(0.0, 0.88),
                                ),
                              );
                            });
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Shadow pass
                              Text(
                                overlay.text,
                                style: TextStyle(
                                  fontSize: overlay.fontSize,
                                  fontWeight: overlay.isBold
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                  color:
                                      Colors.black.withOpacity(0.35),
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 3,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                              // Colour pass
                              Text(
                                overlay.text,
                                style: TextStyle(
                                  fontSize: overlay.fontSize,
                                  fontWeight: overlay.isBold
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                  color: overlay.color,
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 4,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                              // Delete handle
                              if (isSelected)
                                Positioned(
                                  top: -12,
                                  right: -12,
                                  child: GestureDetector(
                                    onTap: () => setState(() {
                                      _textOverlays.removeAt(index);
                                      _selectedOverlayIndex = null;
                                    }),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
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

          // ── Tool buttons (Text + Rotate) ──────────────────────────────
          Container(
            height: _toolBarHeight,
            color: const Color(0xFF111111),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ToolButton(
                  icon: Icons.text_fields_rounded,
                  label: 'Text',
                  onTap: _addTextOverlay,
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

          // ── Filter strip ──────────────────────────────────────────────
          Container(
            height: _filterStripHeight,
            color: Colors.black,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

          // ── Bottom safe area ──────────────────────────────────────────
          SizedBox(height: bottomPadding),
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
