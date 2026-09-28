import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Authentic electronic price-tag (ESL) / E-Paper display refresh simulator.
///
/// Features:
/// - Matte, warm off-white paper background (#E8E6E0)
/// - Muted charcoal black (#21211F) & discrete e-ink states (white, light gray, dark gray, black)
/// - Abrupt rectangular pixel cluster flipping (no smooth opacity / alpha fades)
/// - Irregular spatial jitter (some micro-clusters flip slightly earlier/later)
/// - Physical waveform sequence:
///     0..120ms: Static previous image with initial pixel fragmentation
///     120..320ms: Harsh polarity inversion & chaotic black/white chunk flickering
///     320..500ms: Substrate paper clear with residual cluster noise
///     500..750ms: Blocky coalescence of new dithered image (dark contours snap in first)
///     750ms+: Complete static freeze lock (no glow, no movement)
class EpaperRefreshView extends StatefulWidget {
  final Uint8List rawImageBytes;
  final Uint8List ditheredImageBytes;
  final VoidCallback onComplete;
  final Duration duration;

  const EpaperRefreshView({
    Key? key,
    required this.rawImageBytes,
    required this.ditheredImageBytes,
    required this.onComplete,
    this.duration = const Duration(milliseconds: 780),
  }) : super(key: key);

  @override
  State<EpaperRefreshView> createState() => _EpaperRefreshViewState();
}

