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
    final transactionManager = Provider.of<TransactionManager>(context, listen: false);
    _waybillId = transactionManager.waybillId;
    _referenceEmbedding = transactionManager.embedding;
  }

  void _startBarcodeDetection() {
    final barcodeScanner = BarcodeScanner();
    _cameraController!.startImageStream((image) async {
      if (_currentStep != 0) return;
      final inputImage = TFLiteProcessor.convertCameraImageToInputImage(image, _cameras![0], 0);
      final barcodes = await barcodeScanner.processImage(inputImage);
      for (final barcode in barcodes) {
        if (barcode.rawValue == _waybillId) {
          setState(() {
            _currentStep = 1;
            _instruction = 'Position the package for verification';
          });
          _startPackageVerification();
          break;
        }
      }
    });
  }

  void _startPackageVerification() {
    Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_currentStep != 1) {
        timer.cancel();
        return;
      }
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(bytes);
      final similarity = _calculateCosineSimilarity(embedding, _referenceEmbedding!);
      if (similarity >= 0.75) {
        setState(() {
          _currentStep = 2;
          _instruction = 'Move the package towards the locker';
        });
        _lockFocus();
        _startMotionTracking();
        timer.cancel();
      }
    });
  }

  void _lockFocus() {
    _cameraController!.setFocusMode(FocusMode.locked);
    _cameraController!.setExposureMode(ExposureMode.locked);
  }

  void _startMotionTracking() {
    int frameCount = 0;
    _cameraController!.startImageStream((image) async {
      if (_currentStep != 2) return;
      frameCount++;
      if (frameCount % 20 != 0) return; // Process every 20th frame
      final img = TFLiteProcessor.convertCameraImageToImage(image);
      final detections = await TFLiteProcessor.detectYoloObjects(img);
      final packageDetection = detections.firstWhere(
        (d) => d['class'] == 'package' && d['confidence'] > 0.5,
        orElse: () => {},
      );
      if (packageDetection.isNotEmpty) {
        _trackedBox = Rect.fromLTWH(
          packageDetection['x'] * image.width,
          packageDetection['y'] * image.height,
          packageDetection['width'] * image.width,
          packageDetection['height'] * image.height,
        );
        _missCount = 0;
        setState(() {});
      } else {
        _missCount++;
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
        setState(() {
          _currentStep = 3;
          _instruction = 'Package detected in locker';
        });
        _cameraController!.stopImageStream();
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
                    children: List.generate(4, (i) => Icon(
                      i <= _currentStep ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: i <= _currentStep ? Colors.green : Colors.grey,
                    )),
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