// lib/screens/Profile_page/video_edit_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';

// =============================================================================
// FONT OPTIONS
// =============================================================================

class _FontOption {
  final String label;
  final String? family;
  const _FontOption({required this.label, this.family});
}

const List<_FontOption> _fonts = [
  _FontOption(label: 'Default', family: null),
  _FontOption(label: 'Serif', family: 'Georgia'),
  _FontOption(label: 'Mono', family: 'Courier'),
  _FontOption(label: 'Classic', family: 'Times New Roman'),
  _FontOption(label: 'Round', family: 'Helvetica Neue'),
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
// TEXT COLOURS
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

const double _topBarHeight = 56.0;
const double _toolBarHeight = 76.0;
const double _minFontSize = 16.0;
const double _maxFontSize = 72.0;
const double _trashZoneHeight = 80.0;

// =============================================================================
// VIDEO EDIT SCREEN
// =============================================================================

class VideoEditScreen extends StatefulWidget {
  final File videoFile;
  final VoidCallback? onPostUploaded;

  const VideoEditScreen({
    Key? key,
    required this.videoFile,
    this.onPostUploaded,
  }) : super(key: key);

  @override
  State<VideoEditScreen> createState() => _VideoEditScreenState();
}

class _VideoEditScreenState extends State<VideoEditScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;

  final List<_TextOverlay> _textOverlays = [];
  int? _selectedOverlayIndex;

  // Drag-to-trash
  bool _isDragging = false;
  int? _draggingIndex;
  bool _isOverTrash = false;

  // Text entry
  bool _isTyping = false;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  Color _currentTextColor = Colors.white;
  double _currentFontSize = 32.0;
  bool _currentIsBold = true;
  int _currentFontIndex = 0;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(
      widget.videoFile,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();
    if (mounted) {
      setState(() {
        _videoController = controller;
        _isVideoInitialized = true;
        _isPlaying = true;
      });
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;
    if (_isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
    setState(() => _isPlaying = !_isPlaying);
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
  // DRAG-TO-TRASH
  // ===========================================================================

  bool _isPosOverTrash(Offset pos, double imageH) =>
      pos.dy * imageH >= imageH - _trashZoneHeight;

  void _onDragStart(int index) => setState(() {
        _isDragging = true;
        _draggingIndex = index;
        _selectedOverlayIndex = index;
        _isOverTrash = false;
      });

  void _onDragUpdate(int index, DragUpdateDetails d, double w, double h) {
    final o = _textOverlays[index];
    final newPos = Offset(
      (o.position.dx + d.delta.dx / w).clamp(0.0, 0.9),
      (o.position.dy + d.delta.dy / h).clamp(0.0, 0.99),
    );
    setState(() {
      _textOverlays[index] = o.copyWith(position: newPos);
      _isOverTrash = _isPosOverTrash(newPos, h);
    });
  }

  void _onDragEnd(int index, double h) {
    final overTrash = _isPosOverTrash(_textOverlays[index].position, h);
    setState(() {
      _isDragging = false;
      _draggingIndex = null;
      _isOverTrash = false;
      if (overTrash) {
        _textOverlays.removeAt(index);
        _selectedOverlayIndex = null;
      }
    });
  }

  // ===========================================================================
  // NEXT
  // ===========================================================================

  void _onNext() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddPostScreen(
          initialVideoFile: widget.videoFile,
          onPostUploaded: widget.onPostUploaded,
        ),
      ),
    );
  }

  // ===========================================================================
  // TEXT STYLE HELPERS
  // ===========================================================================

  TextStyle _overlayStyle(_TextOverlay o) => TextStyle(
        fontFamily: _fonts[o.fontIndex].family,
        fontSize: o.fontSize,
        fontWeight: o.isBold ? FontWeight.w800 : FontWeight.w400,
        color: o.color,
        shadows: const [
          Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54),
        ],
      );

  TextStyle _overlayShadowStyle(_TextOverlay o) => TextStyle(
        fontFamily: _fonts[o.fontIndex].family,
        fontSize: o.fontSize,
        fontWeight: o.isBold ? FontWeight.w800 : FontWeight.w400,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black.withOpacity(0.45),
      );

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final videoAreaHeight = screenSize.height -
        topPadding -
        _topBarHeight -
        _toolBarHeight -
        bottomPadding -
        8;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Main column ───────────────────────────────────────────────────
          Column(
            children: [
              SizedBox(height: topPadding),

              // Top bar
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
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      const Text('Edit Video',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                      GestureDetector(
                        onTap: _onNext,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Next',
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

              // Video area + overlays + trash
              SizedBox(
                height: videoAreaHeight,
                child: Stack(
                  children: [
                    // Video player — fills the area, correct ratio
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedOverlayIndex = null);
                          _togglePlayPause();
                        },
                        child: _isVideoInitialized && _videoController != null
                            ? ClipRect(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _videoController!.value.size.width,
                                    height: _videoController!.value.size.height,
                                    child: VideoPlayer(_videoController!),
                                  ),
                                ),
                              )
                            : const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white)),
                      ),
                    ),

                    // Play/pause icon flash
                    if (!_isPlaying)
                      const Center(
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white54, size: 64),
                      ),

                    // Text overlays
                    ..._textOverlays.asMap().entries.map((entry) {
                      final index = entry.key;
                      final overlay = entry.value;
                      final isDraggingThis = _draggingIndex == index;

                      return Positioned(
                        left: (overlay.position.dx * screenSize.width)
                            .clamp(0.0, screenSize.width - 10),
                        top: (overlay.position.dy * videoAreaHeight)
                            .clamp(0.0, videoAreaHeight - 10),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _selectedOverlayIndex = index),
                          onPanStart: (_) => _onDragStart(index),
                          onPanUpdate: (d) => _onDragUpdate(
                              index, d, screenSize.width, videoAreaHeight),
                          onPanEnd: (_) => _onDragEnd(index, videoAreaHeight),
                          child: AnimatedOpacity(
                            opacity:
                                (isDraggingThis && _isOverTrash) ? 0.4 : 1.0,
                            duration: const Duration(milliseconds: 100),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Text(overlay.text,
                                    style: _overlayShadowStyle(overlay)),
                                Text(overlay.text,
                                    style: _overlayStyle(overlay)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                    // Trash zone
                    if (_isDragging)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: _trashZoneHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: _isOverTrash
                                  ? [
                                      Colors.red.withOpacity(0.75),
                                      Colors.red.withOpacity(0.0),
                                    ]
                                  : [
                                      Colors.black.withOpacity(0.55),
                                      Colors.black.withOpacity(0.0),
                                    ],
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _isOverTrash ? 52 : 40,
                                height: _isOverTrash ? 52 : 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isOverTrash
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.25),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.6),
                                      width: 1.5),
                                ),
                                child: Icon(
                                  _isOverTrash
                                      ? Icons.delete
                                      : Icons.delete_outline,
                                  color: Colors.white,
                                  size: _isOverTrash ? 26 : 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Tool bar — Text button only (filters not applicable to video)
              Container(
                height: _toolBarHeight,
                color: const Color(0xFF111111),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ToolButton(
                      icon: Icons.text_fields_rounded,
                      label: 'Text',
                      onTap: _enterTextMode,
                    ),
                  ],
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
                    SizedBox(height: topPadding + 12),

                    // Cancel | colours | bold | Done
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
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
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: _textColors.map((c) {
                                  final selected = _currentTextColor == c;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _currentTextColor = c),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      width: selected ? 28 : 22,
                                      height: selected ? 28 : 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                        border: Border.all(
                                          color: selected
                                              ? Colors.white
                                              : Colors.white.withOpacity(0.3),
                                          width: selected ? 2.5 : 1.5,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          // Bold toggle
                          GestureDetector(
                            onTap: () => setState(
                                () => _currentIsBold = !_currentIsBold),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentIsBold
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.15),
                              ),
                              child: Center(
                                child: Text('B',
                                    style: TextStyle(
                                      color: _currentIsBold
                                          ? Colors.black
                                          : Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    )),
                              ),
                            ),
                          ),
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

                    // Font selector
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _fonts.length,
                        itemBuilder: (ctx, i) {
                          final isSelected = _currentFontIndex == i;
                          return GestureDetector(
                            onTap: () => setState(() => _currentFontIndex = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _fonts[i].label,
                                style: TextStyle(
                                  fontFamily: _fonts[i].family,
                                  color:
                                      isSelected ? Colors.black : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Text field + size slider
                    Expanded(
                      child: GestureDetector(
                        onTap: () {},
                        child: Stack(
                          children: [
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
                                  style: TextStyle(
                                    fontFamily:
                                        _fonts[_currentFontIndex].family,
                                    color: _currentTextColor,
                                    fontSize: _currentFontSize,
                                    fontWeight: _currentIsBold
                                        ? FontWeight.w800
                                        : FontWeight.w400,
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
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  cursorColor: Colors.white,
                                ),
                              ),
                            ),

                            // Size slider
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
// VERTICAL SIZE SLIDER
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
    return LayoutBuilder(builder: (ctx, constraints) {
      final trackH =
          constraints.maxHeight.isFinite ? constraints.maxHeight : 200.0;
      final fraction = (value - min) / (max - min);
      final handleY = trackH * (1 - fraction);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) {
          final f = (1 - (handleY + d.delta.dy) / trackH).clamp(0.0, 1.0);
          onChanged(min + f * (max - min));
        },
        onTapDown: (d) {
          final f = (1 - d.localPosition.dy / trackH).clamp(0.0, 1.0);
          onChanged(min + f * (max - min));
        },
        child: SizedBox(
          width: 36,
          height: trackH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
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
