// lib/screens/Profile_page/edit_shared.dart
//
// Shared models, constants and widgets used by both MediaEditScreen (photo)
// and VideoEditScreen (video).

import 'dart:typed_data';
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
// ADJUSTMENTS  (brightness / contrast / saturation / warmth)
// =============================================================================

class EditAdjustments {
  final double brightness; // -100 … 100
  final double contrast; // -100 … 100
  final double saturation; // -100 … 100
  final double warmth; // -100 … 100

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

  /// Combines filter matrix + adjustments into one 5×4 matrix for
  /// ColorFilter.matrix().
  List<double> combinedMatrix(List<double> filterMatrix) {
    // Start from filter matrix
    var m = List<double>.from(filterMatrix);

    // Brightness: add offset to R G B channels
    final b = brightness / 100 * 80; // scale to ±80 offset
    m[4] += b;
    m[9] += b;
    m[14] += b;

    // Contrast: scale around mid-point (0.5 in 0-1 space = 128 in 0-255)
    final c = (contrast / 100) + 1.0; // 0 → 1.0, 100 → 2.0, -100 → 0
    final t = 128 * (1 - c);
    m[0] *= c;
    m[4] += t;
    m[6] *= c;
    m[9] += t;
    m[12] *= c;
    m[14] += t;

    // Saturation: mix toward greyscale
    final s = (saturation / 100) + 1.0; // 0 → 1.0
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

    // Warmth: boost red, reduce blue (or vice-versa)
    final w = warmth / 100 * 40;
    m[4] += w;
    m[14] -= w;

    return m;
  }
}

// =============================================================================
// FONT OPTIONS
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

// =============================================================================
// TEXT OVERLAY MODEL
// =============================================================================

class TextOverlay {
  String text;
  Offset position; // fractional 0..1
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

// =============================================================================
// SHARED WIDGETS
// =============================================================================

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

// ── Filter strip ──────────────────────────────────────────────────────────────

class FilterStrip extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Uint8List?
      previewImage; // non-null for photos; null for video (show name only)

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
                        width: 2.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: previewImage != null
                          ? ColorFiltered(
                              colorFilter:
                                  ColorFilter.matrix(kFilters[i].matrix),
                              child: Image.memory(previewImage!,
                                  fit: BoxFit.cover),
                            )
                          // Video: coloured gradient tile
                          : _VideoFilterTile(
                              matrix: kFilters[i].matrix,
                              isSelected: isSelected,
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kFilters[i].name,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.45),
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Coloured gradient tile used as filter preview for video (no frame available)
class _VideoFilterTile extends StatelessWidget {
  final List<double> matrix;
  final bool isSelected;
  const _VideoFilterTile({required this.matrix, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B9FD4), Color(0xFFD4886B), Color(0xFF6BD4A5)],
          ),
        ),
      ),
    );
  }
}

// ── Adjustments panel ─────────────────────────────────────────────────────────

class AdjustPanel extends StatelessWidget {
  final EditAdjustments adjustments;
  final ValueChanged<EditAdjustments> onChanged;

  const AdjustPanel({
    Key? key,
    required this.adjustments,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _AdjustSlider(
            icon: Icons.brightness_6_rounded,
            label: 'Brightness',
            value: adjustments.brightness,
            onChanged: (v) => onChanged(adjustments.copyWith(brightness: v)),
          ),
          _AdjustSlider(
            icon: Icons.contrast_rounded,
            label: 'Contrast',
            value: adjustments.contrast,
            onChanged: (v) => onChanged(adjustments.copyWith(contrast: v)),
          ),
          _AdjustSlider(
            icon: Icons.color_lens_rounded,
            label: 'Saturation',
            value: adjustments.saturation,
            onChanged: (v) => onChanged(adjustments.copyWith(saturation: v)),
          ),
          _AdjustSlider(
            icon: Icons.thermostat_rounded,
            label: 'Warmth',
            value: adjustments.warmth,
            onChanged: (v) => onChanged(adjustments.copyWith(warmth: v)),
          ),
        ],
      ),
    );
  }
}

class _AdjustSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _AdjustSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
          const SizedBox(height: 4),
          // Vertical slider track
          SizedBox(
            height: 36,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withOpacity(0.25),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withOpacity(0.15),
              ),
              child: Slider(
                value: value,
                min: -100,
                max: 100,
                onChanged: onChanged,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Text entry overlay ────────────────────────────────────────────────────────

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
  Widget build(BuildContext context) {
    return Container(
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
                  onTap: onCancel,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ),
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
                                width: sel ? 2.5 : 1.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Bold
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
                          : Colors.white.withOpacity(0.15),
                    ),
                    child: Center(
                      child: Text('B',
                          style: TextStyle(
                            color: isBold ? Colors.black : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          )),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onConfirm,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('Done',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        )),
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
              itemCount: kFonts.length,
              itemBuilder: (ctx, i) {
                final sel = fontIndex == i;
                return GestureDetector(
                  onTap: () => onFontChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          sel ? Colors.white : Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(kFonts[i].label,
                        style: TextStyle(
                          fontFamily: kFonts[i].family,
                          color: sel ? Colors.black : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                );
              },
            ),
          ),

          // Text field + size slider
          Expanded(
            child: Stack(
              children: [
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
                            blurRadius: 4,
                          )
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
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: VerticalSizeSlider(
                    value: fontSize,
                    min: kMinFontSize,
                    max: kMaxFontSize,
                    onChanged: onSizeChanged,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 300),
        ],
      ),
    );
  }
}

// ── Vertical size slider ──────────────────────────────────────────────────────

class VerticalSizeSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const VerticalSizeSlider({
    Key? key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  }) : super(key: key);

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
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
                left: 17,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(
                    decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(1),
                ))),
            Positioned(
                left: 17,
                top: handleY,
                bottom: 0,
                width: 2,
                child: Container(
                    decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(1),
                ))),
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
                      )
                    ],
                  ),
                  child: const Icon(Icons.unfold_more,
                      size: 14, color: Colors.black54),
                )),
          ]),
        ),
      );
    });
  }
}

// ── Trash zone ────────────────────────────────────────────────────────────────

class TrashZone extends StatelessWidget {
  final bool isOverTrash;
  const TrashZone({Key? key, required this.isOverTrash}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: kTrashZoneH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: isOverTrash
              ? [Colors.red.withOpacity(0.75), Colors.red.withOpacity(0.0)]
              : [Colors.black.withOpacity(0.55), Colors.black.withOpacity(0.0)],
        ),
      ),
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
              color: isOverTrash ? Colors.red : Colors.white.withOpacity(0.25),
              border:
                  Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
            ),
            child: Icon(
              isOverTrash ? Icons.delete : Icons.delete_outline,
              color: Colors.white,
              size: isOverTrash ? 26 : 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Edit tool button ──────────────────────────────────────────────────────────

class EditToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const EditToolButton({
    Key? key,
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.9)
                  : Colors.white.withOpacity(0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: isActive ? Colors.black : Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.65),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
              )),
        ],
      ),
    );
  }
}
