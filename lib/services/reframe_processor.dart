import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Exact implementation of the reFrame camera dithering algorithm
/// matches Python reframe.py and PIL Floyd-Steinberg / Ordered Dithering.
class ReframeProcessor {
  // Desaturated Palette (Pure primaries):
  // 0: Black, 1: White, 2: Green, 3: Blue, 4: Red, 5: Yellow
  static const List<List<int>> desaturatedPalette = [
    [0, 0, 0],          // 0: Black
    [255, 255, 255],    // 1: White
    [0, 255, 0],        // 2: Green
    [0, 0, 255],        // 3: Blue
    [255, 0, 0],        // 4: Red
    [255, 255, 0],      // 5: Yellow
  ];

  // Saturated Palette (E-paper pigments):
  static const List<List<int>> saturatedPalette = [
    [57, 48, 57],       // 0: Muted Black
    [255, 255, 255],    // 1: White
    [40, 91, 58],       // 2: Muted Green
    [0, 128, 255],      // 3: Muted Blue
    [156, 72, 75],      // 4: Muted Red
    [208, 190, 71],     // 5: Muted Yellow
  ];

  // Original reFrame color indices: [0, 1, 5, 4, 3, 2] -> Black, White, Yellow, Red, Blue, Green
  static const List<int> colorIndices = [0, 1, 5, 4, 3, 2];

  /// Blends the saturated and desaturated palettes exactly like reframe.py:
  /// rs, gs, bs = [c * saturation for c in SATURATED_PALETTE[i]]
  /// rd, gd, bd = [c * (1.0 - saturation) for c in DESATURATED_PALETTE[i]]
  /// palette_colors.append([int(rs + rd), int(gs + gd), int(bs + bd)])
  static List<List<int>> getBlendedPalette({double saturation = 0.6}) {
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

  /// Fast weighted Euclidean distance in RGB (redmean metric)
  /// Matches human perceptual sensitivity much better than naive RGB distance
  /// and avoids float conversion overhead during error diffusion.
  static int findNearestColorIndex(int r, int g, int b, List<List<int>> palette) {
    int bestIdx = 0;
    int minDistance = 0x7FFFFFFF;

    for (int i = 0; i < palette.length; i++) {
      final p = palette[i];
      int pr = p[0];
      int pg = p[1];
      int pb = p[2];

      int rmean = (r + pr) >> 1;
      int dr = r - pr;
      int dg = g - pg;
      int db = b - pb;

      // Color distance with perceptual weights
      int dist = (((512 + rmean) * dr * dr) >> 8) +
                 (4 * dg * dg) +
                 (((767 - rmean) * db * db) >> 8);

      if (dist < minDistance) {
        minDistance = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// 4x4 Bayer matrix for ordered dithering
  static const List<List<double>> bayer4x4 = [
    [ 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0],
    [12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0],
    [ 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0],
    [15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0]
  ];

  /// Process photo with Spectra-6 dithering
  static Uint8List processImage(
    Uint8List inputBytes, {
    double saturation = 0.6,
    double brightnessFactor = 1.1,
    double colorFactor = 1.4,
    bool useFloydSteinberg = true,
    int targetWidth = 600,
  }) {
    img.Image? decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw Exception("Unable to decode image");
    }

    // Correct orientation from EXIF
    decoded = img.bakeOrientation(decoded);

    // Resize image maintaining aspect ratio
    img.Image resized;
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(decoded, width: targetWidth);
    } else {
      resized = img.copyResize(decoded, height: targetWidth);
    }

    // Color enhancements like PIL ImageEnhance.Brightness & Color
    if (brightnessFactor != 1.0) {
      double bOffset = (brightnessFactor - 1.0) * 80;
      resized = img.adjustColor(resized, brightness: bOffset);
    }

    if (colorFactor != 1.0) {
      resized = img.adjustColor(resized, saturation: colorFactor);
    }

    final palette = getBlendedPalette(saturation: saturation);
    final int width = resized.width;
    final int height = resized.height;

    final img.Image result = img.Image(width: width, height: height);

    if (useFloydSteinberg) {
      // 1D flat buffers for cache efficiency
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

      // Classic Floyd-Steinberg error diffusion
      for (int y = 0; y < height; y++) {
        final int yOffset = y * width;
        final int nextYOffset = (y + 1) * width;
        final bool hasNextY = (y + 1 < height);

        for (int x = 0; x < width; x++) {
          final int currIdx = yOffset + x;

          // Clamped current pixel value with accumulated error
          int r = bufR[currIdx].round().clamp(0, 255);
          int g = bufG[currIdx].round().clamp(0, 255);
          int b = bufB[currIdx].round().clamp(0, 255);

          // Find closest color in Spectra-6 palette
          int palIdx = findNearestColorIndex(r, g, b, palette);
          final nearestColor = palette[palIdx];

          result.setPixelRgb(x, y, nearestColor[0], nearestColor[1], nearestColor[2]);

          // Compute residual error
          double errR = r - nearestColor[0].toDouble();
          double errG = g - nearestColor[1].toDouble();
          double errB = b - nearestColor[2].toDouble();

          // Floyd-Steinberg error distribution:
          // x + 1, y     : 7/16
          // x - 1, y + 1 : 3/16
          // x,     y + 1 : 5/16
          // x + 1, y + 1 : 1/16
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
      // Ordered Bayer Dithering
      const double threshold = 72.0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final p = resized.getPixel(x, y);
          double noise = (bayer4x4[y % 4][x % 4] - 0.5) * threshold;

          int r = (p.r + noise).round().clamp(0, 255);
          int g = (p.g + noise).round().clamp(0, 255);
          int b = (p.b + noise).round().clamp(0, 255);

          int palIdx = findNearestColorIndex(r, g, b, palette);
          final c = palette[palIdx];
          result.setPixelRgb(x, y, c[0], c[1], c[2]);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(result));
  }
}
