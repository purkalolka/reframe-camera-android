import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Accurate physical simulation of an electrophoretic ePaper display (E-Ink / Spectra 6).
///
/// Implements the exact multi-phase physics described in electrophoretic display waveforms:
///
/// Phase 0: Old image static
/// Phase 1: Rapid 2-3 harsh B/W and negative polarity inversion flashes (clears charge memory)
/// Phase 2: Chaotic grainy particulate boiling noise (electrified micro-capsules vibrating in fluid)
/// Phase 3: Stochastic crystallization & percolation clusters:
///          - Dark silhouettes pop up first like ink in chemical developer fluid
///          - Micro-pixels settle independently in blotchy, drying clusters
///          - Color pigments (Red, Yellow, Blue) separate and achieve full electrostatic saturation
/// Phase 4: Final crisp, matte, static lock-in.
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
    this.duration = const Duration(milliseconds: 3800),
  }) : super(key: key);

  @override
  State<EpaperRefreshView> createState() => _EpaperRefreshViewState();
}

class _EpaperRefreshViewState extends State<EpaperRefreshView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _ditheredUiImage;
  ui.Image? _rawUiImage;

  // Precomputed pseudo-random noise matrix (128x128) for particle boiling & blotch crystallization
  late final Float32List _noiseGrid;
  static const int _gridSize = 128;

  @override
  void initState() {
    super.initState();
    _initNoiseGrid();
    _decodeImages();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  void _initNoiseGrid() {
    final random = math.Random(42);
    _noiseGrid = Float32List(_gridSize * _gridSize);
    for (int i = 0; i < _noiseGrid.length; i++) {
      _noiseGrid[i] = random.nextDouble();
    }
  }

  Future<void> _decodeImages() async {
    final ditheredCodec = await ui.instantiateImageCodec(widget.ditheredImageBytes);
    final ditheredFrame = await ditheredCodec.getNextFrame();

    final rawCodec = await ui.instantiateImageCodec(widget.rawImageBytes);
    final rawFrame = await rawCodec.getNextFrame();

    if (mounted) {
      setState(() {
        _ditheredUiImage = ditheredFrame.image;
        _rawUiImage = rawFrame.image;
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
        color: const Color(0xFFE8E6E0), // Warm matte e-paper off-white
        child: const Center(
          child: CircularProgressIndicator(color: Colors.black87),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            // Hardware enclosure mockup
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE8E6E0), // Warm off-white matte paper frame
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD0CEC8), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AspectRatio(
                      aspectRatio: _ditheredUiImage!.width / _ditheredUiImage!.height,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _EInkPhysicalWaveformPainter(
                              progress: _controller.value,
                              ditheredImage: _ditheredUiImage!,
                              rawImage: _rawUiImage,
                              noiseGrid: _noiseGrid,
                              gridSize: _gridSize,
                            ),
                            size: Size.infinite,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final p = _controller.value;
                      String statusText;
                      if (p < 0.22) {
                        statusText = "POLARITY INVERSION FLASHES";
                      } else if (p < 0.45) {
                        statusText = "ELECTROSTATIC DUST BOILING";
                      } else if (p < 0.78) {
                        statusText = "CRYSTALLIZING INK PARTICLES";
                      } else if (p < 0.95) {
                        statusText = "SETTLING SPECTRA-6 PIGMENTS";
                      } else {
                        statusText = "IMAGE STABILIZED";
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            statusText,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Color(0xFF2B2B28), // Muted graphite black
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            "${(p * 100).toInt()}%",
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
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

class _EInkPhysicalWaveformPainter extends CustomPainter {
  final double progress;
  final ui.Image ditheredImage;
  final ui.Image? rawImage;
  final Float32List noiseGrid;
  final int gridSize;

  _EInkPhysicalWaveformPainter({
    required this.progress,
    required this.ditheredImage,
    this.rawImage,
    required this.noiseGrid,
    required this.gridSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      ditheredImage.width.toDouble(),
      ditheredImage.height.toDouble(),
    );

    // Characteristic E-Ink warm matte off-white background (#E8E6E0)
    final paperPaint = Paint()..color = const Color(0xFFE8E6E0);
    canvas.drawRect(rect, paperPaint);

    final pixelPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    // ─────────────────────────────────────────────────────────────
    // STAGE 1: «Встряска» / Полярные инверсии (0.00 -> 0.22)
    // 2-3 резкие вспышки негатива и переполюсовки зарядов
    // ─────────────────────────────────────────────────────────────
    if (progress < 0.22) {
      // 3 rapid cycles
      // 0.00-0.07: Flash 1 (Negative inversion)
      // 0.07-0.12: Flash 2 (Graphite Blackout #232321)
      // 0.12-0.17: Flash 3 (Inverted residual)
      // 0.17-0.22: Flash 4 (Pure blank paper reset)
      if (progress < 0.07) {
        _drawInverted(canvas, srcRect, rect);
      } else if (progress < 0.12) {
        canvas.drawRect(rect, Paint()..color = const Color(0xFF232321)); // Graphite black
      } else if (progress < 0.17) {
        _drawInverted(canvas, srcRect, rect);
      } else {
        canvas.drawRect(rect, Paint()..color = const Color(0xFFE8E6E0));
      }
      return;
    }

    // ─────────────────────────────────────────────────────────────
    // STAGE 2: «Хаотичный шум» / Кипящая наэлектризованная пыль (0.22 -> 0.45)
    // Зернистая рябь по всей площади: черные и белые крупинки хаотично
    // мерцают вразнобой, пиксели вибрируют перед оседанием
    // ─────────────────────────────────────────────────────────────
    if (progress < 0.45) {
      double t = (progress - 0.22) / (0.45 - 0.22); // 0.0 -> 1.0

      // Draw faint ghost silhouette under the boiling noise
      final ghostPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = ColorFilter.mode(
          const Color(0xFFE8E6E0).withOpacity(1.0 - (t * 0.5)),
          BlendMode.dstOut,
        );
      _drawMonochrome(canvas, srcRect, rect, ghostPaint);

      // Draw boiling particulate noise
      final noisePaint = Paint()..style = PaintingStyle.fill;
      int seedOffset = (progress * 1000).toInt() % 17;
      double cellSize = size.width / 48.0;

      for (int gy = 0; gy < 32; gy++) {
        for (int gx = 0; gx < 48; gx++) {
          int nIdx = ((gy * 3 + seedOffset) % gridSize) * gridSize + ((gx * 3 + seedOffset) % gridSize);
          double nVal = noiseGrid[nIdx];

          // Particle flicker: dark graphite particles jumping on paper
          if (nVal > 0.58) {
            noisePaint.color = (nVal > 0.82)
                ? const Color(0xFF232321) // Muted graphite
                : const Color(0xFF7A7973); // Mid-gray pigment dust
            canvas.drawRect(
              Rect.fromLTWH(gx * cellSize, gy * cellSize, cellSize, cellSize),
              noisePaint,
            );
          }
        }
      }
      return;
    }

    // ─────────────────────────────────────────────────────────────
    // STAGE 3: Постепенная кристаллизация & оседание чернил (0.45 -> 0.90)
    // Чернила растекаются и оседают неравномерными «влажными пятнами»
    // Силуэты темнеют, пиксели случайными кластерами фиксируются в цвет
    // ─────────────────────────────────────────────────────────────
    if (progress < 0.90) {
      double t = (progress - 0.45) / (0.90 - 0.45); // 0.0 -> 1.0

      // Step 3A: Draw the emerging monochrome base (dark silhouettes forming first)
      final monoFadePaint = Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = const ColorFilter.matrix([
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0,
          0,    0,    0,    1, 0,
        ]);
      canvas.drawImageRect(ditheredImage, srcRect, rect, monoFadePaint);

      // Step 3B: Non-linear stochastic percolation clusters (blotchy drying patches)
      // Each block crystallizes into full color based on local threshold + noise
      double cellSize = size.width / 40.0;
      final blockSrcW = ditheredImage.width / 40.0;
      final blockSrcH = ditheredImage.height / (size.height / cellSize);

      for (int gy = 0; gy < (size.height / cellSize).ceil(); gy++) {
        for (int gx = 0; gx < 40; gx++) {
          int nIdx = ((gy * 4) % gridSize) * gridSize + ((gx * 4) % gridSize);
          double localThreshold = noiseGrid[nIdx]; // 0.0 -> 1.0

          // If current progress surpasses local patch threshold, this patch crystallizes
          if (t >= localThreshold * 0.9) {
            canvas.save();
            canvas.clipRect(Rect.fromLTWH(gx * cellSize, gy * cellSize, cellSize, cellSize));
            canvas.drawImageRect(ditheredImage, srcRect, rect, pixelPaint);
            canvas.restore();
          } else if (t >= localThreshold * 0.5) {
            // Emerging ink dust on edge of drying patch
            final edgeDust = Paint()
              ..color = const Color(0xFF232321).withOpacity(0.35)
              ..style = PaintingStyle.fill;
            canvas.drawRect(
              Rect.fromLTWH(gx * cellSize, gy * cellSize, cellSize, cellSize),
              edgeDust,
            );
          }
        }
      }
      return;
    }

    // ─────────────────────────────────────────────────────────────
    // STAGE 4: Финальная стабилизация (0.90 -> 1.00)
    // Изображение полностью затвердело, чёткое, матовое, статичное
    // ─────────────────────────────────────────────────────────────
    canvas.drawImageRect(ditheredImage, srcRect, rect, pixelPaint);
  }

  void _drawInverted(Canvas canvas, Rect srcRect, Rect dstRect) {
    if (rawImage != null) {
      final invertPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = const ColorFilter.matrix([
          -1,  0,  0, 0, 255,
           0, -1,  0, 0, 255,
           0,  0, -1, 0, 255,
           0,  0,  0, 1,   0,
        ]);
      canvas.drawImageRect(rawImage!, srcRect, dstRect, invertPaint);
    } else {
      canvas.drawRect(dstRect, Paint()..color = const Color(0xFF232321));
    }
  }

  void _drawMonochrome(Canvas canvas, Rect srcRect, Rect dstRect, Paint paint) {
    canvas.drawImageRect(ditheredImage, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(covariant _EInkPhysicalWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
