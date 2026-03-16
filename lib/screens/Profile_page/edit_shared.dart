// lib/screens/Profile_page/edit_shared.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// =============================================================================
// FILTERS
// =============================================================================

class EditFilter {
  final String name;
  final List<double> matrix;
  const EditFilter({required this.name, required this.matrix});
}

const List<EditFilter> kFilters = [
  EditFilter(name: 'Normal', matrix: [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Vivid', matrix: [
    1.4,
    -0.1,
    -0.1,
    0,
    0,
    -0.1,
    1.3,
    -0.1,
    0,
    0,
    -0.1,
    -0.1,
    1.4,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Warm', matrix: [
    1.2,
    0,
    0,
    0,
    15,
    0,
    1.0,
    0,
    0,
    5,
    0,
    0,
    0.8,
    0,
    -10,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Cool', matrix: [
    0.8,
    0,
    0,
    0,
    -10,
    0,
    1.0,
    0,
    0,
    5,
    0,
    0,
    1.2,
    0,
    15,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Noir', matrix: [
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Fade', matrix: [
    1,
    0,
    0,
    0,
    40,
    0,
    1,
    0,
    0,
    40,
    0,
    0,
    1,
    0,
    40,
    0,
    0,
    0,
    0.85,
    0,
  ]),
  EditFilter(name: 'Chrome', matrix: [
    0.78,
    0.15,
    0.07,
    0,
    0,
    0.07,
    0.84,
    0.09,
    0,
    0,
    0.07,
    0.07,
    0.86,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Lush', matrix: [
    0.9,
    0.1,
    0,
    0,
    10,
    0,
    1.1,
    0,
    0,
    5,
    0,
    0.1,
    0.9,
    0,
    10,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Sunset', matrix: [
    1.3,
    0.1,
    0,
    0,
    20,
    0,
    0.95,
    0,
    0,
    -5,
    0,
    0,
    0.7,
    0,
    -15,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Mist', matrix: [
    0.85,
    0.1,
    0.05,
    0,
    25,
    0.05,
    0.9,
    0.05,
    0,
    20,
    0.05,
    0.05,
    0.9,
    0,
    20,
    0,
    0,
    0,
    0.9,
    0,
  ]),
  EditFilter(name: 'Drama', matrix: [
    1.2,
    -0.1,
    0,
    0,
    -10,
    -0.1,
    1.2,
    -0.1,
    0,
    -10,
    0,
    -0.1,
    1.2,
    0,
    -10,
    0,
    0,
    0,
    1,
    0,
  ]),
  EditFilter(name: 'Pastel', matrix: [
    0.8,
    0.1,
    0.1,
    0,
    30,
    0.1,
    0.8,
    0.1,
    0,
    30,
    0.1,
    0.1,
    0.8,
    0,
    30,
    0,
    0,
    0,
    1,
    0,
  ]),
];

// =============================================================================
// ADJUSTMENTS
// =============================================================================

class EditAdjustments {
  final double brightness;
  final double contrast;
  final double saturation;
  final double warmth;

  const EditAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
  });

  EditAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
  }) =>
      EditAdjustments(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        warmth: warmth ?? this.warmth,
      );

  bool get isIdentity =>
      brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0;

  List<double> combinedMatrix(List<double> base) {
    var m = List<double>.from(base);
    final b = brightness / 100 * 80;
    m[4] += b;
    m[9] += b;
    m[14] += b;
    final c = (contrast / 100) + 1.0;
    final t = 128 * (1 - c);
    m[0] *= c;
    m[4] += t;
    m[6] *= c;
    m[9] += t;
    m[12] *= c;
    m[14] += t;
    final s = (saturation / 100) + 1.0;
    final invS = 1 - s;
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    m[0] = m[0] * (lr * invS + s);
    m[1] = m[1] * (lg * invS);
    m[2] = m[2] * (lb * invS);
    m[5] = m[5] * (lr * invS);
    m[6] = m[6] * (lg * invS + s);
    m[7] = m[7] * (lb * invS);
    m[10] = m[10] * (lr * invS);
    m[11] = m[11] * (lg * invS);
    m[12] = m[12] * (lb * invS + s);
    final w = warmth / 100 * 40;
    m[4] += w;
    m[14] -= w;
    return m;
  }
}

// =============================================================================
// CROP
// =============================================================================

enum CropAspect { free, square, fourFive, nineSixteen, sixteenNine, threeTwo }

