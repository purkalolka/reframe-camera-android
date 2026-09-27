import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Accurate reproduction of the reFrame camera image processing pipeline
/// as implemented in kaloyaan/reframe (Spectra 6 ePaper palette and dithering).
class ReframeProcessor {
  // Original Spectra 6 palettes from kaloyaan/reframe
  static const List<List<int>> desaturatedPalette = [
    [0, 0, 0], // Black
    [255, 255, 255], // White
    [0, 255, 0], // Green
    [0, 0, 255], // Blue
    [255, 0, 0], // Red
    [255, 255, 0], // Yellow
  ];

  static const List<List<int>> saturatedPalette = [
    [57, 48, 57], // Muted Black
    [255, 255, 255], // White
    [40, 91, 58], // Muted Green
    [0, 128, 255], // Muted Blue
    [156, 72, 75], // Muted Red
    [208, 190, 71], // Muted Yellow
  ];

  // Palette color indices used by reFrame: [0, 1, 5, 4, 0, 3, 2]
  // Colors: Black, White, Yellow, Red, Black, Blue, Green
  static const List<int> colorIndices = [0, 1, 5, 4, 3, 2];

  /// Blends the saturated and desaturated palettes based on the [saturation] factor (default 0.6)
  static List<List<int>> getBlendedPalette({double saturation = 0.6}) {
    List<List<int>> blended = [];
    for (int idx in colorIndices) {
      final sat = saturatedPalette[idx];
      final desat = desaturatedPalette[idx];
      int r = ((sat[0] * saturation) + (desat[0] * (1.0 - saturation))).round().clamp(0, 255);
      int g = ((sat[1] * saturation) + (desat[1] * (1.0 - saturation))).round().clamp(0, 255);
      int b = ((sat[2] * saturation) + (desat[2] * (1.0 - saturation))).round().clamp(0, 255);
      blended.add([r, g, b]);
    }
    return blended;
  }

  /// Converts RGB (0-255) to CIELAB coordinates for perceptual color distance
  static List<double> rgbToLab(int r, int g, int b) {
    // RGB to Linear
    double cr = r / 255.0;
    double cg = g / 255.0;
    double cb = b / 255.0;

    double lr = cr > 0.04045 ? math.pow((cr + 0.055) / 1.055, 2.4).toDouble() : (cr / 12.92);
    double lg = cg > 0.04045 ? math.pow((cg + 0.055) / 1.055, 2.4).toDouble() : (cg / 12.92);
    double lb = cb > 0.04045 ? math.pow((cb + 0.055) / 1.055, 2.4).toDouble() : (cb / 12.92);

    // Matrix to XYZ (Observer. = 2°, Illuminant = D65)
    double x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375;
    double y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750;
    double z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041;

    x /= 0.95047;
    y /= 1.00000;
    z /= 1.08883;

    double fx = x > 0.008856 ? math.pow(x, 1.0 / 3.0).toDouble() : (903.3 * x + 16.0) / 116.0;
    double fy = y > 0.008856 ? math.pow(y, 1.0 / 3.0).toDouble() : (903.3 * y + 16.0) / 116.0;
    double fz = z > 0.008856 ? math.pow(z, 1.0 / 3.0).toDouble() : (903.3 * z + 16.0) / 116.0;

    double lVal = 116.0 * fy - 16.0;
    double aVal = 500.0 * (fx - fy);
    double bVal = 200.0 * (fy - fz);

    return [lVal, aVal, bVal];
  }

  /// Calculates perceptual color difference (Delta E squared in CIELAB)
  static double colorDistanceSquared(List<double> lab1, List<double> lab2) {
    double dl = lab1[0] - lab2[0];
    double da = lab1[1] - lab2[1];
    double db = lab1[2] - lab2[2];
    return dl * dl + da * da + db * db;
  }

