import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Simulates the physical refresh cycle of a 6-color Spectra 6 ePaper display.
/// The real ePaper cycles through physical particle movements:
/// 1. Flashes/clears (black/white invert wave)
/// 2. Granular pigment particle migration (dither noise)
/// 3. Color separation and settling into the final dithered image.
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
  late Animation<double> _animation;
  int _flashState = 0; // 0: normal, 1: invert, 2: black, 3: white
  Timer? _flickerTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    // E-ink flash waveform simulation in first 1.2 seconds
    int ticks = 0;
    _flickerTimer = Timer.periodic(const Duration(milliseconds: 140), (timer) {
      ticks++;
      if (ticks < 8) {
        setState(() {
          _flashState = ticks % 3;
        });
      } else {
        _flickerTimer?.cancel();
        setState(() {
          _flashState = 0;
        });
      }
    });

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _flickerTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        double progress = _animation.value;

        // Stage 1: ePaper clearing flashes (0.0 -> 0.35)
        if (progress < 0.35 && _flashState != 0) {
          Color flashColor = _flashState == 1 ? Colors.white : Colors.black87;
          return Container(
            color: flashColor,
            child: Center(
              child: Text(
                "REFRESHING EPAPER...",
                style: TextStyle(
                  color: _flashState == 1 ? Colors.black : Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        // Stage 2: Pigment manifestation wave
        // Waves of dithered picture replacing grayscale screen
        return Stack(
          fit: StackFit.expand,
          children: [
            // Background: dithered final image fading in
            Image.memory(
              widget.ditheredImageBytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none, // Preserve crisp dithered pixels!
            ),

            // Scanline / Ink curtain transition
            if (progress < 1.0)
              ClipRect(
                clipper: _InkWaveClipper(progress: progress),
                child: Container(
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Colors.black87,
                          strokeWidth: 2,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "CHARGING INK PARTICLES ${(progress * 100).toInt()}%",
                          style: const TextStyle(
                            color: Colors.black,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InkWaveClipper extends CustomClipper<Rect> {
  final double progress;
  _InkWaveClipper({required this.progress});

  @override
  Rect getClip(Size size) {
    // Reveal from top to bottom with slight scanline effect
    double top = size.height * progress;
    return Rect.fromLTRB(0, top, size.width, size.height);
  }

  @override
  bool shouldReclip(covariant _InkWaveClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