extension CropAspectExt on CropAspect {
  String get label {
    switch (this) {
      case CropAspect.free:
        return 'Free';
      case CropAspect.square:
        return '1:1';
      case CropAspect.fourFive:
        return '4:5';
      case CropAspect.nineSixteen:
        return '9:16';
      case CropAspect.sixteenNine:
        return '16:9';
      case CropAspect.threeTwo:
        return '3:2';
    }
  }

  double? get ratio {
    switch (this) {
      case CropAspect.free:
        return null;
      case CropAspect.square:
        return 1.0;
      case CropAspect.fourFive:
        return 4 / 5;
      case CropAspect.nineSixteen:
        return 9 / 16;
      case CropAspect.sixteenNine:
        return 16 / 9;
      case CropAspect.threeTwo:
        return 3 / 2;
    }
  }
}

// =============================================================================
// BLUR
// =============================================================================

enum BlurType { none, portrait, tiltShift, radial, background }

extension BlurTypeExt on BlurType {
  String get label {
    switch (this) {
      case BlurType.none:
        return 'None';
      case BlurType.portrait:
        return 'Portrait';
      case BlurType.tiltShift:
        return 'Tilt-Shift';
      case BlurType.radial:
        return 'Radial';
      case BlurType.background:
        return 'Background';
    }
  }

  IconData get icon {
    switch (this) {
      case BlurType.none:
        return Icons.blur_off_rounded;
      case BlurType.portrait:
        return Icons.portrait_rounded;
      case BlurType.tiltShift:
        return Icons.swap_vert_rounded;
      case BlurType.radial:
        return Icons.radio_button_unchecked;
      case BlurType.background:
        return Icons.filter_tilt_shift_rounded;
    }
  }
}

// =============================================================================
// DRAW
// =============================================================================

enum DrawTool { brush, marker, highlight, eraser }

extension DrawToolExt on DrawTool {
  String get label {
    switch (this) {
      case DrawTool.brush:
        return 'Brush';
      case DrawTool.marker:
        return 'Marker';
      case DrawTool.highlight:
        return 'Highlight';
      case DrawTool.eraser:
        return 'Eraser';
    }
  }

  IconData get icon {
    switch (this) {
      case DrawTool.brush:
        return Icons.brush_rounded;
      case DrawTool.marker:
        return Icons.edit_rounded;
      case DrawTool.highlight:
        return Icons.highlight_rounded;
      case DrawTool.eraser:
        return Icons.auto_fix_normal_rounded;
    }
  }
}

class DrawStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final DrawTool tool;
  const DrawStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.tool,
  });
}

class DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final DrawStroke? currentStroke;
  DrawingPainter({required this.strokes, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in [...strokes, if (currentStroke != null) currentStroke!]) {
      _draw(canvas, s);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, DrawStroke s) {
    if (s.points.isEmpty) return;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (s.tool) {
      case DrawTool.brush:
        paint
          ..color = s.color
          ..strokeWidth = s.strokeWidth
          ..blendMode = BlendMode.srcOver;
        break;
      case DrawTool.marker:
        paint
          ..color = s.color
          ..strokeWidth = s.strokeWidth * 1.8
          ..blendMode = BlendMode.srcOver
          ..strokeCap = StrokeCap.square;
        break;
      case DrawTool.highlight:
        paint
          ..color = s.color.withOpacity(0.38)
          ..strokeWidth = s.strokeWidth * 3.0
          ..blendMode = BlendMode.srcOver
          ..strokeCap = StrokeCap.square;
        break;
      case DrawTool.eraser:
        paint
          ..color = Colors.transparent
          ..strokeWidth = s.strokeWidth * 2.5
          ..blendMode = BlendMode.clear;
        break;
    }

    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, paint.strokeWidth / 2, paint);
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length - 1; i++) {
      final p0 = s.points[i];
      final p1 = s.points[i + 1];
      path.quadraticBezierTo(
          p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    path.lineTo(s.points.last.dx, s.points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DrawingPainter old) => true;
}

// =============================================================================
// TEXT OVERLAY
// =============================================================================

class EditFont {
  final String label;
  final String? family;
  const EditFont({required this.label, this.family});
}

const List<EditFont> kFonts = [
  EditFont(label: 'Default', family: null),
  EditFont(label: 'Serif', family: 'Georgia'),
  EditFont(label: 'Mono', family: 'Courier'),
  EditFont(label: 'Classic', family: 'Times New Roman'),
  EditFont(label: 'Round', family: 'Helvetica Neue'),
];

class TextOverlay {
  String text;
  Offset position;
  Color color;
  double fontSize;
  bool isBold;
  int fontIndex;

  TextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
    this.fontSize = 28.0,
    this.isBold = true,
    this.fontIndex = 0,
  });

  TextOverlay copyWith({
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
    bool? isBold,
    int? fontIndex,
  }) =>
      TextOverlay(
        text: text ?? this.text,
        position: position ?? this.position,
        color: color ?? this.color,
        fontSize: fontSize ?? this.fontSize,
        isBold: isBold ?? this.isBold,
        fontIndex: fontIndex ?? this.fontIndex,
      );
}

