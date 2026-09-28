# AGENTS.md — reFrame Camera Android

Flutter Android camera app that replicates the Waveshare Spectra 6 ePaper dithering effect.
Repo: https://github.com/purkalolka/reframe-camera-android

---

## How to get an APK (no local build needed)

Push to `main` → GitHub Actions builds the APK automatically.
Download from: **Actions tab → Build Android APK → Artifacts → `reframe-camera-release-apk`**.

To trigger manually: **Actions → "Build Android APK" → Run workflow**.

Local build (requires Flutter 3.24.x + Java 17):
```
flutter pub get
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

---

## Architecture

```
lib/
  main.dart                    # App entry, locks orientation to portraitUp
  screens/
    camera_screen.dart         # Main UI, accelerometer logic, capture flow
    photo_result_screen.dart   # Shows result; save/share buttons
  services/
    reframe_processor.dart     # Dithering engine (Floyd-Steinberg + Bayer 4x4, CIELAB LUT)
  widgets/
    epaper_refresh_view.dart   # ePaper flash animation shown between capture and result
android/
  app/build.gradle             # compileSdkVersion 35, minSdk 21, namespace com.reframe.camera
  build.gradle                 # Forces compileSdk 35 on all subprojects (needed by deps)
.github/workflows/build-apk.yml
```

---

## Critical constraints — do not break these

| Constraint | Detail |
|---|---|
| **compileSdkVersion = 35** | Required by `image_gallery_saver_plus`. Lowering breaks the build. |
| **`image_gallery_saver_plus`** | Used instead of `gal` — `gal` has Gradle incompatibility with this project. |
| **UI locked to `portraitUp`** | Set in `main.dart` via `SystemChrome.setPreferredOrientations`. Do not change. |
| **No system auto-rotate** | Icons rotate via accelerometer (`sensors_plus`), not the OS orientation. The screen never rotates. |
| **`reFrame // SPECTRA6` label must NOT rotate** | It is static; only icon buttons rotate. Do not pass it through `_buildRotatedButton`. |
| **Settings only via gear icon** | No duplicate settings button in the top bar — only the bottom gear icon opens the settings modal. |
| **Front camera: mirror in both places** | Preview uses `Transform(rotationY: pi)`. Saved image uses `img.flipHorizontal` in `processImage()`. |
| **Adaptive icon only in `mipmap-anydpi-v26/`** | Other `mipmap-*` folders use PNG. Do not add `ic_launcher.xml` to them. |
| **Dithering in isolate** | `ReframeProcessor.processImage()` is called via `compute()` — keep it a pure top-level/static function. |

---

## Orientation baking in saved images

`_calculateCaptureRotation()` in `camera_screen.dart` maps `DevicePhysicalOrientation` to degrees passed to `processImage()`:
- `portraitUp` → 0°
- `landscapeLeft` → 270°
- `landscapeRight` → 90°
- `portraitDown` → 180°

Accelerometer: `x > 0` = phone tilted left = `landscapeLeft`; `x < 0` = `landscapeRight`.

`processImage()` applies `img.bakeOrientation` → `img.copyRotate(rotationDegrees)` → optional `img.flipHorizontal` (front cam).

---

## Dithering engine (`reframe_processor.dart`)

- **Floyd-Steinberg** with error damping factor `0.90` (prevents white blowout).
- **Bayer 4×4** ordered dither using CIELAB ΔE² for palette matching.
- CIELAB 32-level LUT is precomputed per-frame.
- Palette presets: `spectra6` (default), `retro3Color`, `monochrome`, `cyberpunk`.
- Palette selector + Floyd/Bayer toggle chip are exposed in the UI settings modal.

---

## ePaper refresh animation (`epaper_refresh_view.dart`)

Discrete voltage-pulse flash sequencer — no directional scanlines or wave sweeps.
Entire screen flashes through states in sequence (each ~180–240 ms):
1. Negative/inverted raw capture
2. Graphite blackout (`#21211F`)
3. Off-white paper clear (`#E8E6E0`)
4. Inverted dithered image
5. Monochrome (grayscale) dithered image
6. Final Spectra-6 dithered image (settled)

`onComplete` callback fires after the last step — do not add `AnimationController` back here.

---

## Gradle / Android gotchas

- `android/build.gradle` uses `afterEvaluate` to force `compileSdkVersion 35` on all subprojects — this is intentional, do not remove it.
- AGP version: `8.1.0` (in `settings.gradle`). Kotlin: `1.9.0`.
- Release builds use `signingConfig signingConfigs.debug` — debug-signed for sideloading; no keystore needed for CI.
- `minifyEnabled false` / `shrinkResources false` — intentional for camera plugin compatibility.
