import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Authentic ePaper refresh simulator (electronic shelf tags & Waveshare e-ink).
/// Real electrophoretic displays don't use soft gradients or standard fades.
/// They use voltage pulses that physically move charged micro-particles in stages:
/// 1. Ghosting erasure & polarity inversion flashes (black -> invert -> white clear)
/// 2. Granular horizontal sweep updating coarse pixel blocks
/// 3. Particle separation: Black/white micro-capsules pop into place
/// 4. Color pigments (Yellow, Red, Blue) electrostatically settle into place
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
    this.duration = const Duration(milliseconds: 3600),
  }) : super(key: key);

  @override
  State<EpaperRefreshView> createState() => _EpaperRefreshViewState();
}

class _EpaperRefreshViewState extends State<EpaperRefreshView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _ditheredUiImage;
  ui.Image? _rawUiImage;

  @override
  void initState() {
    super.initState();
    _decodeImages();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _controller.forward().then((_) {
      widget.onComplete();
    });
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
        color: const Color(0xFFE5E5DF),
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
                color: const Color(0xFFF7F7F2), // matte white e-ink bezel
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6D6CE), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
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
                            painter: _EpaperHardwarePainter(
                              progress: _controller.value,
                              ditheredImage: _ditheredUiImage!,
                              rawImage: _rawUiImage,
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
                      String statusText = "INITIALIZING WAVEFORM...";
                      if (p < 0.25) {
                        statusText = "CLEARING RESIDUAL PARTICLES";
                      } else if (p < 0.50) {
                        statusText = "POLARITY INVERSION CYCLE";
                      } else if (p < 0.75) {
                        statusText = "WRITING MONO INK MATRIX";
                      } else if (p < 0.95) {
                        statusText = "SETTLING SPECTRA-6 PIGMENTS";
                      } else {
                        statusText = "DISPLAY REFRESH READY";
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            statusText,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            "${(p * 100).toInt()}%",
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Colors.black54,
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

class _EpaperHardwarePainter extends CustomPainter {
  final double progress;
  final ui.Image ditheredImage;
  final ui.Image? rawImage;

  _EpaperHardwarePainter({
    required this.progress,
    required this.ditheredImage,
    this.rawImage,
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

    // E-ink paper background
    final paperPaint = Paint()..color = const Color(0xFFF2F2EC);
    canvas.drawRect(rect, paperPaint);

    final pixelPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;

    // STAGE 1: Polarity flashes & ghosting erasure (0.00 -> 0.35)
    // Real ePaper flashes black, then negative/invert, then clears to white
    if (progress < 0.12) {
      // Flash full black
      canvas.drawRect(rect, Paint()..color = const Color(0xFF1E1E1E));
      return;
    } else if (progress < 0.22) {
      // Invert flash (ghosting negation pulse)
      if (rawImage != null) {
        final invertPaint = Paint()
          ..colorFilter = const ColorFilter.matrix([
            -1,  0,  0, 0, 255,
             0, -1,  0, 0, 255,
             0,  0, -1, 0, 255,
             0,  0,  0, 1,   0,
          ]);
        canvas.drawImageRect(rawImage!, srcRect, rect, invertPaint);
      } else {
        canvas.drawRect(rect, Paint()..color = Colors.white);
      }
      return;
    } else if (progress < 0.35) {
      // Blank paper flash before writing
      canvas.drawRect(rect, Paint()..color = const Color(0xFFFAF9F5));
      return;
    }

    // STAGE 2: Stepped Pixel Line-by-Line / Block update (0.35 -> 0.75)
    // Like electronic price tags (ESL) updating line by line in discrete blocks
    if (progress < 0.75) {
      double writeProgress = (progress - 0.35) / (0.75 - 0.35); // 0.0 -> 1.0

      // Calculate discrete stepped scanline (quantized into visible physical blocks)
      const int totalBands = 24;
      int currentBand = (writeProgress * totalBands).floor();
      double bandHeight = size.height / totalBands;
      double revealedHeight = currentBand * bandHeight;

      // Draw grayscale/mono layer of dithered image for completed bands
      if (revealedHeight > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, revealedHeight));

        // High contrast black & white particle stage
        final monoPaint = Paint()
          ..filterQuality = FilterQuality.none
          ..colorFilter = const ColorFilter.matrix([
            0.33, 0.33, 0.33, 0, 0,
            0.33, 0.33, 0.33, 0, 0,
            0.33, 0.33, 0.33, 0, 0,
            0,    0,    0,    1, 0,
          ]);

        canvas.drawImageRect(ditheredImage, srcRect, rect, monoPaint);
        canvas.restore();
      }

      // Draw the active scanning bar (the high-voltage pulse line)
      if (currentBand < totalBands) {
        final activeRect = Rect.fromLTWH(
          0,
          revealedHeight,
          size.width,
          bandHeight,
        );
        // Flickers black/white while voltage is applied to the active row
        final isEven = (currentBand % 2 == 0);
        canvas.drawRect(
          activeRect,
          Paint()..color = isEven ? const Color(0xFF222222) : const Color(0xFFECECE7),
        );
      }
      return;
    }

    // STAGE 3: Pigment color separation & migration (0.75 -> 1.00)
    // On Spectra 6, colored pigments (Red, Yellow, Blue) take longer to migrate
    // than black/white, settling in granular waves
    double colorProgress = (progress - 0.75) / (1.00 - 0.75); // 0.0 -> 1.0

    // First draw the monochrome base
    final monoPaint = Paint()
      ..filterQuality = FilterQuality.none
      ..colorFilter = const ColorFilter.matrix([
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0,    0,    0,    1, 0,
      ]);
    canvas.drawImageRect(ditheredImage, srcRect, rect, monoPaint);

    // Reveal color pigments horizontally in a stepped electrical wave
    const int colorSteps = 16;
    int step = (colorProgress * colorSteps).floor();
    double stepWidth = size.width / colorSteps;
    double coloredWidth = step * stepWidth;

    if (coloredWidth > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, coloredWidth, size.height));
      canvas.drawImageRect(ditheredImage, srcRect, rect, pixelPaint);
      canvas.restore();
    }

    // Draw active color wave pulse line
    if (step < colorSteps && colorProgress < 0.98) {
      final activeColorBar = Rect.fromLTWH(coloredWidth, 0, stepWidth, size.height);
      canvas.drawRect(
        activeColorBar,
        Paint()
          ..color = const Color(0xFFD0BE47).withOpacity(0.35) // Yellow Spectra pigment pulse
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EpaperHardwarePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