const List<Color> kTextColors = [
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

const double kMinFontSize = 16.0;
const double kMaxFontSize = 72.0;
const double kTrashZoneH = 80.0;

TextStyle overlayTextStyle(TextOverlay o) => TextStyle(
      fontFamily: kFonts[o.fontIndex].family,
      fontSize: o.fontSize,
      fontWeight: o.isBold ? FontWeight.w800 : FontWeight.w400,
      color: o.color,
      shadows: const [
        Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54)
      ],
    );

TextStyle overlayShadowStyle(TextOverlay o) => TextStyle(
      fontFamily: kFonts[o.fontIndex].family,
      fontSize: o.fontSize,
      fontWeight: o.isBold ? FontWeight.w800 : FontWeight.w400,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withOpacity(0.45),
    );

// =============================================================================
// BLUR OVERLAY WIDGET
// Uses two image layers: blurred base + unblurred mask on top
// so the effect is baked in by RepaintBoundary.toImage()
// =============================================================================

class BlurOverlay extends StatelessWidget {
  final Uint8List imageBytes;
  final BlurType blurType;
  final double blurIntensity; // 1..25

  const BlurOverlay({
    Key? key,
    required this.imageBytes,
    required this.blurType,
    required this.blurIntensity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (blurType == BlurType.none) return const SizedBox.shrink();

    final sigma = blurIntensity;
    final blurredFull = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Image.memory(imageBytes,
          fit: BoxFit.contain, width: double.infinity, height: double.infinity),
    );

    switch (blurType) {
      // ── Portrait: keep oval centre sharp ──────────────────────────────────
      case BlurType.portrait:
      case BlurType.background:
        return LayoutBuilder(builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            blurredFull,
            ClipPath(
              clipper: _OvalKeepClipper(w, h, 0.5, 0.75),
              child: Image.memory(imageBytes,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity),
            ),
          ]);
        });

      // ── Tilt-shift: keep centre horizontal strip sharp ────────────────────
      case BlurType.tiltShift:
        return LayoutBuilder(builder: (ctx, constraints) {
          final h = constraints.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            blurredFull,
            ClipRect(
              clipper: _HorizontalBandClipper(h * 0.3, h * 0.7),
              child: Image.memory(imageBytes,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity),
            ),
          ]);
        });

      // ── Radial: keep circle centre sharp, blur outward ───────────────────
      case BlurType.radial:
        return LayoutBuilder(builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(fit: StackFit.expand, children: [
            blurredFull,
            ClipPath(
              clipper: _CircleKeepClipper(w / 2, h / 2, (w < h ? w : h) * 0.3),
              child: Image.memory(imageBytes,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity),
            ),
          ]);
        });

      default:
        return const SizedBox.shrink();
    }
  }
}

// Clip a rectangle keeping the oval INSIDE (inverse clip = keep oval, cut rest)
class _OvalKeepClipper extends CustomClipper<Path> {
  final double w, h, rx, ry;
  _OvalKeepClipper(this.w, this.h, this.rx, this.ry);
  @override
  Path getClip(Size size) => Path()
    ..addOval(Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * rx,
        height: size.height * ry));
  @override
  bool shouldReclip(_) => false;
}

class _HorizontalBandClipper extends CustomClipper<Rect> {
  final double top, bottom;
  _HorizontalBandClipper(this.top, this.bottom);
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, bottom);
  @override
  bool shouldReclip(_) => false;
}

class _CircleKeepClipper extends CustomClipper<Path> {
  final double cx, cy, radius;
  _CircleKeepClipper(this.cx, this.cy, this.radius);
  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
  @override
  bool shouldReclip(_) => false;
}

// =============================================================================
// CROP GUIDE OVERLAY
// =============================================================================

