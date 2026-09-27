import 'dart:async';
import 'dart:io';
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

  // Dithering settings mimicking reFrame defaults
  double _saturation = 0.6;
  bool _useFloydSteinberg = true; // true: Floyd-Steinberg, false: Ordered Bayer

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

  // Background isolate computation for dithering so UI stays responsive
  static Uint8List _runDitheringIsolate(Map<String, dynamic> params) {
    return ReframeProcessor.processImage(
      params['bytes'] as Uint8List,
      saturation: params['saturation'] as double,
      brightnessFactor: params['brightness'] as double,
      colorFactor: params['color'] as double,
      useFloydSteinberg: params['floyd'] as bool,
      targetWidth: 600,
    );
  }

  Future<void> _processImageBytes(Uint8List rawBytes) async {
    setState(() {
      _isProcessing = true;
      _rawCapturedBytes = rawBytes;
      _currentPhotoId = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    });

    try {
      // Execute dithering inside isolate (reFrame spectra-6 pipeline)
      final ditheredResult = await compute(_runDitheringIsolate, {
        'bytes': rawBytes,
        'saturation': _saturation,
        'brightness': 1.1,
        'color': 1.4,
        'floyd': _useFloydSteinberg,
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
            // Camera viewfinder
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 3.0 / 4.0, // Classic aspect ratio
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
                  // App branding
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      "reFrame // Spectra-6",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      // Mode switch: Floyd-Steinberg vs Ordered Bayer
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _useFloydSteinberg = !_useFloydSteinberg;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _useFloydSteinberg
                                    ? "Algorithm: Floyd-Steinberg (Error Diffusion)"
                                    : "Algorithm: Ordered Dithering (Bayer 4x4)",
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
                      const SizedBox(width: 8),

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
                        "DITHERING SPECTRA-6 PALETTE...",
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
                        color: const Color(0xFFF0EFEB), // reFrame matte white button
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

                  // Empty container for symmetry
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
