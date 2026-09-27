import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

enum PalettePreset {
  spectra6,     // Authentic reFrame Spectra 6 (6 colors: Blk, Wht, Yel, Red, Blu, Grn)
  retro3Color,  // Classic e-ink (Black, White, Red)
  monochrome,   // Pure e-ink 2-color (Black, White)
  cyberpunk,    // Neon high-contrast palette
}

class ReframeProcessor {
  // Spectra 6 base palettes
  static const List<List<int>> desaturatedPalette = [
    [0, 0, 0],          // 0: Black
    [255, 255, 255],    // 1: White
    [0, 255, 0],        // 2: Green
    [0, 0, 255],        // 3: Blue
    [255, 0, 0],        // 4: Red
    [255, 255, 0],      // 5: Yellow
  ];

  static const List<List<int>> saturatedPalette = [
    [57, 48, 57],       // 0: Muted Black
    [255, 255, 255],    // 1: White
    [40, 91, 58],       // 2: Muted Green
    [0, 128, 255],      // 3: Muted Blue
    [156, 72, 75],      // 4: Muted Red
    [208, 190, 71],     // 5: Muted Yellow
  ];

  static const List<int> colorIndices = [0, 1, 5, 4, 3, 2];

  /// Generates target palette based on chosen preset & saturation
  static List<List<int>> getPalette({
    PalettePreset preset = PalettePreset.spectra6,
    double saturation = 0.6,
  }) {
    switch (preset) {
      case PalettePreset.monochrome:
        return [
          [0, 0, 0],
          [255, 255, 255],
        ];
      case PalettePreset.retro3Color:
        return [
          [25, 25, 25],       // Black
          [250, 250, 245],   // White
          [210, 40, 40],     // Red
        ];
      case PalettePreset.cyberpunk:
        return [
          [15, 15, 25],      // Deep night
          [255, 255, 255],   // Pure white
          [255, 0, 110],     // Neon pink
          [0, 240, 255],     // Neon cyan
          [255, 225, 0],     // Neon yellow
          [120, 0, 255],     // Violet
        ];
      case PalettePreset.spectra6:
      default:
        List<List<int>> palette = [];
        for (int idx in colorIndices) {
          final sat = saturatedPalette[idx];
          final desat = desaturatedPalette[idx];
          int r = ((sat[0] * saturation) + (desat[0] * (1.0 - saturation))).round().clamp(0, 255);
          int g = ((sat[1] * saturation) + (desat[1] * (1.0 - saturation))).round().clamp(0, 255);
          int b = ((sat[2] * saturation) + (desat[2] * (1.0 - saturation))).round().clamp(0, 255);
          palette.add([r, g, b]);
        }
        return palette;
    }
  }

  static List<double> rgbToLab(int r, int g, int b) {
    double cr = r / 255.0;
    double cg = g / 255.0;
    double cb = b / 255.0;

    double lr = cr > 0.04045 ? math.pow((cr + 0.055) / 1.055, 2.4).toDouble() : (cr / 12.92);
    double lg = cg > 0.04045 ? math.pow((cg + 0.055) / 1.055, 2.4).toDouble() : (cg / 12.92);
    double lb = cb > 0.04045 ? math.pow((cb + 0.055) / 1.055, 2.4).toDouble() : (cb / 12.92);

    double x = (lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375) / 0.95047;
    double y = (lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750) / 1.00000;
    double z = (lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041) / 1.08883;

    double fx = x > 0.008856 ? math.pow(x, 1.0 / 3.0).toDouble() : (903.3 * x + 16.0) / 116.0;
    double fy = y > 0.008856 ? math.pow(y, 1.0 / 3.0).toDouble() : (903.3 * y + 16.0) / 116.0;
    double fz = z > 0.008856 ? math.pow(z, 1.0 / 3.0).toDouble() : (903.3 * z + 16.0) / 116.0;

    return [
      116.0 * fy - 16.0,
      500.0 * (fx - fy),
      200.0 * (fy - fz)
    ];
  }

  static const List<List<double>> bayer4x4 = [
    [ 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0],
    [12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0],
    [ 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0],
    [15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0]
  ];

  /// Full dithering pipeline with resolution/density control and settings
  static Uint8List processImage(
    Uint8List inputBytes, {
    PalettePreset preset = PalettePreset.spectra6,
    double saturation = 0.6,
    double brightnessFactor = 1.0,
    double colorFactor = 1.3,
    double contrastFactor = 1.1,
    bool useFloydSteinberg = true,
    int densityResolution = 600, // Resolution density: 400 (Chunky/Grainy), 600 (Balanced), 800 (Fine)
  }) {
    img.Image? decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw Exception("Unable to decode image");
    }

    decoded = img.bakeOrientation(decoded);