  /// Finds index of closest color in the palette using CIELAB distance
  static int findNearestPaletteColor(
    int r,
    int g,
    int b,
    List<List<int>> paletteRgb,
    List<List<double>> paletteLab,
  ) {
    final lab = rgbToLab(r, g, b);
    double minDistance = double.infinity;
    int bestIdx = 0;

    for (int i = 0; i < paletteLab.length; i++) {
      double dist = colorDistanceSquared(lab, paletteLab[i]);
      if (dist < minDistance) {
        minDistance = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Fast Bayer matrix for ordered dithering
  static final List<List<double>> bayerMatrix4x4 = [
    [0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0],
    [12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0],
    [3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0],
    [15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0],
  ];

  /// Full reFrame image processing pipeline:
  /// 1. Resize maintaining aspect ratio (target reFrame display size 600x400 or max 800)
  /// 2. Brightness & Color/Saturation enhancement
  /// 3. Floyd-Steinberg or Ordered Dithering with Spectra-6 blended palette
  static Uint8List processImage(
    Uint8List inputBytes, {
    double saturation = 0.6,
    double brightnessFactor = 1.1,
    double colorFactor = 1.4,
    bool useFloydSteinberg = true,
    int targetWidth = 600,
    int targetHeight = 400,
  }) {
    img.Image? original = img.decodeImage(inputBytes);
    if (original == null) {
      throw Exception("Unable to decode image");
    }

    // Fix orientation if needed
    original = img.bakeOrientation(original);

    // Target reFrame dimension: width ~ 600 or portrait 400x600
    img.Image resized;
    if (original.width > original.height) {
      resized = img.copyResize(original, width: targetWidth);
    } else {
      resized = img.copyResize(original, height: targetWidth);
    }

    // Preprocessing: Brightness & Color enhancements
    // Adjust brightness
    if (brightnessFactor != 1.0) {
      final factor = (brightnessFactor - 1.0) * 100;
      resized = img.adjustColor(resized, brightness: factor);
    }

    // Adjust saturation
    if (colorFactor != 1.0) {
      resized = img.adjustColor(resized, saturation: colorFactor);
    }

    final palette = getBlendedPalette(saturation: saturation);
    final paletteLab = palette.map((rgb) => rgbToLab(rgb[0], rgb[1], rgb[2])).toList();

    final int width = resized.width;
    final int height = resized.height;

    img.Image result = img.Image(width: width, height: height);

    if (useFloydSteinberg) {
      // 3 channels: R, G, B with error diffusion buffers
      List<Float64List> bufferR = List.generate(height, (_) => Float64List(width));
      List<Float64List> bufferG = List.generate(height, (_) => Float64List(width));
      List<Float64List> bufferB = List.generate(height, (_) => Float64List(width));

      // Fill buffers with initial pixel values
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = resized.getPixel(x, y);
          bufferR[y][x] = pixel.r.toDouble();
          bufferG[y][x] = pixel.g.toDouble();
          bufferB[y][x] = pixel.b.toDouble();
        }
      }

      // Floyd-Steinberg error diffusion
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          int oldR = bufferR[y][x].round().clamp(0, 255);
          int oldG = bufferG[y][x].round().clamp(0, 255);
          int oldB = bufferB[y][x].round().clamp(0, 255);

          int palIdx = findNearestPaletteColor(oldR, oldG, oldB, palette, paletteLab);
          final newColor = palette[palIdx];

          result.setPixelRgb(x, y, newColor[0], newColor[1], newColor[2]);

          double errR = oldR - newColor[0].toDouble();
          double errG = oldG - newColor[1].toDouble();
          double errB = oldB - newColor[2].toDouble();

          // Distribute errors:
          // x + 1, y     : 7/16
          // x - 1, y + 1 : 3/16
          // x,     y + 1 : 5/16
          // x + 1, y + 1 : 1/16
          if (x + 1 < width) {
            bufferR[y][x + 1] += errR * (7.0 / 16.0);
            bufferG[y][x + 1] += errG * (7.0 / 16.0);
            bufferB[y][x + 1] += errB * (7.0 / 16.0);
          }
          if (y + 1 < height) {
            if (x - 1 >= 0) {
              bufferR[y + 1][x - 1] += errR * (3.0 / 16.0);
              bufferG[y + 1][x - 1] += errG * (3.0 / 16.0);
              bufferB[y + 1][x - 1] += errB * (3.0 / 16.0);
            }
            bufferR[y + 1][x] += errR * (5.0 / 16.0);
            bufferG[y + 1][x] += errG * (5.0 / 16.0);
            bufferB[y + 1][x] += errB * (5.0 / 16.0);
            if (x + 1 < width) {
              bufferR[y + 1][x + 1] += errR * (1.0 / 16.0);
              bufferG[y + 1][x + 1] += errG * (1.0 / 16.0);
              bufferB[y + 1][x + 1] += errB * (1.0 / 16.0);
            }
          }
        }
      }
    } else {
      // Ordered Bayer dithering
      const double thresholdScale = 64.0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = resized.getPixel(x, y);
          double bayer = bayerMatrix4x4[y % 4][x % 4] - 0.5;
          double noise = bayer * thresholdScale;

          int r = (pixel.r + noise).round().clamp(0, 255);
          int g = (pixel.g + noise).round().clamp(0, 255);
          int b = (pixel.b + noise).round().clamp(0, 255);

          int palIdx = findNearestPaletteColor(r, g, b, palette, paletteLab);
          final newColor = palette[palIdx];

          result.setPixelRgb(x, y, newColor[0], newColor[1], newColor[2]);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(result));
  }
}
