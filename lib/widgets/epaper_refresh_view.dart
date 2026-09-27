import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Authentic e-paper physical refresh sequencer.
/// Real e-ink / electronic price tags do NOT have linear moving waves or directional scanlines.
/// They update the ENTIRE display at once through rapid, discrete, jarring voltage polarity pulses (waveform flashes):
/// - Flash 1: Negative / Invert of the capture
/// - Flash 2: Full dark graphite blackout pulse
/// - Flash 3: Clean off-white paper pulse
/// - Flash 4: Inverted color polarity jolt
/// - Flash 5: High-contrast monochrome ghost snapshot
/// - Final: Crisp static settling of the final Spectra 6 dithered image.
class EpaperRefreshView extends StatefulWidget {
  final Uint8List rawImageBytes;
  final Uint8List ditheredImageBytes;
  final VoidCallback onComplete;

  const EpaperRefreshView({
    Key? key,
    required this.rawImageBytes,
    required this.ditheredImageBytes,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<EpaperRefreshView> createState() => _EpaperRefreshViewState();
}

enum _EpaperFlashStep {
  initialNegative, // Negative flash (inverted pixels)
  graphiteBlackout, // Solid dark slate/graphite erase (#21211F)
  paperWhiteout, // Solid off-white paper clear (#E8E6E0)
  invertJolt, // Harsh color negative jolt
  ghostMono, // High-contrast b&w intermediate settling
  finalSettled, // Locked final Spectra-6 dithered image
}

class _EpaperRefreshViewState extends State<EpaperRefreshView> {
  _EpaperFlashStep _currentStep = _EpaperFlashStep.initialNegative;
  Timer? _stepTimer;

  // Discrete real-world e-paper waveform timing sequence (in milliseconds)
  final List<MapEntry<_EpaperFlashStep, int>> _sequence = const [
    MapEntry(_EpaperFlashStep.initialNegative, 220),
    MapEntry(_EpaperFlashStep.graphiteBlackout, 180),
    MapEntry(_EpaperFlashStep.paperWhiteout, 190),
    MapEntry(_EpaperFlashStep.invertJolt, 200),
    MapEntry(_EpaperFlashStep.ghostMono, 240),
    MapEntry(_EpaperFlashStep.finalSettled, 350),
  ];

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _runNextStep();
  }

  void _runNextStep() {
    if (_currentIndex >= _sequence.length) {
      widget.onComplete();
      return;
    }

    final entry = _sequence[_currentIndex];
    setState(() {
      _currentStep = entry.key;
    });

    _stepTimer = Timer(Duration(milliseconds: entry.value), () {
      _currentIndex++;
      _runNextStep();
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            // Matte e-paper device frame mockup
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE8E6E0), // Warm matte e-paper bezel
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
                    child: Container(
                      color: const Color(0xFFE8E6E0),
                      child: _buildEpaperFlashFrame(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getStatusLabel(_currentStep),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF232321),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        "${((_currentIndex / _sequence.length) * 100).toInt()}%",
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF6B6A66),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusLabel(_EpaperFlashStep step) {
    switch (step) {
      case _EpaperFlashStep.initialNegative:
        return "PULSE 1: POLARITY INVERSION";
      case _EpaperFlashStep.graphiteBlackout:
        return "PULSE 2: ERASING PARTICLES";
      case _EpaperFlashStep.paperWhiteout:
        return "PULSE 3: SUBSTRATE RESET";
      case _EpaperFlashStep.invertJolt:
        return "PULSE 4: PIGMENT JOLT";
      case _EpaperFlashStep.ghostMono:
        return "PULSE 5: INK SETTLING";
      case _EpaperFlashStep.finalSettled:
        return "IMAGE LOCKED";
    }
  }

  Widget _buildEpaperFlashFrame() {
    switch (_currentStep) {
      // 1. Harsh Negative Flash (pixels inverted entirely on the spot)
      case _EpaperFlashStep.initialNegative:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            -1,  0,  0, 0, 255,
             0, -1,  0, 0, 255,
             0,  0, -1, 0, 255,
             0,  0,  0, 1,   0,
          ]),
          child: Image.memory(
            widget.rawImageBytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        );

      // 2. Full screen graphite black pulse
      case _EpaperFlashStep.graphiteBlackout:
        return AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            color: const Color(0xFF21211F), // Muted graphite black
          ),
        );

      // 3. Full screen matte paper clear pulse
      case _EpaperFlashStep.paperWhiteout:
        return AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            color: const Color(0xFFE8E6E0), // Warm matte off-white
          ),
        );

      // 4. Inverted color jolt
      case _EpaperFlashStep.invertJolt:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            -1,  0,  0, 0, 255,
             0, -1,  0, 0, 255,
             0,  0, -1, 0, 255,
             0,  0,  0, 1,   0,
          ]),
          child: Image.memory(
            widget.ditheredImageBytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        );

      // 5. Monochrome ghost settling snapshot
      case _EpaperFlashStep.ghostMono:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.33, 0.33, 0.33, 0, 0,
            0.33, 0.33, 0.33, 0, 0,
            0.33, 0.33, 0.33, 0, 0,
            0,    0,    0,    1, 0,
          ]),
          child: Image.memory(
            widget.ditheredImageBytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        );

      // 6. Final settled e-ink image
      case _EpaperFlashStep.finalSettled:
        return Image.memory(
          widget.ditheredImageBytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        );
    }
  }
}