class CropGuideOverlay extends StatelessWidget {
  final CropAspect aspect;
  const CropGuideOverlay({Key? key, required this.aspect}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ratio = aspect.ratio;
    if (ratio == null) return const SizedBox.shrink();
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      double cropW, cropH;
      if (ratio >= 1) {
        cropW = w;
        cropH = (w / ratio).clamp(0, h);
        if (cropH > h) {
          cropH = h;
          cropW = h * ratio;
        }
      } else {
        cropH = h;
        cropW = (h * ratio).clamp(0, w);
        if (cropW > w) {
          cropW = w;
          cropH = w / ratio;
        }
      }

      final left = (w - cropW) / 2;
      final top = (h - cropH) / 2;
      final right = left + cropW;
      final bottom = top + cropH;

      return CustomPaint(
        size: Size(w, h),
        painter: _CropPainter(
          cropRect: Rect.fromLTRB(left, top, right, bottom),
        ),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  final Rect cropRect;
  _CropPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    // Dim outside
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.45);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(full),
          Path()..addRect(cropRect)),
      dimPaint,
    );

    // Crop border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(cropRect, borderPaint);

    // Rule-of-thirds grid
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 3; i++) {
      final x = cropRect.left + (cropRect.width / 3) * i;
      final y = cropRect.top + (cropRect.height / 3) * i;
      canvas.drawLine(
          Offset(x, cropRect.top), Offset(x, cropRect.bottom), gridPaint);
      canvas.drawLine(
          Offset(cropRect.left, y), Offset(cropRect.right, y), gridPaint);
    }

    // Corner handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const hl = 18.0;
    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      final dx = corner.dx == cropRect.left ? 1 : -1;
      final dy = corner.dy == cropRect.top ? 1 : -1;
      canvas.drawLine(corner, corner + Offset(hl * dx, 0), handlePaint);
      canvas.drawLine(corner, corner + Offset(0, hl * dy), handlePaint);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.cropRect != cropRect;
}

// =============================================================================
// SHARED PANELS
// =============================================================================

class FilterStrip extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Uint8List? previewImage;

  const FilterStrip({
    Key? key,
    required this.selectedIndex,
    required this.onSelect,
    this.previewImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: kFilters.length,
        itemBuilder: (ctx, i) {
          final isSelected = selectedIndex == i;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
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
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: previewImage != null
                          ? ColorFiltered(
                              colorFilter:
                                  ColorFilter.matrix(kFilters[i].matrix),
                              child: Image.memory(previewImage!,
                                  fit: BoxFit.cover))
                          : _VideoFilterTile(matrix: kFilters[i].matrix),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(kFilters[i].name,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withOpacity(0.45),
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VideoFilterTile extends StatelessWidget {
  final List<double> matrix;
  const _VideoFilterTile({required this.matrix});
  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B9FD4), Color(0xFFD4886B), Color(0xFF6BD4A5)],
          )),
        ),
      );
}

class AdjustPanel extends StatelessWidget {
  final EditAdjustments adjustments;
  final ValueChanged<EditAdjustments> onChanged;
  const AdjustPanel(
      {Key? key, required this.adjustments, required this.onChanged})
      : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 100,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _AdjSlider(
                icon: Icons.brightness_6_rounded,
                label: 'Brightness',
                value: adjustments.brightness,
                onChanged: (v) =>
                    onChanged(adjustments.copyWith(brightness: v))),
            _AdjSlider(
                icon: Icons.contrast_rounded,
                label: 'Contrast',
                value: adjustments.contrast,
                onChanged: (v) => onChanged(adjustments.copyWith(contrast: v))),
            _AdjSlider(
                icon: Icons.color_lens_rounded,
                label: 'Saturation',
                value: adjustments.saturation,
                onChanged: (v) =>
                    onChanged(adjustments.copyWith(saturation: v))),
            _AdjSlider(
                icon: Icons.thermostat_rounded,
                label: 'Warmth',
                value: adjustments.warmth,
                onChanged: (v) => onChanged(adjustments.copyWith(warmth: v))),
          ],
        ),
      );
}

class _AdjSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _AdjSlider(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
            const SizedBox(height: 2),
            SizedBox(
              height: 36,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withOpacity(0.25),
                  thumbColor: Colors.white,
                  overlayColor: Colors.white.withOpacity(0.15),
                ),
                child: Slider(
                    value: value, min: -100, max: 100, onChanged: onChanged),
              ),
            ),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 9),
                textAlign: TextAlign.center),
          ],
        ),
      );
}

// ── Crop panel ────────────────────────────────────────────────────────────────