    // Apply density scaling
    img.Image resized;
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(decoded, width: densityResolution);
    } else {
      resized = img.copyResize(decoded, height: densityResolution);
    }

    // Color and contrast adjustments
    if (brightnessFactor != 1.0) {
      double bOffset = (brightnessFactor - 1.0) * 80;
      resized = img.adjustColor(resized, brightness: bOffset);
    }

    if (colorFactor != 1.0) {
      resized = img.adjustColor(resized, saturation: colorFactor);
    }

    if (contrastFactor != 1.0) {
      resized = img.adjustColor(resized, contrast: contrastFactor);
    }

    final palette = getPalette(preset: preset, saturation: saturation);
    final paletteLab = palette.map((p) => rgbToLab(p[0], p[1], p[2])).toList();

    // Fast 32-level LUT in CIELAB space
    final Uint8List lut = Uint8List(32 * 32 * 32);
    for (int r5 = 0; r5 < 32; r5++) {
      int r = (r5 * 255) ~/ 31;
      for (int g5 = 0; g5 < 32; g5++) {
        int g = (g5 * 255) ~/ 31;
        for (int b5 = 0; b5 < 32; b5++) {
          int b = (b5 * 255) ~/ 31;
          final lab = rgbToLab(r, g, b);

          double minDist = double.infinity;
          int bestIdx = 0;
          for (int i = 0; i < paletteLab.length; i++) {
            double dl = lab[0] - paletteLab[i][0];
            double da = lab[1] - paletteLab[i][1];
            double db = lab[2] - paletteLab[i][2];
            double dist = dl * dl + da * da + db * db;
            if (dist < minDist) {
              minDist = dist;
              bestIdx = i;
            }
          }
          lut[(r5 << 10) | (g5 << 5) | b5] = bestIdx;
        }
      }
    }

    int lookupNearestColor(int r, int g, int b) {
      int r5 = ((r.clamp(0, 255) * 31) ~/ 255);
      int g5 = ((g.clamp(0, 255) * 31) ~/ 255);
      int b5 = ((b.clamp(0, 255) * 31) ~/ 255);
      return lut[(r5 << 10) | (g5 << 5) | b5];
    }

    final int width = resized.width;
    final int height = resized.height;
    final img.Image result = img.Image(width: width, height: height);

    if (useFloydSteinberg) {
      final Float64List bufR = Float64List(width * height);
      final Float64List bufG = Float64List(width * height);
      final Float64List bufB = Float64List(width * height);

      int idx = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final p = resized.getPixel(x, y);
          bufR[idx] = p.r.toDouble();
          bufG[idx] = p.g.toDouble();
          bufB[idx] = p.b.toDouble();
          idx++;
        }
      }

      const double errorDamping = 0.90;

      for (int y = 0; y < height; y++) {
        final int yOffset = y * width;
        final int nextYOffset = (y + 1) * width;
        final bool hasNextY = (y + 1 < height);

        for (int x = 0; x < width; x++) {
          final int currIdx = yOffset + x;

          int r = bufR[currIdx].round().clamp(0, 255);
          int g = bufG[currIdx].round().clamp(0, 255);
          int b = bufB[currIdx].round().clamp(0, 255);

          int palIdx = lookupNearestColor(r, g, b);
          final nearestColor = palette[palIdx];

          result.setPixelRgb(x, y, nearestColor[0], nearestColor[1], nearestColor[2]);

          double errR = (r - nearestColor[0]) * errorDamping;
          double errG = (g - nearestColor[1]) * errorDamping;
          double errB = (b - nearestColor[2]) * errorDamping;

          if (x + 1 < width) {
            final int rightIdx = currIdx + 1;
            bufR[rightIdx] += errR * (7.0 / 16.0);
            bufG[rightIdx] += errG * (7.0 / 16.0);
            bufB[rightIdx] += errB * (7.0 / 16.0);
          }

          if (hasNextY) {
            if (x > 0) {
              final int botLeft = nextYOffset + (x - 1);
              bufR[botLeft] += errR * (3.0 / 16.0);
              bufG[botLeft] += errG * (3.0 / 16.0);
              bufB[botLeft] += errB * (3.0 / 16.0);
            }

            final int bot = nextYOffset + x;
            bufR[bot] += errR * (5.0 / 16.0);
            bufG[bot] += errG * (5.0 / 16.0);
            bufB[bot] += errB * (5.0 / 16.0);

            if (x + 1 < width) {
              final int botRight = nextYOffset + (x + 1);
              bufR[botRight] += errR * (1.0 / 16.0);
              bufG[botRight] += errG * (1.0 / 16.0);
              bufB[botRight] += errB * (1.0 / 16.0);
            }
          }
        }
      }
    } else {
      const double threshold = 52.0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final p = resized.getPixel(x, y);
          double noise = (bayer4x4[y % 4][x % 4] - 0.5) * threshold;

          int r = (p.r + noise).round().clamp(0, 255);
          int g = (p.g + noise).round().clamp(0, 255);
          int b = (p.b + noise).round().clamp(0, 255);

          int palIdx = lookupNearestColor(r, g, b);
          final c = palette[palIdx];
          result.setPixelRgb(x, y, c[0], c[1], c[2]);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(result));
  }
}
