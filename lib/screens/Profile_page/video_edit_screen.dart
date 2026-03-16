// lib/screens/Profile_page/video_edit_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';
import 'package:Ratedly/screens/Profile_page/edit_shared.dart';

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

  // ── Editing state ─────────────────────────────────────────────────────────
  int _selectedFilterIndex = 0;
  EditAdjustments _adj = const EditAdjustments();
  _ActiveTab _activeTab = _ActiveTab.filters;

  // ── Text state ────────────────────────────────────────────────────────────
  bool _isTyping = false;
  final List<TextOverlay> _overlays = [];
  int? _selectedOverlayIndex;
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  Color _tColor = Colors.white;
  double _tSize = 32.0;
  bool _tBold = true;
  int _tFont = 0;

  // ── Drag-to-trash ─────────────────────────────────────────────────────────
  bool _isDragging = false;
  int? _dragIndex;
  bool _isOverTrash = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(
      widget.videoFile,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await c.initialize();
    await c.setLooping(true);
    await c.play();
    if (mounted) {
      setState(() {
        _videoController = c;
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
  // COMBINED MATRIX
  // ===========================================================================

  List<double> get _currentMatrix =>
      _adj.combinedMatrix(kFilters[_selectedFilterIndex].matrix);

  // ===========================================================================
  // TEXT
  // ===========================================================================

  void _enterTextMode() {
    _textCtrl.clear();
    setState(() {
      _isTyping = true;
      _tColor = Colors.white;
      _tSize = 32.0;
      _tBold = true;
      _tFont = 0;
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _textFocus.requestFocus();
    });
  }

  void _confirmText() {
    final text = _textCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() => _overlays.add(TextOverlay(
            text: text,
            position: const Offset(0.5, 0.45),
            color: _tColor,
            fontSize: _tSize,
            isBold: _tBold,
            fontIndex: _tFont,
          )));
    }
    _textCtrl.clear();
    _textFocus.unfocus();
    setState(() => _isTyping = false);
  }

  void _cancelText() {
    _textCtrl.clear();
    _textFocus.unfocus();
    setState(() => _isTyping = false);
  }

  // ===========================================================================
  // DRAG-TO-TRASH
  // ===========================================================================

  bool _overTrash(Offset pos, double h) => pos.dy * h >= h - kTrashZoneH;

  void _onDragStart(int i) => setState(() {
        _isDragging = true;
        _dragIndex = i;
        _selectedOverlayIndex = i;
        _isOverTrash = false;
      });

  void _onDragUpdate(int i, DragUpdateDetails d, double w, double h) {
    final o = _overlays[i];
    final p = Offset(
      (o.position.dx + d.delta.dx / w).clamp(0.0, 0.9),
      (o.position.dy + d.delta.dy / h).clamp(0.0, 0.99),
    );
    setState(() {
      _overlays[i] = o.copyWith(position: p);
      _isOverTrash = _overTrash(p, h);
    });
  }

  void _onDragEnd(int i, double h) {
    final del = _overTrash(_overlays[i].position, h);
    setState(() {
      _isDragging = false;
      _dragIndex = null;
      _isOverTrash = false;
      if (del) {
        _overlays.removeAt(i);
        _selectedOverlayIndex = null;
      }
    });
  }

  // ===========================================================================
  // NEXT — passes original video file (overlays are visual-only)
  // ===========================================================================

  void _onNext() {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddPostScreen(
            initialVideoFile: widget.videoFile,
            onPostUploaded: widget.onPostUploaded,
          ),
        ));
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  static const double _topBar = 56.0;
  static const double _tabBar = 44.0;
  static const double _panel = 100.0;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    final videoH =
        screenSize.height - topPad - _topBar - _tabBar - _panel - botPad - 8;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: topPad),

              // ── Top bar ────────────────────────────────────────────────
              SizedBox(
                height: _topBar,
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
                                color: Colors.white, size: 20)),
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
                              borderRadius: BorderRadius.circular(20)),
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

              // ── Video + overlays + trash ───────────────────────────────
              SizedBox(
                height: videoH,
                child: Stack(
                  children: [
                    // Video with filter applied as ColorFilter overlay
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedOverlayIndex = null);
                          _togglePlayPause();
                        },
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(_currentMatrix),
                          child: _isVideoInitialized && _videoController != null
                              ? ClipRect(
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: _videoController!.value.size.width,
                                      height:
                                          _videoController!.value.size.height,
                                      child: VideoPlayer(_videoController!),
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white)),
                        ),
                      ),
                    ),

                    // Play/pause icon
                    if (!_isPlaying)
                      const Center(
                          child: Icon(Icons.play_circle_outline,
                              color: Colors.white54, size: 64)),

                    // Text overlays
                    ..._buildOverlays(screenSize.width, videoH),

                    // Trash zone
                    if (_isDragging)
                      Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: TrashZone(isOverTrash: _isOverTrash)),
                  ],
                ),
              ),

              // ── Tab bar ────────────────────────────────────────────────
              _buildTabBar(),

              // ── Active panel ───────────────────────────────────────────
              Container(
                height: _panel,
                color: Colors.black,
                child: _buildPanel(),
              ),

              SizedBox(height: botPad),
            ],
          ),

          // ── Text entry overlay ─────────────────────────────────────────
          if (_isTyping)
            Positioned.fill(
              child: TextEntryOverlay(
                controller: _textCtrl,
                focusNode: _textFocus,
                textColor: _tColor,
                fontSize: _tSize,
                isBold: _tBold,
                fontIndex: _tFont,
                onColorChanged: (c) => setState(() => _tColor = c),
                onSizeChanged: (v) => setState(() => _tSize = v),
                onBoldToggle: () => setState(() => _tBold = !_tBold),
                onFontChanged: (i) => setState(() => _tFont = i),
                onConfirm: _confirmText,
                onCancel: _cancelText,
                topPadding: topPad,
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab bar ──────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      height: _tabBar,
      color: const Color(0xFF111111),
      child: Row(
        children: _ActiveTab.values.map((tab) {
          final isActive = _activeTab == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (tab == _ActiveTab.text) {
                  _enterTextMode();
                  return;
                }
                setState(() => _activeTab = tab);
              },
              child: Container(
                color: Colors.transparent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_tabIcon(tab),
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.45),
                        size: 18),
                    const SizedBox(height: 2),
                    Text(_tabLabel(tab),
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withOpacity(0.45),
                          fontSize: 9,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.normal,
                        )),
                    if (isActive)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        height: 2,
                        width: 16,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPanel() {
    switch (_activeTab) {
      case _ActiveTab.filters:
        return FilterStrip(
          selectedIndex: _selectedFilterIndex,
          previewImage: null, // video — shows gradient tiles
          onSelect: (i) => setState(() => _selectedFilterIndex = i),
        );
      case _ActiveTab.adjust:
        return AdjustPanel(
          adjustments: _adj,
          onChanged: (a) => setState(() => _adj = a),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildOverlays(double w, double h) {
    return _overlays.asMap().entries.map((entry) {
      final index = entry.key;
      final o = entry.value;
      final draggingThis = _dragIndex == index;
      return Positioned(
        left: (o.position.dx * w).clamp(0.0, w - 10),
        top: (o.position.dy * h).clamp(0.0, h - 10),
        child: GestureDetector(
          onTap: () => setState(() => _selectedOverlayIndex = index),
          onPanStart: (_) => _onDragStart(index),
          onPanUpdate: (d) => _onDragUpdate(index, d, w, h),
          onPanEnd: (_) => _onDragEnd(index, h),
          child: AnimatedOpacity(
            opacity: (draggingThis && _isOverTrash) ? 0.4 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Stack(clipBehavior: Clip.none, children: [
              Text(o.text, style: overlayShadowStyle(o)),
              Text(o.text, style: overlayTextStyle(o)),
            ]),
          ),
        ),
      );
    }).toList();
  }

  IconData _tabIcon(_ActiveTab t) {
    switch (t) {
      case _ActiveTab.filters:
        return Icons.auto_fix_high_rounded;
      case _ActiveTab.adjust:
        return Icons.tune_rounded;
      case _ActiveTab.text:
        return Icons.text_fields_rounded;
    }
  }

  String _tabLabel(_ActiveTab t) {
    switch (t) {
      case _ActiveTab.filters:
        return 'Filters';
      case _ActiveTab.adjust:
        return 'Adjust';
      case _ActiveTab.text:
        return 'Text';
    }
  }
}

enum _ActiveTab { filters, adjust, text }