class _EpaperRefreshViewState extends State<EpaperRefreshView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _rawUiImage;
  ui.Image? _ditheredUiImage;

  // Spatial jitter threshold matrix for irregular block-level physical updates
  static const int _gridCols = 32;
  static const int _gridRows = 42;
  late final Float32List _jitterMap;

  @override
  void initState() {
    super.initState();
    _initJitterMap();
    _decodeImages();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  void _initJitterMap() {
    final rand = math.Random(1337);
    _jitterMap = Float32List(_gridCols * _gridRows);
    for (int i = 0; i < _jitterMap.length; i++) {
      // Deterministic spatial offset between -0.12 and +0.12
      _jitterMap[i] = (rand.nextDouble() - 0.5) * 0.24;
    }
  }

  Future<void> _decodeImages() async {
    final rawCodec = await ui.instantiateImageCodec(widget.rawImageBytes);
    final rawFrame = await rawCodec.getNextFrame();

    final ditheredCodec = await ui.instantiateImageCodec(widget.ditheredImageBytes);
    final ditheredFrame = await ditheredCodec.getNextFrame();

    if (mounted) {
      setState(() {
        _rawUiImage = rawFrame.image;
        _ditheredUiImage = ditheredFrame.image;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ditheredUiImage == null) {
      return Container(
        color: const Color(0xFFE8E6E0),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF21211F)),
          ),
        ),
      );
    }

    final aspectRatio = _ditheredUiImage!.width / _ditheredUiImage!.height;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            // Physical retail price-tag bezel mockup
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE8E6E0), // Matte warm off-white paper
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC8C6BF), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _RetailEpaperPainter(
                              progress: _controller.value,
                              rawImage: _rawUiImage,
                              ditheredImage: _ditheredUiImage!,
                              jitterMap: _jitterMap,
                              cols: _gridCols,
                              rows: _gridRows,
                            ),
                            size: Size.infinite,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final p = _controller.value;
                      String status;
                      if (p < 0.20) {
                        status = "ELECTROSTATIC POLARIZATION";
                      } else if (p < 0.50) {
                        status = "CLEARING CHARGE MEMORY";
                      } else if (p < 0.85) {
                        status = "PHYSICAL INK SNAP";
                      } else {
                        status = "DISPLAY LOCKED";
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            status,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4A4A46),
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            "REFRESH",
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7A7973),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetailEpaperPainter extends CustomPainter {
  final double progress; // 0.0 -> 1.0
  final ui.Image? rawImage;
  final ui.Image ditheredImage;
  final Float32List jitterMap;
  final int cols;
  final int rows;

  _RetailEpaperPainter({
    required this.progress,
    required this.rawImage,
    required this.ditheredImage,
    required this.jitterMap,
    required this.cols,
    required this.rows,
  });

  // Physical 4-level discrete e-ink states
  static const Color paperWhite = Color(0xFFE8E6E0);
  static const Color lightGray = Color(0xFFB5B3AC);
  static const Color darkGray = Color(0xFF555450);
  static const Color charcoalBlack = Color(0xFF21211F);

  @override
  void paint(Canvas canvas, Size size) {
    final dstRect = Offset.zero & size;
    final ditherSrcRect = Rect.fromLTWH(
      0,
      0,
      ditheredImage.width.toDouble(),
      ditheredImage.height.toDouble(),
    );

    // Default matte paper substrate
    canvas.drawRect(dstRect, Paint()..color = paperWhite);

    final pixelPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    // STAGE 5: Final static lock-in (>= 90%)
    if (progress >= 0.90) {
      canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, pixelPaint);
      return;
    }

    final double cellW = size.width / cols;
    final double cellH = size.height / rows;

    // STAGE 1: Initial disintegration & subtle breakdown (0.00 -> 0.18)
    if (progress < 0.18) {
      // Draw previous image
      if (rawImage != null) {
        final rawSrcRect = Rect.fromLTWH(0, 0, rawImage!.width.toDouble(), rawImage!.height.toDouble());
        canvas.drawImageRect(rawImage!, rawSrcRect, dstRect, pixelPaint);
      } else {
        canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, pixelPaint);
      }

      // Discrete pixel chunks begin to abruptly flip
      final flipPaint = Paint()..style = PaintingStyle.fill;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          final jitter = jitterMap[idx];
          final localT = progress + jitter;

          if (localT > 0.08) {
            final isDark = (idx * 17) % 3 == 0;
            flipPaint.color = isDark ? charcoalBlack : paperWhite;
            canvas.drawRect(
              Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
              flipPaint,
            );
          }
        }
      }
      return;
    }

    // STAGE 2: Harsh black/white polarity inversion & chaotic chunk flicker (0.18 -> 0.45)
    if (progress < 0.45) {
      // Rapid global polarity flash cycle
      final flashIndex = ((progress - 0.18) * 40).floor();
      final bool isBlackPulse = (flashIndex % 2 == 0);

      // Fill underlying screen with dominant pulse
      canvas.drawRect(dstRect, Paint()..color = isBlackPulse ? charcoalBlack : paperWhite);

      // Overlay chaotic opposing physical clusters
      final blockPaint = Paint()..style = PaintingStyle.fill;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          final jitter = jitterMap[idx];
          final localT = (progress - 0.18) / 0.27 + jitter;

          // Pseudorandom physical state flipping
          final stepVal = ((localT * 100) + idx * 7).toInt() % 7;
          if (stepVal == 0) {
            blockPaint.color = isBlackPulse ? paperWhite : charcoalBlack;
            canvas.drawRect(
              Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
              blockPaint,
            );
          } else if (stepVal == 1) {
            blockPaint.color = isBlackPulse ? lightGray : darkGray;
            canvas.drawRect(
              Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
              blockPaint,
            );
          }
        }
      }
      return;
    }

    // STAGE 3: Clean substrate reset with faint residual ghosting (0.45 -> 0.60)
    if (progress < 0.60) {
      canvas.drawRect(dstRect, Paint()..color = paperWhite);

      // Faint residual ghosting dots
      final ghostPaint = Paint()..style = PaintingStyle.fill;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          if ((idx * 31) % 11 == 0) {
            ghostPaint.color = ((idx % 2) == 0) ? lightGray : const Color(0xFFD4D2CA);
            canvas.drawRect(
              Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
              ghostPaint,
            );
          }
        }
      }
      return;
    }

    // STAGE 4: Blocky coalescence of new dithered image (0.60 -> 0.90)
    // Dark contours snap in first, followed by remaining pigment clusters
    final double snapT = (progress - 0.60) / 0.30; // 0.0 -> 1.0

    // Draw dithered image as source
    canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, pixelPaint);

    // Overlay unsettled clusters that haven't flipped yet
    final unsettledPaint = Paint()..style = PaintingStyle.fill;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final jitter = jitterMap[idx];
        final localThreshold = 0.5 + jitter; // Threshold around 0.5

        if (snapT < localThreshold) {
          // Has not snapped to final state yet: shows interim e-ink gray / white state
          final interimVal = (idx + (snapT * 20).toInt()) % 4;
          if (interimVal == 0) {
            unsettledPaint.color = paperWhite;
          } else if (interimVal == 1) {
            unsettledPaint.color = lightGray;
          } else if (interimVal == 2) {
            unsettledPaint.color = darkGray;
          } else {
            unsettledPaint.color = charcoalBlack;
          }

          canvas.drawRect(
            Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
            unsettledPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RetailEpaperPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