class CropPanel extends StatelessWidget {
  final CropAspect selected;
  final ValueChanged<CropAspect> onSelect;
  const CropPanel({Key? key, required this.selected, required this.onSelect})
      : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 100,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: CropAspect.values.map((a) {
            final isSel = selected == a;
            return GestureDetector(
              onTap: () => onSelect(a),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSel ? Colors.white : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color:
                          isSel ? Colors.white : Colors.white.withOpacity(0.25),
                      width: 1.5),
                ),
                child: Text(a.label,
                    style: TextStyle(
                      color: isSel ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
            );
          }).toList(),
        ),
      );
}

// ── Blur panel ────────────────────────────────────────────────────────────────

class BlurPanel extends StatelessWidget {
  final BlurType selected;
  final double intensity;
  final ValueChanged<BlurType> onSelectType;
  final ValueChanged<double> onIntensityChanged;
  const BlurPanel({
    Key? key,
    required this.selected,
    required this.intensity,
    required this.onSelectType,
    required this.onIntensityChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 100,
        child: Column(
          children: [
            // Type selector row
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: BlurType.values.map((t) {
                  final isSel = selected == t;
                  return GestureDetector(
                    onTap: () => onSelectType(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSel
                            ? Colors.white
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSel
                                ? Colors.white
                                : Colors.white.withOpacity(0.2),
                            width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(t.icon,
                              size: 14,
                              color: isSel
                                  ? Colors.black
                                  : Colors.white.withOpacity(0.8)),
                          const SizedBox(width: 5),
                          Text(t.label,
                              style: TextStyle(
                                color: isSel ? Colors.black : Colors.white,
                                fontSize: 12,
                                fontWeight:
                                    isSel ? FontWeight.w700 : FontWeight.w500,
                              )),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            // Intensity slider (only when not None)
            if (selected != BlurType.none)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withOpacity(0.25),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withOpacity(0.15),
                  ),
                  child: Slider(
                    value: intensity,
                    min: 1,
                    max: 25,
                    onChanged: onIntensityChanged,
                  ),
                ),
              ),
          ],
        ),
      );
}

// ── Draw panel ────────────────────────────────────────────────────────────────

const List<Color> kDrawColors = [
  Colors.white,
  Colors.black,
  Colors.red,
  Colors.orange,
  Colors.yellow,
  Colors.green,
  Colors.blue,
  Colors.purple,
  Colors.pink,
  Colors.cyan,
  Colors.brown,
];

class DrawPanel extends StatelessWidget {
  final DrawTool tool;
  final Color color;
  final double strokeWidth;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final ValueChanged<DrawTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onSizeChanged;

  const DrawPanel({
    Key? key,
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.onUndo,
    required this.onClear,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onSizeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 100,
        child: Column(
          children: [
            // Row 1: tools + undo + clear
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  ...DrawTool.values.map((t) {
                    final isSel = tool == t;
                    return GestureDetector(
                      onTap: () => onToolChanged(t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel
                              ? Colors.white
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t.icon,
                              size: 14,
                              color: isSel
                                  ? Colors.black
                                  : Colors.white.withOpacity(0.8)),
                          const SizedBox(width: 5),
                          Text(t.label,
                              style: TextStyle(
                                color: isSel ? Colors.black : Colors.white,
                                fontSize: 12,
                                fontWeight:
                                    isSel ? FontWeight.w700 : FontWeight.w500,
                              )),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  // Undo
                  _IconBtn(icon: Icons.undo_rounded, onTap: onUndo),
                  const SizedBox(width: 8),
                  // Clear
                  _IconBtn(icon: Icons.delete_outline_rounded, onTap: onClear),
                ],
              ),
            ),
            // Row 2: colours + size
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: kDrawColors.map((c) {
                        final isSel = color == c;
                        return GestureDetector(
                          onTap: () => onColorChanged(c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            width: isSel ? 28 : 22,
                            height: isSel ? 28 : 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c,
                              border: Border.all(
                                  color: isSel
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.3),
                                  width: isSel ? 2.5 : 1),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // Size slider
                  SizedBox(
                    width: 90,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.25),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withOpacity(0.15),
                      ),
                      child: Slider(
                        value: strokeWidth,
                        min: 2,
                        max: 30,
                        onChanged: onSizeChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}

// =============================================================================
// TEXT ENTRY OVERLAY
// =============================================================================

class TextEntryOverlay extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color textColor;
  final double fontSize;
  final bool isBold;
  final int fontIndex;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onSizeChanged;
  final VoidCallback onBoldToggle;
  final ValueChanged<int> onFontChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final double topPadding;

  const TextEntryOverlay({
    Key? key,
    required this.controller,
    required this.focusNode,
    required this.textColor,
    required this.fontSize,
    required this.isBold,
    required this.fontIndex,
    required this.onColorChanged,
    required this.onSizeChanged,
    required this.onBoldToggle,
    required this.onFontChanged,
    required this.onConfirm,
    required this.onCancel,
    required this.topPadding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black.withOpacity(0.55),
        child: Column(children: [
          SizedBox(height: topPadding + 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              GestureDetector(
                  onTap: onCancel,
                  child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text('Cancel',
                          style:
                              TextStyle(color: Colors.white, fontSize: 15)))),
              Expanded(
                  child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: kTextColors.map((c) {
                      final sel = textColor == c;
                      return GestureDetector(
                          onTap: () => onColorChanged(c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: sel ? 28 : 22,
                            height: sel ? 28 : 22,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c,
                                border: Border.all(
                                    color: sel
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                                    width: sel ? 2.5 : 1.5)),
                          ));
                    }).toList()),
              )),
              GestureDetector(
                  onTap: onBoldToggle,
                  child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isBold
                              ? Colors.white
                              : Colors.white.withOpacity(0.15)),
                      child: Center(
                          child: Text('B',
                              style: TextStyle(
                                  color: isBold ? Colors.black : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900))))),
              GestureDetector(
                  onTap: onConfirm,
                  child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text('Done',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)))),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
              height: 36,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: kFonts.length,
                  itemBuilder: (ctx, i) {
                    final sel = fontIndex == i;
                    return GestureDetector(
                        onTap: () => onFontChanged(i),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: sel
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16)),
                            child: Text(kFonts[i].label,
                                style: TextStyle(
                                    fontFamily: kFonts[i].family,
                                    color: sel ? Colors.black : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600))));
                  })),
          Expanded(
              child: Stack(children: [
            Center(
                child: IntrinsicWidth(
                    child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textAlign: TextAlign.center,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onConfirm(),
              style: TextStyle(
                  fontFamily: kFonts[fontIndex].family,
                  color: textColor,
                  fontSize: fontSize,
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w400,
                  shadows: [
                    Shadow(
                        color: Colors.black.withOpacity(0.6),
                        offset: const Offset(1, 1),
                        blurRadius: 4)
                  ]),
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero),
              cursorColor: Colors.white,
            ))),
            Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: VerticalSizeSlider(
                    value: fontSize,
                    min: kMinFontSize,
                    max: kMaxFontSize,
                    onChanged: onSizeChanged)),
          ])),
          const SizedBox(height: 300),
        ]),
      );
}

