import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class NewLiveScreen extends StatefulWidget {
  const NewLiveScreen({super.key});

  @override
  State<NewLiveScreen> createState() => _NewLiveScreenState();
}

class _NewLiveScreenState extends State<NewLiveScreen> {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // Steps: 0=Barcode, 1=Package Verification, 2=Motion Tracking, 3=Locker Detection
  int _currentStep = 0;
  String _instruction = 'Scan the barcode on the package';

  // Reference data
  String? _waybillId;
  List<double>? _referenceEmbedding;

  // Tracking
  Rect? _trackedBox;
  int _missCount = 0;
  static const int maxMisses = 5;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadReferenceData();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    _cameraController = CameraController(_cameras![0], ResolutionPreset.high);
    await _cameraController!.initialize();
    setState(() => _isCameraInitialized = true);
    _startBarcodeDetection();
  }

  Future<void> _loadReferenceData() async {
    final transactionManager = Provider.of<TransactionManager>(
      context,
      listen: false,
    );
    _waybillId = transactionManager.waybillId;
    _referenceEmbedding = transactionManager.embedding;
  }

  void _startBarcodeDetection() {
    final barcodeScanner = BarcodeScanner();
    bool isProcessing = false;
    int frameCount = 0;

    _cameraController!.startImageStream((image) async {
      if (_currentStep != 0 || isProcessing) return;
      frameCount++;
      if (frameCount % 10 != 0) return; // Process every 10th frame

      isProcessing = true;
      print('📷 [BARCODE] Processing frame $frameCount...');

      try {
        final inputImage = TFLiteProcessor.convertCameraImageToInputImage(
          image,
          _cameras![0],
          0,
        );
        final barcodes = await barcodeScanner.processImage(inputImage);

        if (barcodes.isNotEmpty) {
          print('📊 [BARCODE] Found ${barcodes.length} barcode(s)');
        }

        for (final barcode in barcodes) {
          if (barcode.rawValue == _waybillId) {
            print('✅ [BARCODE] Match! Moving to package verification.');
            _cameraController!.stopImageStream();
            setState(() {
              _currentStep = 1;
              _instruction = 'Position the package for verification';
            });
            _startPackageVerification();
            break;
          }
        }
      } catch (e) {
        print('❌ [ERROR] Barcode processing failed: $e');
      } finally {
        isProcessing = false;
      }
    });
  }

  void _startPackageVerification() {
    int checkCount = 0;
    Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_currentStep != 1) {
        timer.cancel();
        return;
      }
      checkCount++;
      print('\n📦 [VERIFY] Package verification attempt $checkCount...');

      try {
        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();
        final embedding = await TFLiteProcessor.generateEmbedding(bytes);
        final similarity = _calculateCosineSimilarity(
          embedding,
          _referenceEmbedding!,
        );

        print(
          '📊 [VERIFY] Similarity: ${(similarity * 100).toStringAsFixed(1)}% (threshold: 75%)',
        );

        if (similarity >= 0.75) {
          print('✅ [VERIFY] Package verified! Starting motion tracking.');
          setState(() {
            _currentStep = 2;
            _instruction = 'Move the package towards the locker';
          });
          _lockFocus();
          _startMotionTracking();
          timer.cancel();
        }
      } catch (e) {
        print('❌ [ERROR] Verification failed: $e');
      }
    });
  }

  void _lockFocus() {
    _cameraController!.setFocusMode(FocusMode.locked);
    _cameraController!.setExposureMode(ExposureMode.locked);
  }

  void _startMotionTracking() {
    int frameCount = 0;
    bool isProcessing = false;

    _cameraController!.startImageStream((image) async {
      if (_currentStep != 2 || isProcessing) return;
      frameCount++;
      if (frameCount % 20 != 0) return; // Process every 20th frame

      isProcessing = true;
      print('\n📷 [FRAME] Processing frame $frameCount...');

      try {
        final img = TFLiteProcessor.convertCameraImageToImage(image);
        final detections = await TFLiteProcessor.detectYoloObjects(img);

        print('📊 [DETECTIONS] Found ${detections.length} objects');

        // Get screen preview size (use MediaQuery from context)
        final screenSize = MediaQuery.of(context).size;
        final previewWidth = screenSize.width;
        final previewHeight = screenSize.height;

        print('📱 [SCREEN] Preview size: ${previewWidth}x${previewHeight}');

        final packageDetection = detections.firstWhere(
          (d) => d['class'] == 'package' && d['confidence'] > 0.5,
          orElse: () => {},
        );

        if (packageDetection.isNotEmpty) {
          // CRITICAL FIX: Scale normalized coords (0-1) to SCREEN size, not camera image size
          _trackedBox = Rect.fromLTWH(
            packageDetection['x'] * previewWidth,
            packageDetection['y'] * previewHeight,
            packageDetection['width'] * previewWidth,
            packageDetection['height'] * previewHeight,
          );
          _missCount = 0;
          print(
            '✅ [PACKAGE] Detected at ${_trackedBox!.left.toInt()},${_trackedBox!.top.toInt()} size ${_trackedBox!.width.toInt()}x${_trackedBox!.height.toInt()}',
          );
          setState(() {});
        } else {
          _missCount++;
          print(
            '⚠️ [MISS] Package not detected. Miss count: $_missCount/$maxMisses',
          );
          if (_missCount >= maxMisses) {
            _showTrackingLostDialog();
          }
        }

        // Check for locker
        final lockerDetection = detections.firstWhere(
          (d) => d['class'] == 'locker' && d['confidence'] > 0.5,
          orElse: () => {},
        );

        if (lockerDetection.isNotEmpty) {
          print('✅ [LOCKER] Detected! Moving to final step.');
          setState(() {
            _currentStep = 3;
            _instruction = 'Package detected in locker';
          });
          _cameraController!.stopImageStream();
        }
      } catch (e) {
        print('❌ [ERROR] Frame processing failed: $e');
      } finally {
        isProcessing = false;
      }
    });
  }

  void _showTrackingLostDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tracking Lost'),
        content: Text('Package tracking was lost. Please restart the process.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentStep = 0;
                _instruction = 'Scan the barcode on the package';
              });
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  double _calculateCosineSimilarity(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Live Verification')),
      body: _isCameraInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController!),
                if (_trackedBox != null)
                  Positioned(
                    left: _trackedBox!.left,
                    top: _trackedBox!.top,
                    width: _trackedBox!.width,
                    height: _trackedBox!.height,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 3),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 100,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: EdgeInsets.all(16),
                    color: Colors.black54,
                    child: Text(
                      _instruction,
                      style: TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Positioned(
                  top: 20,
                  left: 20,
                  child: Row(
                    children: List.generate(
                      4,
                      (i) => Icon(
                        i <= _currentStep
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: i <= _currentStep ? Colors.green : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
