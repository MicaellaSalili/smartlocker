import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async';
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'home_screen.dart';
import 'view_transaction_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
    // Diagnostics for Step 2
    bool _isBlurry = false;
    bool _isTooDark = false;
    // Helper functions for diagnostics
    Future<bool> _checkBlur(Uint8List imageBytes) async {
      try {
        final img = await decodeImageFromList(imageBytes);
        // Simple blur check: if width or height < 10, treat as blurry
        if (img.width < 10 || img.height < 10) return true;
        // For demo: always return false (replace with real Laplacian if needed)
        return false;
      } catch (_) {
        return false;
      }
    }

    Future<bool> _checkBrightness(Uint8List imageBytes) async {
      try {
        await decodeImageFromList(imageBytes);
        // For demo: always return false (replace with real brightness check if needed)
        return false;
      } catch (_) {
        return false;
      }
    }
  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // Barcode verification
  bool _barcodeVerified = false;
  int _barcodeMatchFrames = 0;

  // Frame throttling for barcode detection
  DateTime? _lastBarcodeDetectionTime;

  // Detection state
  bool _isDetecting = false;
  Timer? _detectionTimer;
  Timer? _motionTimer;

  // Detection steps
  int _currentStep =
      0; // 0=Guide, 1=Barcode(1/5), 2=Package(2/5), 3=Motion(3/5), 4=Locker(4/5), 5=DoorClosing(5/5), 6=Success
  String _currentStepTitle = '';
  String _currentInstructions = '';

  // Processing flags
  bool _isProcessing = false;

  // Reference data from scan
  String? _scannedWaybillId;
  List<double>? _referenceEmbedding;

  // Frame tracking
  int _consecutiveDetections = 0;
  int _consecutiveMotionFrames = 0;
  static const int requiredFrames = 3;
  static const int requiredMotionFrames = 5;

  // Step 4: Dual detection tracking (package + locker)
  int _packageInLockerFrames = 0;
  int _lockerFrameFrames = 0;
  static const int requiredPackageInLockerFrames = 3;
  static const int requiredLockerFrameFrames = 3;

  // Configurable thresholds
  static const double packageSimilarityThreshold = 0.65;
  static const double packageInLockerThreshold = 0.75;
  static const double lockerFrameThreshold = 0.70;
  static const double motionTrackingThreshold = 0.80;

  // Bounding box for green frame
  Rect? _detectionBox;
  bool _showGreenFrame = false;
  String _matchStatus = ''; // 'Match', 'Mismatch', or empty
  double _currentSimilarity = 0.0;
  String _detectionDiagnostics = ''; // Show what's being detected

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _fetchReferenceData();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
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

      debugPrint('✅ Reference data loaded:');
      debugPrint('   Waybill ID: $_scannedWaybillId');
      debugPrint('   Embedding length: ${_referenceEmbedding?.length}');
    } catch (e) {
      debugPrint('❌ Error fetching reference data: $e');
    }
  }

  void _startDetection() {
    setState(() {
      _currentStep = 1;
      _currentStepTitle = 'Step 1: Scan to Detect and Verify the Waybill ID';
      _currentInstructions = 'Position the barcode/QR code within the frame';
      _barcodeVerified = false;
      _barcodeMatchFrames = 0;
    });
    // Start camera stream for barcode detection
    _startFrameProcessing();
  }

  void _startFrameProcessing() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Only start image stream if not already streaming
    if (!_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream((CameraImage image) async {
        if (_isProcessing || _currentStep == 0 || _currentStep >= 5) {
          return;
        }

        _isProcessing = true;
        await _processFrame(image);
        _isProcessing = false;
      });
    }
  }

  Future<void> _processFrame(CameraImage frame) async {
    try {
      // Step 1: Barcode detection using camera stream
      if (_currentStep == 1 && !_barcodeVerified) {
        await _detectBarcodeFromFrame(frame);
        return;
      }

      // Step 2: Package detection (handled by timer)
      if (_currentStep == 2) {
        return; // Detection handled by _detectPackage timer
      }

      // Step 3: Motion tracking (handled by timer)
      if (_currentStep == 3) {
        return; // Motion tracking handled by _trackMotion timer
      }
    } catch (e) {
      debugPrint('Error processing frame: $e');
    }
  }

  Future<void> _detectBarcodeFromFrame(CameraImage cameraImage) async {
    if (_isDetecting) return;

    // Throttle barcode detection to every 500ms
    final now = DateTime.now();
    if (_lastBarcodeDetectionTime != null &&
        now.difference(_lastBarcodeDetectionTime!).inMilliseconds < 500) {
      return;
    }
    _lastBarcodeDetectionTime = now;

    _isDetecting = true;

    try {
      // Convert CameraImage to InputImage for ML Kit
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        cameraImage.width.toDouble(),
        cameraImage.height.toDouble(),
      );

      final InputImageRotation imageRotation = InputImageRotation.rotation0deg;
      final InputImageFormat inputImageFormat = InputImageFormat.yuv420;

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );

      // Use Google ML Kit Barcode Scanner
      final barcodeScanner = BarcodeScanner();
      final List<Barcode> barcodes = await barcodeScanner.processImage(
        inputImage,
      );
      await barcodeScanner.close();

      if (barcodes.isEmpty) {
        _isDetecting = false;
        return;
      }

      final barcode = barcodes.first;
      if (barcode.rawValue == null) {
        _isDetecting = false;
        return;
      }

      final scannedBarcode = barcode.rawValue!;
      debugPrint('📱 Barcode detected: $scannedBarcode');

      // If no reference barcode, accept any barcode
      if (_scannedWaybillId == null || _scannedWaybillId!.isEmpty) {
        debugPrint(
          '⚠️ No reference waybill ID stored, accepting scanned barcode',
        );
        _barcodeMatchFrames++;

        if (_barcodeMatchFrames >= 1 && mounted) {
          setState(() {
            _barcodeVerified = true;
            _showGreenFrame = true;
            _detectionBox = Rect.fromLTWH(50, 150, 300, 200);
          });

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            setState(() {
              _currentStep = 2;
              _currentStepTitle =
                  'Step 2: Scan to Detect and Verify the Package';
                _currentInstructions =
                    'Position the entire package within the frame. The system will verify by matching the package’s visual features.';
              _barcodeMatchFrames = 0;
              _showGreenFrame = false;
            });
            _startObjectDetection();
          }
        }
        _isDetecting = false;
        return;
      }

      // Compare with reference waybill ID
      if (scannedBarcode == _scannedWaybillId) {
        _barcodeMatchFrames++;
        debugPrint('✅ Barcode match! ${_barcodeMatchFrames}/1');

        setState(() {
          _showGreenFrame = true;
          _detectionBox = Rect.fromLTWH(50, 150, 300, 200);
          _matchStatus = 'Match';
          _currentSimilarity = 100.0;
        });

        if (_barcodeMatchFrames >= 1 && mounted) {
          setState(() {
            _barcodeVerified = true;
          });

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            setState(() {
              _currentStep = 2;
              _currentStepTitle =
                  'Step 2: Scan to Detect and Verify the Package';
              _currentInstructions =
                  'Position the entire package within the frame';
              _barcodeMatchFrames = 0;
              _showGreenFrame = false;
            });
            _startObjectDetection();
          }
        }
      } else {
        _barcodeMatchFrames = 0;
        setState(() {
          _showGreenFrame = false;
          _matchStatus = 'Mismatch';
          _currentSimilarity = 0.0;
        });
        debugPrint('❌ Barcode mismatch: $scannedBarcode vs $_scannedWaybillId');
      }
    } catch (e) {
      debugPrint('⚠️ Barcode detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  void _startObjectDetection() {
    if (_detectionTimer != null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    setState(() {
      _showGreenFrame = true;
      _detectionBox = Rect.fromCenter(
        center: Offset(screenWidth / 2, screenHeight / 2),
        width: screenWidth * 0.75,
        height: screenHeight * 0.55,
      );
    });

    // Start detection timer
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 800), (
      timer,
    ) async {
      if (!mounted || _isDetecting || _currentStep != 2) {
        return;
      }
      await _detectPackage();
    });
  }

  void _stopObjectDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
    setState(() {
      _showGreenFrame = false;
    });
  }

  void _startMotionTracking() {
    // Start periodic motion tracking (every 800ms)
    _motionTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_currentStep == 3 && !_isDetecting) {
        _trackMotion();
      }
    });
  }

  void _stopMotionTracking() {
    _motionTimer?.cancel();
    _motionTimer = null;
    _consecutiveMotionFrames = 0;
  }

  Timer? _lockerTimer;

  void _startLockerVerification() {
    // Reset dual tracking counters
    _packageInLockerFrames = 0;
    _lockerFrameFrames = 0;

    setState(() {
      _detectionDiagnostics = 'Detecting: Package + Locker';
    });

    // Start periodic dual detection (every 800ms)
    _lockerTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_currentStep == 4 && !_isDetecting) {
        _detectPackageAndLocker();
      }
    });
  }

  void _stopLockerVerification() {
    _lockerTimer?.cancel();
    _lockerTimer = null;
    _packageInLockerFrames = 0;
    _lockerFrameFrames = 0;
    setState(() {
      _detectionDiagnostics = '';
    });
  }

  Future<void> _detectPackageAndLocker() async {
    if (_isDetecting || _currentStep != 4) return;

    try {
      _isDetecting = true;

      // Capture image for dual detection
      final XFile image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      if (_referenceEmbedding != null) {
        final similarity = _calculateCosineSimilarity(
          embedding,
          _referenceEmbedding!,
        );

        // Check if package is detected (in locker position)
        final packageDetected = similarity >= packageInLockerThreshold;

        // Check if locker frame is detected (lower threshold to detect locker edges)
        final lockerDetected = similarity >= lockerFrameThreshold;

        debugPrint(
          '📦 Package: ${(similarity * 100).toStringAsFixed(1)}% (${packageDetected ? "✓" : "✗"}) | '
          '🚪 Locker: ${(similarity * 100).toStringAsFixed(1)}% (${lockerDetected ? "✓" : "✗"})',
        );

        // Update frame counters based on detection
        if (packageDetected) {
          _packageInLockerFrames++;
        } else {
          _packageInLockerFrames = 0;
        }

        if (lockerDetected) {
          _lockerFrameFrames++;
        } else {
          _lockerFrameFrames = 0;
        }

        // Update UI with real-time diagnostics
        setState(() {
          if (packageDetected && lockerDetected) {
            _showGreenFrame = true;
            _matchStatus = 'Match';
            _currentSimilarity = similarity * 100;
            _detectionDiagnostics =
                'Package: ${_packageInLockerFrames}/${requiredPackageInLockerFrames} | '
                'Locker: ${_lockerFrameFrames}/${requiredLockerFrameFrames}';
          } else if (!packageDetected && lockerDetected) {
            _showGreenFrame = false;
            _matchStatus = 'Package Missing';
            _currentSimilarity = similarity * 100;
            _detectionDiagnostics =
                '⚠️ Package not detected. Adjust camera position.';
          } else if (packageDetected && !lockerDetected) {
            _showGreenFrame = false;
            _matchStatus = 'Locker Missing';
            _currentSimilarity = similarity * 100;
            _detectionDiagnostics =
                '⚠️ Locker frame not detected. Point camera at locker.';
          } else {
            _showGreenFrame = false;
            _matchStatus = 'Mismatch';
            _currentSimilarity = similarity * 100;
            _detectionDiagnostics =
                '⚠️ Neither package nor locker detected clearly.';
          }
        });

        // Check if both package and locker are consistently detected
        if (_packageInLockerFrames >= requiredPackageInLockerFrames &&
            _lockerFrameFrames >= requiredLockerFrameFrames) {
          debugPrint(
            '✅ Both package and locker verified! '
            'Package: ${_packageInLockerFrames}/${requiredPackageInLockerFrames}, '
            'Locker: ${_lockerFrameFrames}/${requiredLockerFrameFrames}',
          );

          // Stop locker verification
          _stopLockerVerification();

          await Future.delayed(const Duration(milliseconds: 500));

          setState(() {
            _showGreenFrame = false;
            _matchStatus = '';
            _detectionDiagnostics = '';
          });

          // Start placement countdown
          _startLockerPlacementCountdown();
        }
      }
    } catch (e) {
      debugPrint('Error detecting package and locker: $e');
    } finally {
      _isDetecting = false;
    }
  }

  int _doorCountdown = 5;
  Timer? _countdownTimer;
  int _lockerPlacementCountdown = 5;
  Timer? _lockerPlacementTimer;

  void _startLockerPlacementCountdown() {
    _lockerPlacementCountdown = 5;
    setState(() {
      _currentInstructions =
          'PUT IT NOW IN THE LOCKER IN ${_lockerPlacementCountdown}s';
    });

    _lockerPlacementTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockerPlacementCountdown > 1) {
        setState(() {
          _lockerPlacementCountdown--;
          _currentInstructions =
              'PUT IT NOW IN THE LOCKER IN ${_lockerPlacementCountdown}s';
        });
      } else {
        timer.cancel();
        _moveToStep5();
      }
    });
  }

  void _moveToStep5() async {
    await _cameraController?.stopImageStream();

    setState(() {
      _currentStep = 5;
      _currentStepTitle = 'Step 5: Door Closing';
      _currentInstructions =
          'Close the Door Immediately to complete the drop. Failure to close the door will make you restart the entire process.';
      _showGreenFrame = false;
    });

    // Start door closing countdown
    _startDoorClosingCountdown();
  }

  void _startDoorClosingCountdown() {
    _doorCountdown = 5;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_doorCountdown > 0) {
        setState(() {
          _doorCountdown--;
          _currentInstructions = 'Doors Closing in ${_doorCountdown}s.';
        });
      } else {
        timer.cancel();
        _completeDrop();
      }
    });
  }

  void _completeDrop() async {
    setState(() {
      _currentStep = 6;
      _currentStepTitle = 'Verification Complete!';
      _currentInstructions = 'Package successfully verified and placed';
      _showGreenFrame = false;
    });

    // Save transaction to database before finalizing
    final transactionManager = Provider.of<TransactionManager>(
      context,
      listen: false,
    );
    // Debug print all required fields
    debugPrint('--- TransactionManager fields before saving ---');
    debugPrint('auditData: ${transactionManager.auditData}');
    debugPrint('lockerId: ${transactionManager.lockerId}');
    debugPrint('waybillId: ${transactionManager.waybillId}');
    debugPrint('waybillDetails: ${transactionManager.waybillDetails}');
    debugPrint('embedding: ${transactionManager.embedding}');
    debugPrint('---------------------------------------------');

    bool transactionSaved = false;
    if (transactionManager.auditData == null) {
      debugPrint('❌ Missing recipient info (auditData). Please set recipient info before saving.');
    } else if (transactionManager.lockerId == null) {
      debugPrint('❌ Missing lockerId.');
    } else if (transactionManager.waybillId == null) {
      debugPrint('❌ Missing waybillId.');
    } else if (transactionManager.waybillDetails == null) {
      debugPrint('❌ Missing waybillDetails.');
    } else if (transactionManager.embedding == null || transactionManager.embedding!.length != 128) {
      debugPrint('❌ Missing or invalid embedding (must be 128 numbers).');
    } else {
      transactionSaved = await transactionManager.logTransactionData(
        lockerId: transactionManager.lockerId!,
        waybillId: transactionManager.waybillId!,
        waybillDetails: transactionManager.waybillDetails!,
        embedding: transactionManager.embedding!,
      );
      if (transactionSaved) {
        debugPrint('✅ Transaction data saved successfully.');
      } else {
        debugPrint('❌ Transaction data failed to save.');
      }
    }

    // Finalize transaction only if transaction was saved
    if (transactionSaved) {
      await _finalizeTransaction();
    } else {
      debugPrint('❌ Transaction not finalized because save failed.');
    }

    // Lock the locker after verification only if transaction was saved
    if (transactionSaved && transactionManager.lockerId != null) {
      final locked = await transactionManager.lockLockerById(transactionManager.lockerId!);
      if (locked) {
        debugPrint('✅ Locker locked successfully');
      } else {
        debugPrint('❌ Failed to lock locker');
      }
    } else if (!transactionSaved) {
      debugPrint('❌ Locker not locked because transaction was not saved.');
    }
  }

  Future<void> _detectPackage() async {
    try {
      // Capture image and generate embedding
      final XFile image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      // Run diagnostics
      _isBlurry = await _checkBlur(imageBytes);
      _isTooDark = await _checkBrightness(imageBytes);

      // Compare with reference embedding
      if (_referenceEmbedding != null) {
        final similarity = _calculateCosineSimilarity(
          embedding,
          _referenceEmbedding!,
        );

        debugPrint(
          'Package similarity: ${(similarity * 100).toStringAsFixed(1)}%',
        );

        // Always display match percentage
        _detectionDiagnostics = 'Similarity: ${(similarity * 100).toStringAsFixed(1)}%';
        if (_isBlurry) {
          _detectionDiagnostics += '\nPossible reason: Image is blurry.';
        }
        if (_isTooDark) {
          _detectionDiagnostics += '\nPossible reason: Lighting is poor.';
        }

        if (similarity >= packageSimilarityThreshold) {
          _consecutiveDetections++;
          setState(() {
            _showGreenFrame = true;
            _detectionBox = Rect.fromLTWH(30, 100, 340, 400);
            _matchStatus = 'Match';
            _currentSimilarity = similarity * 100;
          });

          if (_consecutiveDetections >= requiredFrames) {
            debugPrint('✅ Package verified!');
            _consecutiveDetections = 0;

            // Stop package detection timer
            _stopObjectDetection();

            await Future.delayed(const Duration(milliseconds: 500));

            // Bypass Step 3 and move directly to Step 4
            setState(() {
              _currentStep = 4;
              _currentStepTitle = 'Step 4: Find the Locker and Verify';
              _currentInstructions = 'Point camera at the locker to verify placement';
              _showGreenFrame = false;
              _matchStatus = '';
              _currentSimilarity = 0.0;
            });

            // Start locker verification
            _startLockerVerification();
          }
        } else {
          _consecutiveDetections = 0;
          setState(() {
            _showGreenFrame = false;
            _matchStatus = 'Mismatch';
            _currentSimilarity = similarity * 100;
          });
        }
      }
    } catch (e) {
      debugPrint('Error detecting package: $e');
    }
  }

  Future<void> _trackMotion() async {
    if (_isDetecting || _currentStep != 3) return;

    try {
      _isDetecting = true;

      // Capture image and generate embedding
      final XFile image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      // Compare with reference embedding
      if (_referenceEmbedding != null) {
        final similarity = _calculateCosineSimilarity(
          embedding,
          _referenceEmbedding!,
        );

        final isMatch = similarity >= motionTrackingThreshold;

        if (isMatch) {
          _consecutiveMotionFrames++;

          setState(() {
            // Show the green frame with fixed bounding box
            _showGreenFrame = true;
            _detectionBox = Rect.fromLTWH(30, 100, 340, 400);
            _matchStatus = 'Match';
            _currentSimilarity = similarity * 100;
          });

          debugPrint(
            'Motion tracking: ${_consecutiveMotionFrames}/$requiredMotionFrames',
          );

          if (_consecutiveMotionFrames >= requiredMotionFrames) {
            debugPrint('✅ Motion tracking complete! Moving to Step 4');

            // Stop motion tracking
            _stopMotionTracking();
            _consecutiveMotionFrames = 0;

            await Future.delayed(const Duration(milliseconds: 500));

            setState(() {
              _currentStep = 4;
              _currentStepTitle = 'Step 4: Find the Locker and Verify';
              _currentInstructions =
                  'Point camera at the locker to verify placement';
              _showGreenFrame = false; // Step 4 manages its own frame
              _matchStatus = '';
              _currentSimilarity = 0.0;
            });

            // Start locker verification
            _startLockerVerification();
          }
        } else {
          _consecutiveMotionFrames = 0;
          setState(() {
            // Hide green frame and show mismatch
            _showGreenFrame = false;
            _matchStatus = 'Mismatch';
            _currentSimilarity = similarity * 100;
          });
        }
      }
    } catch (e) {
      debugPrint('Error tracking motion: $e');
    } finally {
      _isDetecting = false;
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
    _detectionTimer?.cancel();
    _motionTimer?.cancel();
    _lockerTimer?.cancel();
    _countdownTimer?.cancel();
    _lockerPlacementTimer?.cancel();
    _stopObjectDetection();
    _stopMotionTracking();
    _stopLockerVerification();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Step 1-4: Camera Preview (unified camera for all steps)
            if (_currentStep >= 1 &&
                _currentStep <= 4 &&
                _isCameraInitialized &&
                _cameraController != null)
              Positioned.fill(child: CameraPreview(_cameraController!)),

            // Green Detection Frame
            if (_showGreenFrame && _detectionBox != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: DetectionFramePainter(detectionBox: _detectionBox!),
                ),
              ),

            // Match/Mismatch Label on top of detection box
            if (_matchStatus.isNotEmpty && _detectionBox != null)
              Positioned(
                top: _detectionBox!.top - 40,
                left: _detectionBox!.left,
                right: MediaQuery.of(context).size.width - _detectionBox!.right,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _matchStatus == 'Match' ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _matchStatus == 'Match'
                        ? 'Match'
                        : _matchStatus == 'Package Missing'
                        ? 'Package Missing'
                        : _matchStatus == 'Locker Missing'
                        ? 'Locker Missing'
                        : 'Mismatch - ${_currentSimilarity.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Real-time diagnostics for Step 4
            if (_currentStep == 4 && _detectionDiagnostics.isNotEmpty)
              Positioned(
                top: 80,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: Text(
                    _detectionDiagnostics,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
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
                  child: CustomPaint(painter: ScanningFramePainter()),
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
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
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
                    if (_currentStep > 0 && _currentStep < 6)
                      const SizedBox(height: 8),
                    if (_currentStep > 0 && _currentStep < 6)
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
                          _currentStep == 4 && _showGreenFrame
                              ? 'Verifying: Pkg ${_packageInLockerFrames}/${requiredPackageInLockerFrames} | Lkr ${_lockerFrameFrames}/${requiredLockerFrameFrames}'
                              : _showGreenFrame
                              ? 'Verifying: ${(_consecutiveDetections >= requiredFrames ? _consecutiveMotionFrames : _consecutiveDetections)}/${_currentStep == 3 ? requiredMotionFrames : requiredFrames}'
                              : 'Scanning...',
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

            // Instructions and diagnostics for Step 2
            if (_currentStep == 2)
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentInstructions,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      if (_matchStatus == 'Mismatch') ...[
                        const SizedBox(height: 12),
                        Text(
                          _detectionDiagnostics,
                          style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            // Instructions for other steps
            if (_currentStep > 0 && _currentStep < 6 && _currentStep != 2)
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
                    style: const TextStyle(color: Colors.white, fontSize: 16),
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

            // Success Screen (Step 6)
            if (_currentStep == 6)
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
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 48),
                      ElevatedButton(
                        onPressed: () {
                          // Review Transaction navigation
                          final transactionManager = Provider.of<TransactionManager>(
                            context,
                            listen: false,
                          );
                          final transactionData = {
                            'id': 'Transaction ID: ${transactionManager.waybillId ?? "000000"}',
                            'recipient': 'Recipient: ${transactionManager.auditData?.firstName ?? ""} ${transactionManager.auditData?.lastName ?? ""}',
                            'phone': '${transactionManager.auditData?.phoneNumber ?? "N/A"}',
                            'locker': 'Locker: Smart Locker 001',
                            'status': 'Delivered',
                            'timestamp': DateTime.now().millisecondsSinceEpoch,
                            'waybill_id': transactionManager.waybillId,
                            'waybill_details': transactionManager.waybillDetails,
                            'qr_scanned': 'Yes',
                            'package_details': 'Scanned and logged',
                            'verification_status': 'Verified',
                            'color': Colors.green,
                          };
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => ViewTransactionScreen(transaction: transactionData),
                            ),
                            (route) => false,
                          );
                        },
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
                          'Review Transaction',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const HomeScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
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
                            color: Colors.black,
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
            if (_currentStep > 0 && _currentStep < 6)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildProgressDot(1, 'Barcode'),
                    const SizedBox(width: 4),
                    _buildProgressLine(1),
                    const SizedBox(width: 4),
                    _buildProgressDot(2, 'Package'),
                    const SizedBox(width: 4),
                    _buildProgressLine(2),
                    const SizedBox(width: 4),
                    _buildProgressDot(3, 'Motion'),
                    const SizedBox(width: 4),
                    _buildProgressLine(3),
                    const SizedBox(width: 4),
                    _buildProgressDot(4, 'Locker'),
                    const SizedBox(width: 4),
                    _buildProgressLine(4),
                    const SizedBox(width: 4),
                    _buildProgressDot(5, 'Door'),
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
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLength), paint);

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