// =============================================================================
// VERTICAL SIZE SLIDER
// =============================================================================

class VerticalSizeSlider extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const VerticalSizeSlider(
      {Key? key,
      required this.value,
      required this.min,
      required this.max,
      required this.onChanged})
      : super(key: key);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, c) {
        final trackH = c.maxHeight.isFinite ? c.maxHeight : 200.0;
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
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                      left: 17,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: Container(
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(1)))),
                  Positioned(
                      left: 17,
                      top: handleY,
                      bottom: 0,
                      width: 2,
                      child: Container(
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(1)))),
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
                                    offset: const Offset(0, 2))
                              ]),
                          child: const Icon(Icons.unfold_more,
                              size: 14, color: Colors.black54))),
                ])));
      });
}

// =============================================================================
// TRASH ZONE
// =============================================================================

class TrashZone extends StatelessWidget {
  final bool isOverTrash;
  const TrashZone({Key? key, required this.isOverTrash}) : super(key: key);
  @override
  Widget build(BuildContext context) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: kTrashZoneH,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isOverTrash
                  ? [Colors.red.withOpacity(0.75), Colors.red.withOpacity(0)]
                  : [
                      Colors.black.withOpacity(0.55),
                      Colors.black.withOpacity(0)
                    ])),
      child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isOverTrash ? 52 : 40,
                  height: isOverTrash ? 52 : 40,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOverTrash
                          ? Colors.red
                          : Colors.white.withOpacity(0.25),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.6), width: 1.5)),
                  child: Icon(isOverTrash ? Icons.delete : Icons.delete_outline,
                      color: Colors.white, size: isOverTrash ? 26 : 20)))));
}
