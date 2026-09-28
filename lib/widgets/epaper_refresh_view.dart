import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Authentic electronic price-tag (ESL) / E-Paper display refresh simulator.
///
/// Features physical multi-phase electrophoretic waveform behavior:
/// - Phase 1: Disintegration & Initial Pixel Cluster Breakdown
/// - Phase 2: Harsh Multi-Pulse Polarity Flashes (Negative -> Dark Slate -> Negative -> White Clear)
/// - Phase 3: Chaotic Grainy Electric Dust & Pixel Chattering (unsettled charged microcapsules)
/// - Phase 4: Substrate Paper Wash with Faint Ghosting
/// - Phase 5: Progressive Ink Snapping (dark contours freeze in first, colors lock in with slight delay)
/// - Phase 6: Final Crisp Freeze Lock (static paper-like appearance)
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
    this.duration = const Duration(milliseconds: 3200),
  }) : super(key: key);

  @override
  State<EpaperRefreshView> createState() => _EpaperRefreshViewState();
}

class _EpaperRefreshViewState extends State<EpaperRefreshView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _rawUiImage;
  ui.Image? _ditheredUiImage;
  bool _isImagesDecoded = false;
  bool _isDisposed = false;

  // Spatial jitter threshold matrix for irregular physical cluster updates
  static const int _gridCols = 36;
  static const int _gridRows = 48;
  late final Float32List _jitterMap;

  @override
  void initState() {
    super.initState();
    _initJitterMap();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          widget.onComplete();
        }
      }
    });

    _decodeImages();
  }

  void _initJitterMap() {
    final rand = math.Random(42);
    _jitterMap = Float32List(_gridCols * _gridRows);
    for (int i = 0; i < _jitterMap.length; i++) {
      _jitterMap[i] = (rand.nextDouble() - 0.5) * 0.22;
    }
  }

  Future<void> _decodeImages() async {
    try {
      final rawCodec = await ui.instantiateImageCodec(widget.rawImageBytes);
      final rawFrame = await rawCodec.getNextFrame();

      final ditheredCodec = await ui.instantiateImageCodec(widget.ditheredImageBytes);
      final ditheredFrame = await ditheredCodec.getNextFrame();

      if (mounted && !_isDisposed) {
        setState(() {
          _rawUiImage = rawFrame.image;
          _ditheredUiImage = ditheredFrame.image;
          _isImagesDecoded = true;
        });
        // Start animation strictly after images are decoded to prevent skipped flashes
        _controller.forward();
      } else {
        rawFrame.image.dispose();
        ditheredFrame.image.dispose();
      }
    } catch (e) {
      debugPrint("EpaperRefreshView decode error: $e");
      if (mounted && !_isDisposed) {
        widget.onComplete();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    _rawUiImage?.dispose();
    _ditheredUiImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isImagesDecoded || _ditheredUiImage == null) {
      return Container(
        color: const Color(0xFFE8E6E0),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            // Physical retail price-tag bezel mockup
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE8E6E0), // Warm matte e-paper
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC8C6BF), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 24,
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
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final p = _controller.value;
                      String status;
                      if (p < 0.15) {
                        status = "WAVEFORM INIT: DISINTEGRATION";
                      } else if (p < 0.42) {
                        status = "HIGH-VOLTAGE POLARITY FLASHES";
                      } else if (p < 0.65) {
                        status = "PARTICULATE DUST & CHATTER";
                      } else if (p < 0.90) {
                        status = "ELECTROSTATIC PIGMENT LOCK";
                      } else {
                        status = "DISPLAY FROZEN (STATIC)";
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
                              color: Color(0xFF383834),
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            "${(p * 100).toInt()}%",
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6B6A66),
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

    // Warm matte paper substrate
    canvas.drawRect(dstRect, Paint()..color = paperWhite);

    final pixelPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    // STAGE 6: Final static freeze (>= 92%)
    if (progress >= 0.92) {
      canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, pixelPaint);
      return;
    }

    final double cellW = size.width / cols;
    final double cellH = size.height / rows;

    // ─────────────────────────────────────────────────────────────
    // PHASE 1: DISINTEGRATION (0.00 -> 0.15)
    // Old image starts breaking apart into small flipping blocks
    // ─────────────────────────────────────────────────────────────
    if (progress < 0.15) {
      if (rawImage != null) {
        final rawSrcRect = Rect.fromLTWH(0, 0, rawImage!.width.toDouble(), rawImage!.height.toDouble());
        canvas.drawImageRect(rawImage!, rawSrcRect, dstRect, pixelPaint);
      } else {
        canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, pixelPaint);
      }

      final double t = progress / 0.15;
      final flipPaint = Paint()..style = PaintingStyle.fill;

      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          final jitter = jitterMap[idx];
          if (t + jitter > 0.45) {
            final isDark = (idx * 19) % 3 == 0;
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

    // ─────────────────────────────────────────────────────────────
    // PHASE 2: HARSH MULTI-PULSE POLARITY FLASHES (0.15 -> 0.42)
    // 4 distinct global voltage polarity jolts erasing charge memory:
    // 0.15 - 0.22: Inverted snapshot flash
    // 0.22 - 0.29: Full dark charcoal blackout (#21211F)
    // 0.29 - 0.36: Harsh inverted color negative pulse
    // 0.36 - 0.42: Pure off-white paper clear (#E8E6E0)
    // ─────────────────────────────────────────────────────────────
    if (progress < 0.42) {
      if (progress < 0.22) {
        // Flash 1: Inverted raw/current image
        final invertPaint = Paint()
          ..filterQuality = FilterQuality.none
          ..colorFilter = const ColorFilter.matrix([
            -1,  0,  0, 0, 255,
             0, -1,  0, 0, 255,
             0,  0, -1, 0, 255,
             0,  0,  0, 1,   0,
          ]);
        if (rawImage != null) {
          final rawSrcRect = Rect.fromLTWH(0, 0, rawImage!.width.toDouble(), rawImage!.height.toDouble());
          canvas.drawImageRect(rawImage!, rawSrcRect, dstRect, invertPaint);
        } else {
          canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, invertPaint);
        }
      } else if (progress < 0.29) {
        // Flash 2: Solid graphite blackout
        canvas.drawRect(dstRect, Paint()..color = charcoalBlack);
      } else if (progress < 0.36) {
        // Flash 3: Inverted dithered jolt
        final invertPaint = Paint()
          ..filterQuality = FilterQuality.none
          ..colorFilter = const ColorFilter.matrix([
            -1,  0,  0, 0, 255,
             0, -1,  0, 0, 255,
             0,  0, -1, 0, 255,
             0,  0,  0, 1,   0,
          ]);
        canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, invertPaint);
      } else {
        // Flash 4: Pure paper clear
        canvas.drawRect(dstRect, Paint()..color = paperWhite);
      }

      // Add discrete flipping cluster chatter on top of the flashes
      final blockPaint = Paint()..style = PaintingStyle.fill;
      final flashTick = (progress * 50).toInt();
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          if ((idx + flashTick) % 7 == 0) {
            blockPaint.color = ((idx % 2) == 0) ? charcoalBlack : paperWhite;
            canvas.drawRect(
              Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
              blockPaint,
            );
          }
        }
      }
      return;
    }

    // ─────────────────────────────────────────────────────────────
    // PHASE 3: ELECTRIC PARTICULATE DUST & CHATTER (0.42 -> 0.65)
    // Particles vibrating in fluid, with faint ghost silhouette beneath
    // ─────────────────────────────────────────────────────────────
    if (progress < 0.65) {
      final double dustT = (progress - 0.42) / (0.65 - 0.42);

      // Faint ghost monochrome silhouette emerging under the dust
      final ghostPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0, dustT * 0.4, 0,
        ]);
      canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, ghostPaint);

      // Discrete pixel cluster noise (simulating charged microcapsules)
      final dustPaint = Paint()..style = PaintingStyle.fill;
      final int stepTick = (progress * 70).toInt();

      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          final val = (idx * 31 + stepTick * 11) % 17;
          if (val < 4) {
            if (val == 0) dustPaint.color = charcoalBlack;
            else if (val == 1) dustPaint.color = darkGray;
            else if (val == 2) dustPaint.color = lightGray;
            else dustPaint.color = paperWhite;

            canvas.drawRect(
              Rect.fromLTWH(c * cellW, r * cellH, cellW + 0.5, cellH + 0.5),
              dustPaint,
            );
          }
        }
      }
      return;
    }

    // ─────────────────────────────────────────────────────────────
    // PHASE 4 & 5: PROGRESSIVE INK SNAPPING & CRYSTALLIZATION (0.65 -> 0.92)
    // Dark contours snap in first in high-contrast mono,
    // then colored pigments latch into place block by block.
    // ─────────────────────────────────────────────────────────────
    final double snapT = (progress - 0.65) / (0.92 - 0.65); // 0.0 -> 1.0

    // Draw base dithered image
    canvas.drawImageRect(ditheredImage, ditherSrcRect, dstRect, pixelPaint);

    final unsettledPaint = Paint()..style = PaintingStyle.fill;
    final int tick = (snapT * 25).toInt();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final jitter = jitterMap[idx];
        final localThreshold = 0.5 + jitter;

        // Clusters that have not stabilized yet show discrete intermediate flips
        if (snapT < localThreshold) {
          final val = (idx + tick) % 5;
          if (val == 0) {
            unsettledPaint.color = charcoalBlack;
          } else if (val == 1) {
            unsettledPaint.color = darkGray;
          } else if (val == 2) {
            unsettledPaint.color = lightGray;
          } else {
            unsettledPaint.color = paperWhite;
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
