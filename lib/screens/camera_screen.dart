import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reframe_processor.dart';
import '../widgets/epaper_refresh_view.dart';
import 'photo_result_screen.dart';

enum DevicePhysicalOrientation {
  portraitUp,
  landscapeLeft,
  portraitDown,
  landscapeRight,
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isProcessing = false;
  bool _isRefreshingEpaper = false;
  FlashMode _flashMode = FlashMode.off;

  // Settings
  PalettePreset _palettePreset = PalettePreset.spectra6;
  int _densityResolution = 700;
  double _saturation = 0.6;
  double _colorBoost = 1.3;
  double _contrast = 1.15;
  bool _useFloydSteinberg = true;
  double _refreshDurationSeconds = 3.5; // Tunable e-paper refresh speed (1.5s - 6.0s)

  Uint8List? _rawCapturedBytes;
  Uint8List? _ditheredBytes;
  String _currentPhotoId = "";

  final ImagePicker _picker = ImagePicker();

  // Accelerometer orientation tracking
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  DevicePhysicalOrientation _deviceOrientation = DevicePhysicalOrientation.portraitUp;
  double _uiRotationAngle = 0.0; // In radians for smooth icon rotation

  bool get _isCurrentFrontCamera {
    if (widget.cameras.isEmpty || _selectedCameraIndex >= widget.cameras.length) {
      return false;
    }
    return widget.cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _initAccelerometer();
    if (widget.cameras.isNotEmpty) {
      _initCamera(_selectedCameraIndex);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _densityResolution = prefs.getInt('pref_densityResolution') ?? 700;
        _contrast = prefs.getDouble('pref_contrast') ?? 1.15;
        _colorBoost = prefs.getDouble('pref_colorBoost') ?? 1.3;
        _useFloydSteinberg = prefs.getBool('pref_useFloydSteinberg') ?? true;
        _refreshDurationSeconds = prefs.getDouble('pref_refreshDuration') ?? 3.5;

        final presetIndex = prefs.getInt('pref_palettePreset');
        if (presetIndex != null && presetIndex >= 0 && presetIndex < PalettePreset.values.length) {
          _palettePreset = PalettePreset.values[presetIndex];
        }
      });
    } catch (e) {
      debugPrint("Error loading preferences: $e");
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pref_densityResolution', _densityResolution);
      await prefs.setDouble('pref_contrast', _contrast);
      await prefs.setDouble('pref_colorBoost', _colorBoost);
      await prefs.setBool('pref_useFloydSteinberg', _useFloydSteinberg);
      await prefs.setDouble('pref_refreshDuration', _refreshDurationSeconds);
      await prefs.setInt('pref_palettePreset', _palettePreset.index);
    } catch (e) {
      debugPrint("Error saving preferences: $e");
    }
  }

  void _initAccelerometer() {
    _accelerometerSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      double x = event.x;
      double y = event.y;

      DevicePhysicalOrientation newOrientation = _deviceOrientation;
      double targetAngle = _uiRotationAngle;

      if (x.abs() > 4.5 || y.abs() > 4.5) {
        if (x.abs() > y.abs()) {
          if (x > 0) {
            // Tilted left -> rotate icons clockwise (+90 deg)
            newOrientation = DevicePhysicalOrientation.landscapeLeft;
            targetAngle = math.pi / 2;
          } else {
            // Tilted right -> rotate icons counter-clockwise (-90 deg)
            newOrientation = DevicePhysicalOrientation.landscapeRight;
            targetAngle = -math.pi / 2;
          }
        } else {
          if (y > 0) {
            // Normal upright portrait
            newOrientation = DevicePhysicalOrientation.portraitUp;
            targetAngle = 0.0;
          } else {
            // Upside down
            newOrientation = DevicePhysicalOrientation.portraitDown;
            targetAngle = math.pi;
          }
        }

        if (newOrientation != _deviceOrientation || targetAngle != _uiRotationAngle) {
          if (mounted) {
            setState(() {
              _deviceOrientation = newOrientation;
              _uiRotationAngle = targetAngle;
            });
          }
        }
      }
    });
  }

  Future<void> _initCamera(int cameraIndex) async {
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    if (widget.cameras.isEmpty) return;
    final camera = widget.cameras[cameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (mounted) {
        setState(() {
          _controller = controller;
          _selectedCameraIndex = cameraIndex;
        });
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _controller = null;
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_selectedCameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelerometerSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _switchCamera() {
    if (widget.cameras.length < 2) return;
    int nextIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    _initCamera(nextIndex);
  }

  void _cycleFlash() {
    if (_controller == null) return;
    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      case FlashMode.always:
      default:
        nextMode = FlashMode.off;
        break;
    }
    _controller!.setFlashMode(nextMode);
    setState(() {
      _flashMode = nextMode;
    });
  }

  static Uint8List _runDitheringIsolate(Map<String, dynamic> params) {
    return ReframeProcessor.processImage(
      params['bytes'] as Uint8List,
      preset: params['preset'] as PalettePreset,
      saturation: params['saturation'] as double,
      brightnessFactor: 1.0,
      colorFactor: params['color'] as double,
      contrastFactor: params['contrast'] as double,
      useFloydSteinberg: params['floyd'] as bool,
      densityResolution: params['density'] as int,
      isFrontCamera: params['isFrontCamera'] as bool,
      rotationDegrees: params['rotation'] as int,
    );
  }

  Future<void> _processImageBytes(Uint8List rawBytes, {bool isFront = false, int rotation = 0}) async {
    final photoSuffix = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _isProcessing = true;
      _rawCapturedBytes = rawBytes;
      _currentPhotoId = photoSuffix.length > 6 ? photoSuffix.substring(photoSuffix.length - 6) : photoSuffix;
    });

    try {
      final ditheredResult = await compute(_runDitheringIsolate, {
        'bytes': rawBytes,
        'preset': _palettePreset,
        'saturation': _saturation,
        'color': _colorBoost,
        'contrast': _contrast,
        'floyd': _useFloydSteinberg,
        'density': _densityResolution,
        'isFrontCamera': isFront,
        'rotation': rotation,
      });

      if (!mounted) return;

      setState(() {
        _ditheredBytes = ditheredResult;
        _isProcessing = false;
        _isRefreshingEpaper = true;
      });
    } catch (e) {
      debugPrint("Processing error: $e");
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error processing photo: $e")),
        );
      }
    }
  }

  int _calculateCaptureRotation() {
    switch (_deviceOrientation) {
      case DevicePhysicalOrientation.portraitUp:
        return 0;
      case DevicePhysicalOrientation.landscapeLeft:
        return 270;
      case DevicePhysicalOrientation.landscapeRight:
        return 90;
      case DevicePhysicalOrientation.portraitDown:
        return 180;
    }
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) {
      return;
    }

    try {
      final bool wasFront = _isCurrentFrontCamera;
      final int rotation = _calculateCaptureRotation();

      final XFile photoFile = await _controller!.takePicture();
      final Uint8List bytes = await photoFile.readAsBytes();

      await _processImageBytes(bytes, isFront: wasFront, rotation: rotation);
    } catch (e) {
      debugPrint("Take photo error: $e");
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Camera capture error: $e")),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        await _processImageBytes(bytes, isFront: false, rotation: 0);
      }
    } catch (e) {
      debugPrint("Gallery pick error: $e");
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gallery pick error: $e")),
        );
      }
    }
  }

  void _onEpaperRefreshComplete() {
    setState(() {
      _isRefreshingEpaper = false;
    });

    if (_ditheredBytes != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PhotoResultScreen(
            imageBytes: _ditheredBytes!,
            photoId: _currentPhotoId,
          ),
        ),
      );
    }
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "reFrame Parameters",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 12),

                    // Palette Preset Selection
                    const Text(
                      "COLOR PALETTE",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildPresetChip("Spectra 6", PalettePreset.spectra6, setModalState),
                        _buildPresetChip("Retro (B/W/Red)", PalettePreset.retro3Color, setModalState),
                        _buildPresetChip("Mono (B/W)", PalettePreset.monochrome, setModalState),
                        _buildPresetChip("Cyberpunk", PalettePreset.cyberpunk, setModalState),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Refresh Animation Speed / Duration Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "REFRESH DURATION",
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          "${_refreshDurationSeconds.toStringAsFixed(1)}s",
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.yellowAccent),
                        ),
                      ],
                    ),
                    Slider(
                      value: _refreshDurationSeconds,
                      min: 1.5,
                      max: 6.0,
                      divisions: 9,
                      activeColor: Colors.yellowAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        setModalState(() => _refreshDurationSeconds = val);
                        setState(() => _refreshDurationSeconds = val);
                      },
                      onChangeEnd: (_) => _saveSettings(),
                    ),

                    // Density / Graininess Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "GRAIN / DENSITY",
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          _getDensityLabel(_densityResolution),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.yellowAccent),
                        ),
                      ],
                    ),
                    Slider(
                      value: _densityResolution.toDouble(),
                      min: 360,
                      max: 1080,
                      divisions: 4,
                      activeColor: Colors.yellowAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        setModalState(() => _densityResolution = val.toInt());
                        setState(() => _densityResolution = val.toInt());
                      },
                      onChangeEnd: (_) => _saveSettings(),
                    ),

                    // Contrast Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "CONTRAST",
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          "${(_contrast * 100).toInt()}%",
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.yellowAccent),
                        ),
                      ],
                    ),
                    Slider(
                      value: _contrast,
                      min: 0.9,
                      max: 1.6,
                      activeColor: Colors.yellowAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        setModalState(() => _contrast = val);
                        setState(() => _contrast = val);
                      },
                      onChangeEnd: (_) => _saveSettings(),
                    ),

                    // Color Saturation Slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "PIGMENT BOOST",
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          "${(_colorBoost * 100).toInt()}%",
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.yellowAccent),
                        ),
                      ],
                    ),
                    Slider(
                      value: _colorBoost,
                      min: 1.0,
                      max: 2.0,
                      activeColor: Colors.yellowAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        setModalState(() => _colorBoost = val);
                        setState(() => _colorBoost = val);
                      },
                      onChangeEnd: (_) => _saveSettings(),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getDensityLabel(int val) {
    if (val <= 360) return "360p (Coarse)";
    if (val <= 540) return "540p (Medium)";
    if (val <= 720) return "720p (Default)";
    if (val <= 900) return "900p (Fine)";
    return "1080p (Ultra)";
  }

  Widget _buildPresetChip(String label, PalettePreset preset, StateSetter setModalState) {
    final bool isSelected = _palettePreset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.white,
      backgroundColor: Colors.black45,
      labelStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: isSelected ? Colors.black : Colors.white,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (val) {
        if (val) {
          setModalState(() => _palettePreset = preset);
          setState(() => _palettePreset = preset);
          _saveSettings();
        }
      },
    );
  }

  Widget _buildRotatedButton({required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _uiRotationAngle),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, angle, childWidget) {
        return Transform.rotate(
          angle: angle,
          child: childWidget,
        );
      },
      child: child,
    );
  }

  Widget _buildViewfinder() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;
    final cameraRatio = 1.0 / _controller!.value.aspectRatio;

    return Center(
      child: AspectRatio(
        aspectRatio: cameraRatio,
        child: _isCurrentFrontCamera
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(math.pi),
                child: CameraPreview(_controller!),
              )
            : CameraPreview(_controller!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRefreshingEpaper && _rawCapturedBytes != null && _ditheredBytes != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: EpaperRefreshView(
          rawImageBytes: _rawCapturedBytes!,
          ditheredImageBytes: _ditheredBytes!,
          duration: Duration(milliseconds: (_refreshDurationSeconds * 1000).toInt()),
          onComplete: _onEpaperRefreshComplete,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            // Stable vertical Viewfinder (never jarringly jumps on orientation)
            _buildViewfinder(),

            // Top control bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Static branding (does NOT rotate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      "reFrame // ${_palettePreset.name.toUpperCase()}",
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                  // Dithering Mode Toggle + Flash Button
                  Row(
                    children: [
                      _buildRotatedButton(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _useFloydSteinberg = !_useFloydSteinberg;
                            });
                            _saveSettings();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _useFloydSteinberg
                                  ? Colors.yellowAccent.withOpacity(0.9)
                                  : Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _useFloydSteinberg ? "FLOYD" : "BAYER",
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      _buildRotatedButton(
                        child: IconButton(
                          icon: Icon(
                            _flashMode == FlashMode.off
                                ? Icons.flash_off
                                : _flashMode == FlashMode.auto
                                    ? Icons.flash_auto
                                    : Icons.flash_on,
                            color: Colors.white,
                          ),
                          onPressed: _cycleFlash,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Shutter & Bottom Controls
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Import photo from gallery
                    _buildRotatedButton(
                      child: IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
                        tooltip: "Process from Gallery",
                        onPressed: _isProcessing ? null : _pickFromGallery,
                      ),
                    ),

                    // Shutter button
                    GestureDetector(
                      onTap: _isProcessing ? null : _takePhoto,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: Colors.transparent,
                        ),
                        child: Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isProcessing ? Colors.yellowAccent : Colors.white,
                            ),
                            child: _isProcessing
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.black,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),

                    // Switch Camera
                    _buildRotatedButton(
                      child: IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                        tooltip: "Switch Camera",
                        onPressed: _isProcessing ? null : _switchCamera,
                      ),
                    ),

                    // Settings modal bottom sheet
                    _buildRotatedButton(
                      child: IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.settings_outlined, color: Colors.white),
                        tooltip: "Tune density & colors",
                        onPressed: _showSettingsModal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
