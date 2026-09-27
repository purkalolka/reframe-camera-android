import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '../services/reframe_processor.dart';
import '../widgets/epaper_refresh_view.dart';
import 'photo_result_screen.dart';

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

  // Camera Settings
  PalettePreset _palettePreset = PalettePreset.spectra6;
  int _densityResolution = 700; // 400: Lo-Fi/Grainy, 700: Default, 1000: Ultra-Dense
  double _saturation = 0.6;
  double _colorBoost = 1.3;
  double _contrast = 1.15;
  bool _useFloydSteinberg = true;

  Uint8List? _rawCapturedBytes;
  Uint8List? _ditheredBytes;
  String _currentPhotoId = "";

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameras.isNotEmpty) {
      _initCamera(_selectedCameraIndex);
    }
  }

  Future<void> _initCamera(int cameraIndex) async {
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
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_selectedCameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    );
  }

  Future<void> _processImageBytes(Uint8List rawBytes) async {
    setState(() {
      _isProcessing = true;
      _rawCapturedBytes = rawBytes;
      _currentPhotoId = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
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
          SnackBar(content: Text("Processing failed: $e")),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) {
      return;
    }

    try {
      final XFile photoFile = await _controller!.takePicture();
      final Uint8List bytes = await photoFile.readAsBytes();
      await _processImageBytes(bytes);
    } catch (e) {
      debugPrint("Take photo error: $e");
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        await _processImageBytes(bytes);
      }
    } catch (e) {
      debugPrint("Gallery pick error: $e");
    }
  }

  void _onEpaperRefreshComplete() {
    setState(() {
      _isRefreshingEpaper = false;
    });

    if (_ditheredBytes != null) {
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
    if (val <= 450) return "Lo-Fi Chunky (${val}p)";
    if (val <= 650) return "Medium Grain (${val}p)";
    if (val <= 850) return "Dense / Sharp (${val}p)";
    return "Ultra-Fine (${val}p)";
  }

  Widget _buildPresetChip(String title, PalettePreset preset, StateSetter setModalState) {
    final isSelected = _palettePreset == preset;
    return ChoiceChip(
      label: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.white70,
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: Colors.yellowAccent,
      backgroundColor: Colors.white10,
      onSelected: (selected) {
        if (selected) {
          setModalState(() => _palettePreset = preset);
          setState(() => _palettePreset = preset);
        }
      },
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
          onComplete: _onEpaperRefreshComplete,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            // Viewfinder
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 3.0 / 4.0,
                    child: CameraPreview(_controller!),
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),

            // Top control bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // App branding & current preset
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
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      // Mode switch: Floyd-Steinberg vs Bayer
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _useFloydSteinberg = !_useFloydSteinberg;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _useFloydSteinberg
                                    ? "Algorithm: Floyd-Steinberg"
                                    : "Algorithm: Bayer 4x4",
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            _useFloydSteinberg ? "FLOYD" : "BAYER",
                            style: const TextStyle(
                              color: Colors.yellowAccent,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Settings button
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, color: Colors.white),
                        tooltip: "Parameters & Palettes",
                        onPressed: _showSettingsModal,
                      ),

                      // Flash button
                      IconButton(
                        icon: Icon(
                          _flashMode == FlashMode.off
                              ? Icons.flash_off
                              : (_flashMode == FlashMode.auto ? Icons.flash_auto : Icons.flash_on),
                          color: Colors.white,
                        ),
                        onPressed: _cycleFlash,
                      ),

                      // Flip camera button
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                        onPressed: _switchCamera,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Processing overlay indicator
            if (_isProcessing)
              Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        "DITHERING EPAPER PARTICLES...",
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          letterSpacing: 1.5,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom control bar (reFrame physical shutter button style)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Pick from phone gallery
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
                    tooltip: "Pick from gallery",
                    onPressed: _pickFromGallery,
                  ),

                  // Large tactile shutter button
                  GestureDetector(
                    onTap: _takePhoto,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF0EFEB),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.8),
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFE5E5DF),
                            border: Border.all(
                              color: const Color(0xFF222222),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Parameters shortcut button
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.settings_outlined, color: Colors.white),
                    tooltip: "Tune density & colors",
                    onPressed: _showSettingsModal,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
