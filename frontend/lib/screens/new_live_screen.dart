import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

  // Mobile scanner for barcode
  MobileScannerController? _barcodeController;
  bool _barcodeDetected = false;

  // Detection steps
  int _currentStep = 0; // 0=Guide, 1=BarcodeDetection, 2=PackageDetection, 3=MotionTracking, 4=Success
  String _currentStepTitle = '';
  String _currentInstructions = '';
  
  // Processing flags
  bool _isProcessing = false;
  
  // Reference data from scan
  String? _scannedWaybillId;
  List<double>? _referenceEmbedding;
  String? _referenceWaybillDetails;
  
  // Frame tracking
  int _consecutiveDetections = 0;
  int _consecutiveMotionFrames = 0;
  static const int requiredFrames = 3;
  static const int requiredMotionFrames = 5;
  
  // Bounding box for green frame
  Rect? _detectionBox;
  bool _showGreenFrame = false;

  @override
  void initState() {
    super.initState();
    _initializeBarcodeScanner();
    _initializeCamera();
    _fetchReferenceData();
  }

  void _initializeBarcodeScanner() {
    _barcodeController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _fetchReferenceData() async {
    try {
      final transactionManager = Provider.of<TransactionManager>(
        context,
        listen: false,
      );
      
      _scannedWaybillId = transactionManager.waybillId;
      _referenceEmbedding = transactionManager.embedding;
      _referenceWaybillDetails = transactionManager.waybillDetails;
      
      debugPrint('✅ Reference data loaded:');
      debugPrint('   Waybill ID: $_scannedWaybillId');
      debugPrint('   Embedding length: ${_referenceEmbedding?.length}');
      debugPrint('   Details: $_referenceWaybillDetails');
    } catch (e) {
      debugPrint('❌ Error fetching reference data: $e');
    }
  }

  void _startDetection() {
    setState(() {
      _currentStep = 1;
      _currentStepTitle = 'Step 1: Scan to Detect and Verify the Waybill ID';
      _currentInstructions = 'Position the barcode/QR code within the frame';
    });
    // Step 1 uses mobile scanner, not camera stream
  }

  void _startFrameProcessing() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isProcessing || _currentStep == 0 || _currentStep == 1 || _currentStep == 4) {
        return;
      }

      _isProcessing = true;
      await _processFrame(image);
      _isProcessing = false;
    });
  }

  Future<void> _processFrame(CameraImage frame) async {
    try {
      if (_currentStep == 2) {
        // Step 2: Detect whole package
        await _detectPackage(frame);
      } else if (_currentStep == 3) {
        // Step 3: Track motion of package
        await _trackMotion(frame);
      }
    } catch (e) {
      debugPrint('Error processing frame: $e');
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_barcodeDetected || _isProcessing || _currentStep != 1) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    final scannedBarcode = barcode.rawValue!;

    // Compare with reference waybill ID
    if (_scannedWaybillId != null && scannedBarcode == _scannedWaybillId) {
      _consecutiveDetections++;

      debugPrint('✅ Barcode match! ${_consecutiveDetections}/$requiredFrames');
      debugPrint('   Scanned: $scannedBarcode');
      debugPrint('   Reference: $_scannedWaybillId');

      setState(() {
        _showGreenFrame = true;
        _detectionBox = Rect.fromLTWH(50, 150, 300, 200);
      });

      if (_consecutiveDetections >= requiredFrames) {
        setState(() {
          _barcodeDetected = true;
          _isProcessing = true;
        });

        debugPrint('✅ Waybill barcode verified!');
        _consecutiveDetections = 0;

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _currentStep = 2;
              _currentStepTitle = 'Step 2: Scan to Detect and Verify the Package';
              _currentInstructions = 'Position the entire package within the frame';
              _showGreenFrame = false;
              _barcodeDetected = false;
              _isProcessing = false;
            });
            _startFrameProcessing(); // Start camera stream for package detection
          }
        });
      }
    } else {
      _consecutiveDetections = 0;
      setState(() {
        _showGreenFrame = false;
      });
      
      debugPrint('❌ Barcode mismatch!');
      debugPrint('   Scanned: $scannedBarcode');
      debugPrint('   Expected: $_scannedWaybillId');
    }
  }

  Future<void> _detectPackage(CameraImage frame) async {
    try {
      // Capture image and generate embedding
      final XFile image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      // Compare with reference embedding
      if (_referenceEmbedding != null) {
        final similarity = _calculateCosineSimilarity(embedding, _referenceEmbedding!);
        
        debugPrint('Package similarity: ${(similarity * 100).toStringAsFixed(1)}%');

        if (similarity >= 0.85) {
          _consecutiveDetections++;
          
          setState(() {
            _showGreenFrame = true;
            _detectionBox = Rect.fromLTWH(30, 100, 340, 400);
          });

          if (_consecutiveDetections >= requiredFrames) {
            debugPrint('✅ Package verified!');
            _consecutiveDetections = 0;
            
            await Future.delayed(const Duration(milliseconds: 500));
            
            setState(() {
              _currentStep = 3;
              _currentStepTitle = 'Step 3: Maintain Live Detection while placing';
              _currentInstructions = 'Keep the package in frame while moving to locker';
              _showGreenFrame = false;
            });
          }
        } else {
          _consecutiveDetections = 0;
          setState(() {
            _showGreenFrame = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error detecting package: $e');
    }
  }

  Future<void> _trackMotion(CameraImage frame) async {
    try {
      // Capture image and generate embedding
      final XFile image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      // Compare with reference embedding
      if (_referenceEmbedding != null) {
        final similarity = _calculateCosineSimilarity(embedding, _referenceEmbedding!);
        
        if (similarity >= 0.80) {
          _consecutiveMotionFrames++;
          
          setState(() {
            _showGreenFrame = true;
            _detectionBox = Rect.fromLTWH(30, 100, 340, 400);
          });

          debugPrint('Motion tracking: ${_consecutiveMotionFrames}/$requiredMotionFrames');

          if (_consecutiveMotionFrames >= requiredMotionFrames) {
            debugPrint('✅ Motion tracking complete!');
            
            // Stop image stream
            await _cameraController?.stopImageStream();
            
            await Future.delayed(const Duration(milliseconds: 500));
            
            setState(() {
              _currentStep = 4;
              _currentStepTitle = 'Verification Complete!';
              _currentInstructions = 'Package successfully verified';
              _showGreenFrame = false;
            });

            // Finalize transaction
            _finalizeTransaction();
          }
        } else {
          _consecutiveMotionFrames = 0;
          setState(() {
            _showGreenFrame = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error tracking motion: $e');
    }
  }

  double _calculateCosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0 || normB == 0) return 0.0;
    
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final InputImageRotation imageRotation =
          InputImageRotation.rotation0deg;

      final InputImageFormat inputImageFormat =
          InputImageFormat.nv21;

      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }

  Future<void> _finalizeTransaction() async {
    try {
      final transactionManager = Provider.of<TransactionManager>(
        context,
        listen: false,
      );

      if (transactionManager.transactionId != null) {
        final success = await transactionManager.finalizeTransactionById(
          transactionManager.transactionId!,
        );

        if (success) {
          debugPrint('✅ Transaction finalized successfully');
        }
      }
    } catch (e) {
      debugPrint('Error finalizing transaction: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Step 1: Barcode Scanner
            if (_currentStep == 1 && _barcodeController != null)
              Positioned.fill(
                child: MobileScanner(
                  controller: _barcodeController,
                  onDetect: _onBarcodeDetected,
                ),
              ),

            // Steps 2-3: Camera Preview
            if (_currentStep >= 2 && _currentStep <= 3 && _isCameraInitialized && _cameraController != null)
              Positioned.fill(
                child: CameraPreview(_cameraController!),
              ),

            // Green Detection Frame
            if (_showGreenFrame && _detectionBox != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: DetectionFramePainter(
                    detectionBox: _detectionBox!,
                  ),
                ),
              ),

            // Scanning Frame for Step 1 (Barcode)
            if (_currentStep == 1 && !_showGreenFrame)
              Center(
                child: Container(
                  width: 300,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: ScanningFramePainter(),
                  ),
                ),
              ),

            // Top Header
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _currentStep == 0 ? 'Live Detection' : _currentStepTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_currentStep > 0 && _currentStep < 4)
                      const SizedBox(height: 8),
                    if (_currentStep > 0 && _currentStep < 4)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _showGreenFrame ? 'Verifying: ${(_consecutiveDetections >= requiredFrames ? _consecutiveMotionFrames : _consecutiveDetections)}/${_currentStep == 3 ? requiredMotionFrames : requiredFrames}' : 'Scanning...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Instructions
            if (_currentStep > 0 && _currentStep < 4)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _currentInstructions,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

            // Guide Screen (Step 0)
            if (_currentStep == 0)
              Positioned.fill(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        size: 100,
                        color: Color(0xFF4285F4),
                      ),
                      const SizedBox(height: 32),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Position the package in the frame to verify',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      ElevatedButton(
                        onPressed: _startDetection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Start Live Detection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Success Screen (Step 4)
            if (_currentStep == 4)
              Positioned.fill(
                child: Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 100,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Verified 100%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Package successfully verified!\nYou can now close the locker door.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Return to Home',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Progress indicators
            if (_currentStep > 0 && _currentStep < 4)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildProgressDot(1, 'Barcode'),
                    const SizedBox(width: 8),
                    _buildProgressLine(1),
                    const SizedBox(width: 8),
                    _buildProgressDot(2, 'Package'),
                    const SizedBox(width: 8),
                    _buildProgressLine(2),
                    const SizedBox(width: 8),
                    _buildProgressDot(3, 'Motion'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDot(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;
    
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.green
                : isActive
                    ? const Color(0xFF4285F4)
                    : Colors.grey,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive || isCompleted ? Colors.white : Colors.grey,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressLine(int step) {
    final isCompleted = _currentStep > step;
    
    return Container(
      width: 40,
      height: 2,
      color: isCompleted ? Colors.green : Colors.grey,
    );
  }
}

class ScanningFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw corner brackets only
    const double cornerLength = 40.0;
    
    // Top-left corner
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, cornerLength),
      paint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLength),
      paint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLength),
      paint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(ScanningFramePainter oldDelegate) => false;
}

class DetectionFramePainter extends CustomPainter {
  final Rect detectionBox;

  DetectionFramePainter({required this.detectionBox});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // Draw filled rectangle
    canvas.drawRect(detectionBox, fillPaint);

    // Draw border
    canvas.drawRect(detectionBox, paint);

    // Draw corner brackets
    const double cornerLength = 30.0;
    
    // Top-left corner
    canvas.drawLine(
      detectionBox.topLeft,
      detectionBox.topLeft + const Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      detectionBox.topLeft,
      detectionBox.topLeft + const Offset(0, cornerLength),
      paint,
    );
    
    // Top-right corner
    canvas.drawLine(
      detectionBox.topRight,
      detectionBox.topRight + const Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      detectionBox.topRight,
      detectionBox.topRight + const Offset(0, cornerLength),
      paint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      detectionBox.bottomLeft,
      detectionBox.bottomLeft + const Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      detectionBox.bottomLeft,
      detectionBox.bottomLeft + const Offset(0, -cornerLength),
      paint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      detectionBox.bottomRight,
      detectionBox.bottomRight + const Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      detectionBox.bottomRight,
      detectionBox.bottomRight + const Offset(0, -cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(DetectionFramePainter oldDelegate) {
    return oldDelegate.detectionBox != detectionBox;
  }
}
