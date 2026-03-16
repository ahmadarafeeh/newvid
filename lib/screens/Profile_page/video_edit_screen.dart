// lib/screens/Profile_page/video_edit_screen.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/video_trimmer.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';
import 'package:Ratedly/screens/Profile_page/edit_shared.dart';

// Tab order matches photo editor with Trim + Sound added.
enum _ActiveTab { trim, text, sound, filters, adjust, crop, blur, draw, rotate }

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
  // ── Preview player ─────────────────────────────────────────────────────────
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;

  // ── Trim ───────────────────────────────────────────────────────────────────
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isTrimPlaying = false;
  bool _isSavingTrim = false;
  bool _trimDirty = false;

  // ── Filter / Adjust ────────────────────────────────────────────────────────
  int _selectedFilterIndex = 0;
  EditAdjustments _adj = const EditAdjustments();

  // ── Crop ───────────────────────────────────────────────────────────────────
  Rect _cropRect = const Rect.fromLTRB(0, 0, 1, 1);
  CropAspect _cropAspect = CropAspect.free;

  // ── Blur ───────────────────────────────────────────────────────────────────
  BlurType _blurType = BlurType.none;
  double _blurIntensity = 8.0;

  // ── Draw ───────────────────────────────────────────────────────────────────
  final List<DrawStroke> _strokes = [];
  DrawStroke? _currentStroke;
  DrawTool _drawTool = DrawTool.brush;
  Color _drawColor = Colors.white;
  double _drawSize = 8.0;
  bool _isDrawing = false;

  // ── Text ───────────────────────────────────────────────────────────────────
  bool _isTyping = false;
  final List<TextOverlay> _overlays = [];
  int? _selectedOverlayIndex;
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  Color _tColor = Colors.white;
  double _tSize = 32.0;
  bool _tBold = true;
  int _tFont = 0;

  // ── Sound ──────────────────────────────────────────────────────────────────
  bool _isMuted = false;

  // ── Rotate ─────────────────────────────────────────────────────────────────
  int _rotationQuarters = 0;

  // ── Drag-to-trash ──────────────────────────────────────────────────────────
  bool _isDragging = false;
  int? _dragIndex;
  bool _isOverTrash = false;

  // ── Active tab ─────────────────────────────────────────────────────────────
  _ActiveTab _activeTab = _ActiveTab.trim;

  // ── Layout ─────────────────────────────────────────────────────────────────
  static const double _topBarH = 56.0;
  static const double _tabBarH = 44.0;
  static const double _panelH = 100.0;
  static const double _trimPanelH = 120.0;

  double get _currentPanelH =>
      _activeTab == _ActiveTab.trim ? _trimPanelH : _panelH;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _initPreviewPlayer();
    _trimmer.loadVideo(videoFile: widget.videoFile);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _trimmer.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _initPreviewPlayer() async {
    final c = VideoPlayerController.file(
      widget.videoFile,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await c.initialize();
    await c.setLooping(true);
    await c.setVolume(1.0);
    if (mounted) {
      setState(() {
        _videoController = c;
        _isVideoInitialized = true;
        _isPlaying = false;
      });
    }
  }

  // ===========================================================================
  // PLAY / PAUSE
  // ===========================================================================

  Future<void> _togglePlayPause() async {
    if (_videoController == null || !_isVideoInitialized) return;
    if (_isPlaying) {
      await _videoController!.pause();
    } else {
      await _videoController!.play();
    }
    if (mounted) setState(() => _isPlaying = _videoController!.value.isPlaying);
  }

  // ===========================================================================
  // SOUND
  // ===========================================================================

  Future<void> _toggleSound() async {
    if (_videoController == null) return;
    final muted = !_isMuted;
    await _videoController!.setVolume(muted ? 0.0 : 1.0);
    if (mounted) setState(() => _isMuted = muted);
  }

  // ===========================================================================
  // SILENCE & STOP  (before leaving screen)
  // ===========================================================================

  Future<void> _silenceAndStop() async {
    if (_videoController != null) {
      await _videoController!.setVolume(0.0);
      await _videoController!.pause();
    }
    if (mounted) setState(() => _isPlaying = false);
  }

  // ===========================================================================
  // TAB SWITCHING
  // ===========================================================================

  Future<void> _switchTab(_ActiveTab tab) async {
    if (tab == _ActiveTab.text) {
      _enterTextMode();
      return;
    }
    if (tab == _ActiveTab.sound) {
      _toggleSound();
      return;
    }
    if (tab == _ActiveTab.rotate) {
      _rotate();
      return;
    }

    // Pause preview when entering Trim; resume when leaving.
    if (tab == _ActiveTab.trim && _activeTab != _ActiveTab.trim) {
      await _videoController?.pause();
      if (mounted) setState(() => _isPlaying = false);
    }
    if (_activeTab == _ActiveTab.trim && tab != _ActiveTab.trim) {
      await _videoController?.play();
      if (mounted)
        setState(() => _isPlaying = _videoController?.value.isPlaying ?? false);
    }

    if (mounted)
      setState(() {
        _activeTab = tab;
        _isDrawing = false;
      });
  }

  // ===========================================================================
  // ROTATE
  // ===========================================================================

  void _rotate() =>
      setState(() => _rotationQuarters = (_rotationQuarters + 1) % 4);

  // ===========================================================================
  // CROP
  // ===========================================================================

  void _snapCropToAspect(CropAspect aspect) {
    setState(() => _cropAspect = aspect);
    final ratio = aspect.ratio;
    if (ratio == null) {
      setState(() => _cropRect = const Rect.fromLTRB(0, 0, 1, 1));
      return;
    }
    // Use controller's aspect ratio for accurate snapping.
    final videoRatio = (_videoController?.value.aspectRatio) ?? 1.0;
    double left, top, right, bottom;
    if (videoRatio >= ratio) {
      final normW = ratio / videoRatio;
      left = (1.0 - normW) / 2;
      right = 1.0 - left;
      top = 0.0;
      bottom = 1.0;
    } else {
      final normH = videoRatio / ratio;
      top = (1.0 - normH) / 2;
      bottom = 1.0 - top;
      left = 0.0;
      right = 1.0;
    }
    setState(() => _cropRect = Rect.fromLTRB(left, top, right, bottom));
  }

  // ===========================================================================
  // DRAW
  // ===========================================================================

  void _onDrawStart(DragStartDetails d) {
    setState(() {
      _isDrawing = true;
      _currentStroke = DrawStroke(
        points: [d.localPosition],
        color: _drawColor,
        strokeWidth: _drawSize,
        tool: _drawTool,
      );
    });
  }

  void _onDrawUpdate(DragUpdateDetails d) {
    if (!_isDrawing || _currentStroke == null) return;
    setState(() {
      _currentStroke = DrawStroke(
        points: [..._currentStroke!.points, d.localPosition],
        color: _currentStroke!.color,
        strokeWidth: _currentStroke!.strokeWidth,
        tool: _currentStroke!.tool,
      );
    });
  }

  void _onDrawEnd(DragEndDetails _) {
    if (_currentStroke != null) {
      setState(() {
        _strokes.add(_currentStroke!);
        _currentStroke = null;
        _isDrawing = false;
      });
    }
  }

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

  void _onTextDragStart(int i) => setState(() {
        _isDragging = true;
        _dragIndex = i;
        _selectedOverlayIndex = i;
        _isOverTrash = false;
      });

  void _onTextDragUpdate(int i, DragUpdateDetails d, double w, double h) {
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

  void _onTextDragEnd(int i, double h) {
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
  // NEXT
  // ===========================================================================

  Future<void> _onNext() async {
    await _silenceAndStop();
    if (!mounted) return;

    if (_trimDirty) {
      setState(() => _isSavingTrim = true);
      File? trimmedFile;
      try {
        await _trimmer.saveTrimmedVideo(
          startValue: _startValue,
          endValue: _endValue,
          onSave: (String? path) {
            if (path != null) trimmedFile = File(path);
          },
        );
      } catch (_) {}
      if (mounted) setState(() => _isSavingTrim = false);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AddPostScreen(
                    initialVideoFile: trimmedFile ?? widget.videoFile,
                    onPostUploaded: widget.onPostUploaded,
                  )));
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AddPostScreen(
                    initialVideoFile: widget.videoFile,
                    onPostUploaded: widget.onPostUploaded,
                  )));
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  List<double> get _currentMatrix =>
      _adj.combinedMatrix(kFilters[_selectedFilterIndex].matrix);

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    final videoH = screenSize.height -
        topPad -
        _topBarH -
        _tabBarH -
        _currentPanelH -
        botPad -
        8;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(children: [
        Column(children: [
          SizedBox(height: topPad),

          // ── Top bar ──────────────────────────────────────────────────────
          SizedBox(
            height: _topBarH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () async {
                      await _silenceAndStop();
                      if (mounted) Navigator.pop(context);
                    },
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
                    onTap: _isSavingTrim ? null : _onNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20)),
                      child: _isSavingTrim
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
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

          // ── Video area ───────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: videoH,
            child: Stack(children: [
              // ── Trim tab: Trimmer's VideoViewer ─────────────────────────
              if (_activeTab == _ActiveTab.trim)
                Positioned.fill(
                    child: Container(
                        color: Colors.black,
                        child: VideoViewer(trimmer: _trimmer))),

              // ── All other tabs: filtered + rotated preview ───────────────
              if (_activeTab != _ActiveTab.trim)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _activeTab == _ActiveTab.draw
                        ? null
                        : () {
                            setState(() => _selectedOverlayIndex = null);
                            _togglePlayPause();
                          },
                    onPanStart:
                        _activeTab == _ActiveTab.draw ? _onDrawStart : null,
                    onPanUpdate:
                        _activeTab == _ActiveTab.draw ? _onDrawUpdate : null,
                    onPanEnd: _activeTab == _ActiveTab.draw ? _onDrawEnd : null,
                    child: ClipRect(
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(_currentMatrix),
                        child: Transform.rotate(
                          angle: _rotationQuarters * 3.14159265 / 2,
                          child: _isVideoInitialized && _videoController != null
                              ? FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _videoController!.value.size.width,
                                    height: _videoController!.value.size.height,
                                    child: VideoPlayer(_videoController!),
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Blur overlay (BackdropFilter works on live video) ────────
              if (_activeTab != _ActiveTab.trim && _blurType != BlurType.none)
                Positioned.fill(
                    child: _VideoBlurOverlay(
                        blurType: _blurType, intensity: _blurIntensity)),

              // ── Draw strokes layer ───────────────────────────────────────
              if (_activeTab != _ActiveTab.trim)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: _activeTab != _ActiveTab.draw,
                    child: CustomPaint(
                      painter: DrawingPainter(
                          strokes: _strokes, currentStroke: _currentStroke),
                    ),
                  ),
                ),

              // ── Text overlays ────────────────────────────────────────────
              if (_activeTab != _ActiveTab.trim)
                ..._buildTextOverlays(screenSize.width, videoH),

              // ── Crop overlay (outside draw layer so handles stay on top) ─
              if (_activeTab == _ActiveTab.crop)
                Positioned.fill(
                  child: InteractiveCropOverlay(
                    cropRect: _cropRect,
                    onChanged: (r) => setState(() {
                      _cropRect = r;
                      _cropAspect = CropAspect.free;
                    }),
                  ),
                ),

              // ── Play/pause icon ──────────────────────────────────────────
              if (_activeTab != _ActiveTab.trim &&
                  _activeTab != _ActiveTab.draw &&
                  !_isPlaying)
                const Center(
                    child: Icon(Icons.play_circle_outline,
                        color: Colors.white54, size: 64)),

              // ── Draw cursor hint ─────────────────────────────────────────
              if (_activeTab == _ActiveTab.draw)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                      child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: _drawSize.clamp(6, 24),
                        height: _drawSize.clamp(6, 24),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _drawColor,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 1)),
                      ),
                      const SizedBox(width: 8),
                      Text(_drawTool.label,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12)),
                    ]),
                  )),
                ),

              // ── Trash zone ───────────────────────────────────────────────
              if (_isDragging)
                Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: TrashZone(isOverTrash: _isOverTrash)),
            ]),
          ),

          // ── Tab bar ──────────────────────────────────────────────────────
          _buildTabBar(),

          // ── Panel ────────────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _currentPanelH,
            color: Colors.black,
            child: _buildPanel(),
          ),

          SizedBox(height: botPad),
        ]),

        // ── Text entry overlay ───────────────────────────────────────────────
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
            topPadding: MediaQuery.of(context).padding.top,
          )),
      ]),
    );
  }

  // ===========================================================================
  // TAB BAR
  // ===========================================================================

  Widget _buildTabBar() {
    return Container(
      height: _tabBarH,
      color: const Color(0xFF111111),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _ActiveTab.values.map((tab) {
            final bool isActive =
                tab == _ActiveTab.sound ? !_isMuted : _activeTab == tab;

            return GestureDetector(
              onTap: () => _switchTab(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
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
                    // Underline only for panel-opening tabs.
                    if (tab != _ActiveTab.sound &&
                        tab != _ActiveTab.text &&
                        tab != _ActiveTab.rotate &&
                        _activeTab == tab)
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
            );
          }).toList(),
        ),
      ),
    );
  }

  // ===========================================================================
  // PANELS
  // ===========================================================================

  Widget _buildPanel() {
    switch (_activeTab) {
      case _ActiveTab.trim:
        return _buildTrimPanel();
      case _ActiveTab.filters:
        return FilterStrip(
            selectedIndex: _selectedFilterIndex,
            previewImage: null,
            onSelect: (i) => setState(() => _selectedFilterIndex = i));
      case _ActiveTab.adjust:
        return AdjustPanel(
            adjustments: _adj, onChanged: (a) => setState(() => _adj = a));
      case _ActiveTab.crop:
        return SnapCropPanel(
            selected: _cropAspect, onSnapToAspect: _snapCropToAspect);
      case _ActiveTab.blur:
        return BlurPanel(
          selected: _blurType,
          intensity: _blurIntensity,
          onSelectType: (t) => setState(() => _blurType = t),
          onIntensityChanged: (v) => setState(() => _blurIntensity = v),
        );
      case _ActiveTab.draw:
        return DrawPanel(
          tool: _drawTool,
          color: _drawColor,
          strokeWidth: _drawSize,
          onUndo: () => setState(() {
            if (_strokes.isNotEmpty) _strokes.removeLast();
          }),
          onClear: () => setState(() => _strokes.clear()),
          onToolChanged: (t) => setState(() => _drawTool = t),
          onColorChanged: (c) => setState(() => _drawColor = c),
          onSizeChanged: (v) => setState(() => _drawSize = v),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTrimPanel() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: TrimViewer(
          trimmer: _trimmer,
          viewerHeight: 54.0,
          viewerWidth: MediaQuery.of(context).size.width,
          maxVideoLength: const Duration(seconds: 60),
          onChangeStart: (v) {
            _startValue = v;
            _trimDirty = true;
          },
          onChangeEnd: (v) {
            _endValue = v;
            _trimDirty = true;
          },
          onChangePlaybackState: (playing) {
            if (mounted) setState(() => _isTrimPlaying = playing);
          },
        ),
      ),
      SizedBox(
          height: 46,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                try {
                  final playing = await _trimmer.videoPlaybackControl(
                      startValue: _startValue, endValue: _endValue);
                  if (mounted) setState(() => _isTrimPlaying = playing);
                } catch (_) {}
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.35), width: 1),
                ),
                child: Icon(
                    _isTrimPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20),
              ),
            ),
          )),
    ]);
  }

  // ===========================================================================
  // TEXT OVERLAYS
  // ===========================================================================

  List<Widget> _buildTextOverlays(double w, double h) {
    return _overlays.asMap().entries.map((entry) {
      final index = entry.key;
      final o = entry.value;
      final draggingThis = _dragIndex == index;
      return Positioned(
        left: (o.position.dx * w).clamp(0.0, w - 10),
        top: (o.position.dy * h).clamp(0.0, h - 10),
        child: GestureDetector(
          onTap: _activeTab != _ActiveTab.draw
              ? () => setState(() => _selectedOverlayIndex = index)
              : null,
          onPanStart: _activeTab != _ActiveTab.draw
              ? (_) => _onTextDragStart(index)
              : null,
          onPanUpdate: _activeTab != _ActiveTab.draw
              ? (d) => _onTextDragUpdate(index, d, w, h)
              : null,
          onPanEnd: _activeTab != _ActiveTab.draw
              ? (_) => _onTextDragEnd(index, h)
              : null,
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

  // ===========================================================================
  // ICONS & LABELS
  // ===========================================================================

  IconData _tabIcon(_ActiveTab t) {
    switch (t) {
      case _ActiveTab.trim:
        return Icons.content_cut_rounded;
      case _ActiveTab.filters:
        return Icons.auto_fix_high_rounded;
      case _ActiveTab.adjust:
        return Icons.tune_rounded;
      case _ActiveTab.crop:
        return Icons.crop_rounded;
      case _ActiveTab.blur:
        return Icons.blur_on_rounded;
      case _ActiveTab.draw:
        return Icons.brush_rounded;
      case _ActiveTab.text:
        return Icons.text_fields_rounded;
      case _ActiveTab.sound:
        return _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
      case _ActiveTab.rotate:
        return Icons.rotate_90_degrees_cw_rounded;
    }
  }

  String _tabLabel(_ActiveTab t) {
    switch (t) {
      case _ActiveTab.trim:
        return 'Trim';
      case _ActiveTab.filters:
        return 'Filters';
      case _ActiveTab.adjust:
        return 'Adjust';
      case _ActiveTab.crop:
        return 'Crop';
      case _ActiveTab.blur:
        return 'Blur';
      case _ActiveTab.draw:
        return 'Draw';
      case _ActiveTab.text:
        return 'Text';
      case _ActiveTab.sound:
        return 'Sound';
      case _ActiveTab.rotate:
        return 'Rotate';
    }
  }
}

// =============================================================================
// VIDEO BLUR OVERLAY
//
// Uses BackdropFilter (not BlurOverlay which requires static image bytes)
// so it composites live over whatever is rendered beneath it — the VideoPlayer.
// =============================================================================

class _VideoBlurOverlay extends StatelessWidget {
  final BlurType blurType;
  final double intensity;

  const _VideoBlurOverlay({required this.blurType, required this.intensity});

  @override
  Widget build(BuildContext context) {
    if (blurType == BlurType.none) return const SizedBox.shrink();

    final filter = ui.ImageFilter.blur(sigmaX: intensity, sigmaY: intensity);

    switch (blurType) {
      // Portrait / background: blur everything, keep a centred oval sharp.
      case BlurType.portrait:
      case BlurType.background:
        return LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            // Full blur.
            BackdropFilter(
                filter: filter,
                child: const ColoredBox(color: Colors.transparent)),
            // Cut the oval back out — an unblurred transparent hole.
            ClipPath(
              clipper: _OvalHoleClipper(w * 0.5, h * 0.75),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ]);
        });

      // Tilt-shift: blur top & bottom bands, keep centre strip sharp.
      case BlurType.tiltShift:
        return LayoutBuilder(builder: (_, c) {
          final h = c.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            // Top band blur.
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: h * 0.3,
                child: BackdropFilter(
                    filter: filter,
                    child: const ColoredBox(color: Colors.transparent))),
            // Bottom band blur.
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: h * 0.3,
                child: BackdropFilter(
                    filter: filter,
                    child: const ColoredBox(color: Colors.transparent))),
          ]);
        });

      // Radial: blur everything, keep a centred circle sharp.
      case BlurType.radial:
        return LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            BackdropFilter(
                filter: filter,
                child: const ColoredBox(color: Colors.transparent)),
            ClipPath(
              clipper: _CircleHoleClipper(w / 2, h / 2, (w < h ? w : h) * 0.3),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ]);
        });

      default:
        return const SizedBox.shrink();
    }
  }
}

class _OvalHoleClipper extends CustomClipper<Path> {
  final double rx, ry;
  const _OvalHoleClipper(this.rx, this.ry);
  @override
  Path getClip(Size s) => Path()
    ..addOval(Rect.fromCenter(
        center: Offset(s.width / 2, s.height / 2), width: rx, height: ry));
  @override
  bool shouldReclip(_) => false;
}

class _CircleHoleClipper extends CustomClipper<Path> {
  final double cx, cy, r;
  const _CircleHoleClipper(this.cx, this.cy, this.r);
  @override
  Path getClip(Size s) =>
      Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
  @override
  bool shouldReclip(_) => false;
}
