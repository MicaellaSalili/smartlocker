import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async';
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';
import 'view_transaction_screen.dart';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

int _currentStep =
    0; // 0: Guide, 1: Live Detection, 2-6: Scan Steps, 7: Success, 8: Failure
bool _showDoorCountdown = false;
int _doorCountdown = 5;

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isVerifying = false;
  String _verificationStatus = 'Initializing camera...';
  List<double>? _referenceEmbedding;
  String? _referenceWaybillId;
  String? _referenceWaybillDetails;
  int _consecutiveSuccessFrames = 0;
  bool _isProcessingFrame = false;

  // New state variables for countdown and verification control
  Timer? _closeDoorTimer;
  int _countdown = 3;
  bool _isVerificationStarted = false;

  int _stepDelayMs = 1000; // 1 second per step
  bool _stepAdvancing = false;

  // Edge detection for Step 2
  bool _showDetectionFrame = false;
  Rect? _detectionBox;
  bool _packageInFrame = false;
  int _edgeDetectionFrames = 0;
  static const int requiredEdgeFrames = 3;

  // Barcode verification for steps
  bool _barcodeVerified = false;
  int _barcodeMatchFrames = 0;

  // Simple camera-based package tracking
  bool _isDetecting = false;
  Timer? _detectionTimer;
  int _packageDetectionCount = 0;

  // Frame throttling for barcode detection
  DateTime? _lastBarcodeDetectionTime;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  // Barcode scanner removed - using camera stream for barcode detection via Google ML Kit

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.max, // Set to max for best quality
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _verificationStatus = 'Camera ready. Fetching reference data...';
          });
          await _fetchReferenceData();
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _verificationStatus = 'Camera initialization failed';
        });
      }
    }
  }

  Future<void> _fetchReferenceData() async {
    try {
      // Call TransactionManager to fetch reference data
      final transactionManager = Provider.of<TransactionManager>(
        context,
        listen: false,
      );
      final hasData = await transactionManager.fetchReferenceData();

      // Get the stored data from transaction manager
      _referenceEmbedding = transactionManager.embedding;
      _referenceWaybillId = transactionManager.waybillId;
      _referenceWaybillDetails = transactionManager.waybillDetails;

      if (hasData && _referenceEmbedding != null) {
        setState(() {
          _verificationStatus = 'Reference data loaded. Ready to verify.';
        });
        // Start live verification loop
        _startLiveVerification();
      } else {
        setState(() {
          _verificationStatus =
              'No reference data found. Please scan package first.';
        });
      }
    } catch (e) {
      debugPrint('Error fetching reference data: $e');
      setState(() {
        _verificationStatus = 'Failed to fetch reference data';
      });
    }
  }

  void _startLiveVerification() {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isVerifying) {
      return;
    }

    setState(() {
      _isVerifying = true;
      _verificationStatus = 'Verifying package placement...';
      _consecutiveSuccessFrames = 0;
    });

    // Only start image stream if not already streaming
    if (!_controller!.value.isStreamingImages) {
      _controller!.startImageStream((CameraImage image) async {
        if (!_isVerifying || _isProcessingFrame) {
          return;
        }

        _isProcessingFrame = true;
        await _processFrame(image);
        _isProcessingFrame = false;
      });
    }
  }

  /// Process a single camera frame for verification
  Future<void> _processFrame(CameraImage frame) async {
    // Step 2: Barcode detection using camera stream
    if (_currentStep == 2 && !_barcodeVerified && !_stepAdvancing) {
      await _detectBarcodeFromFrame(frame);
      return;
    }

    // Step 3: Package detection (handled by timer)
    if (_currentStep == 3) {
      return; // Detection handled by _detectPackageInFrame timer
    }

    // Other steps: Auto-advance
    if (mounted && !_stepAdvancing && _currentStep >= 4 && _currentStep < 6) {
      _stepAdvancing = true;
      setState(() {
        if (_currentStep < 6) {
          _currentStep++;
        } else if (_currentStep == 6 && !_showDoorCountdown) {
          _startCloseDoorCountdown();
        }
      });
      await Future.delayed(Duration(milliseconds: _stepDelayMs));
      _stepAdvancing = false;
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

      // Determine rotation based on device orientation
      final InputImageRotation imageRotation = InputImageRotation.rotation0deg;

      // Use yuv420 format since that's what we initialized the camera with
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
      if (_referenceWaybillId == null || _referenceWaybillId!.isEmpty) {
        debugPrint(
          '⚠️ No reference waybill ID stored, accepting scanned barcode',
        );
        _barcodeMatchFrames++;

        if (_barcodeMatchFrames >= 1 && mounted) {
          setState(() {
            _barcodeVerified = true;
          });

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            setState(() {
              _currentStep = 3;
              _barcodeMatchFrames = 0;
            });
            // Start object detection for Step 3 (package detection)
            _startObjectDetection();
          }
        }
        _isDetecting = false;
        return;
      }

      // Compare with reference waybill ID
      if (scannedBarcode == _referenceWaybillId) {
        _barcodeMatchFrames++;
        debugPrint('✅ Barcode match! ${_barcodeMatchFrames}/1');

        if (_barcodeMatchFrames >= 1 && mounted) {
          setState(() {
            _barcodeVerified = true;
          });

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            setState(() {
              _currentStep = 3;
              _barcodeMatchFrames = 0;
            });
            // Start object detection for Step 3 (package detection)
            _startObjectDetection();
          }
        }
      } else {
        _barcodeMatchFrames = 0;
        debugPrint(
          '❌ Barcode mismatch: $scannedBarcode vs $_referenceWaybillId',
        );
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
      _showDetectionFrame = true;
      _detectionBox = Rect.fromCenter(
        center: Offset(screenWidth / 2, screenHeight / 2),
        width: screenWidth * 0.75,
        height: screenHeight * 0.55,
      );
      _packageDetectionCount = 0;
    });

    // Start detection timer
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 800), (
      timer,
    ) async {
      if (!mounted || _isDetecting || _currentStep != 3) {
        return;
      }
      await _detectPackageInFrame();
    });
  }

  void _stopObjectDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
    setState(() {
      _showDetectionFrame = false;
      _packageInFrame = false;
      _edgeDetectionFrames = 0;
      _packageDetectionCount = 0;
    });
  }

  Future<void> _detectPackageInFrame() async {
    if (_isDetecting ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        _referenceEmbedding == null) {
      return;
    }

    _isDetecting = true;

    try {
      // Take a picture from current frame
      final image = await _controller!.takePicture();
      final imageBytes = await File(image.path).readAsBytes();

      // Generate embedding for current frame
      final currentEmbedding = await TFLiteProcessor.generateEmbedding(
        imageBytes,
      );

      // Calculate similarity with reference
      final similarity = _calculateCosineSimilarity(
        currentEmbedding,
        _referenceEmbedding!,
      );

      debugPrint(
        '📦 Package similarity: ${(similarity * 100).toStringAsFixed(1)}%',
      );

      if (similarity >= 0.85) {
        _edgeDetectionFrames++;
        _packageDetectionCount++;
        debugPrint(
          '✅ Package match! Frame ${_edgeDetectionFrames}/$requiredEdgeFrames',
        );

        if (_edgeDetectionFrames >= requiredEdgeFrames) {
          setState(() {
            _packageInFrame = true;
          });

          debugPrint('🎉 Package verified! Advancing to step 4');

          _stopObjectDetection();

          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            setState(() {
              _currentStep = 4;
            });
          }
        } else {
          setState(() {
            _packageInFrame = true;
          });
        }
      } else {
        if (_edgeDetectionFrames > 0) {
          _edgeDetectionFrames--;
          debugPrint(
            '⚠️ Package moved or changed. Count: $_edgeDetectionFrames',
          );
        }
        setState(() {
          _packageInFrame = false;
        });
      }

      // Clean up temp file
      await File(image.path).delete();
    } catch (e) {
      debugPrint('❌ Detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  /// Start the close door countdown after successful verification
  void _startCloseDoorCountdown() {
    debugPrint('Starting close door countdown');

    // Set verification started flag
    _isVerificationStarted = true;

    // Show the door countdown popup
    setState(() {
      _showDoorCountdown = true;
      _doorCountdown = 5; // Updated to 5 seconds
    });

    // a) Stop the image stream to pause continuous processing
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }

    // Reset countdown to 5 seconds
    _countdown = 5;

    // b) Start countdown timer
    _closeDoorTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _doorCountdown = _countdown; // Update countdown display
        });
      }

      if (_countdown > 1) {
        _countdown--; // Countdown logic updated to show 5-1
      } else {
        // Countdown finished, hide popup and continue verifying step 6
        timer.cancel();
        if (mounted) {
          setState(() {
            _showDoorCountdown = false;
            // Return to live detection for verifying 6/6
            // The verification loop will continue and show success screen after required frames
            // Do not call _stopAndFinalize here
            // Ensure _currentStep remains at 7 for 6/6 verification
          });
        }
      }
    });
  }

  /// Calculate Cosine Similarity between two vectors
  double _calculateCosineSimilarity(
    List<double> vectorA,
    List<double> vectorB,
  ) {
    if (vectorA.length != vectorB.length) {
      debugPrint('Warning: Vector length mismatch');
      return 0.0;
    }

    double dotProduct = 0.0;
    double magnitudeA = 0.0;
    double magnitudeB = 0.0;

    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      magnitudeA += vectorA[i] * vectorA[i];
      magnitudeB += vectorB[i] * vectorB[i];
    }

    magnitudeA = math.sqrt(magnitudeA);
    magnitudeB = math.sqrt(magnitudeB);

    if (magnitudeA == 0.0 || magnitudeB == 0.0) {
      return 0.0;
    }

    return dotProduct / (magnitudeA * magnitudeB);
  }

  void _stopLiveVerification() {
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    setState(() {
      _isVerifying = false;
    });
  }

  @override
  void dispose() {
    _closeDoorTimer?.cancel();
    _detectionTimer?.cancel();
    _stopObjectDetection();
    _stopLiveVerification();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Builder(
          builder: (context) {
            // Step 0: Guide
            if (_currentStep == 0) {
              return Stack(
                children: [
                  // Header
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 64,
                      color: const Color(0xFF4285F4),
                      alignment: Alignment.center,
                      child: const Text(
                        'Live Detection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // Guide Card
                  Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.85,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Placeholder for illustration
                          Container(
                            height: 120,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green, width: 3),
                            ),
                            child: const Icon(
                              Icons.inventory_2,
                              size: 64,
                              color: Colors.brown,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Guide instructions
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                '1. Center the PACKAGE',
                                style: TextStyle(fontSize: 16),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '2. Ensure WAYBILL & QR/BARCODE are FLAT & FACING FRONT',
                                style: TextStyle(fontSize: 16),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '3. Check for CLEAR, Bright LIGHTING',
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Start button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _currentStep = 1;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4285F4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Got it! Start Live Detection',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Cancel button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: const BorderSide(
                                  color: Colors.grey,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // Step 1: Live Detection (preview, instructions, capture button)
            if (_currentStep == 1) {
              return Stack(
                children: [
                  // Camera Preview Fullscreen (NO scan frame overlay)
                  Positioned.fill(
                    child: _isCameraInitialized && _controller != null
                        ? CameraPreview(_controller!)
                        : Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                  ),
                  // Header
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 64,
                      color: const Color(0xFF4285F4),
                      alignment: Alignment.center,
                      child: const Text(
                        'Live Detection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // Instructions and buttons
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Position the entire package, waybill, and QR/barcode. Ensure the view is clear.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _currentStep = 2;
                                  _barcodeVerified = false;
                                  _barcodeMatchFrames = 0;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4285F4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Capture & Log Package',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _currentStep = 0;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: const BorderSide(
                                  color: Colors.grey,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // Steps 2-7: Scan Package, Verification, Door Closing, Success, Failure
            if (_currentStep >= 2 && _currentStep <= 7) {
              final List<Map<String, String>> scanSteps = [
                {
                  'title': 'Scan to Detect and Verify the Waybill ID',
                  'desc': 'Collected Data: Waybill ID',
                  'progress': '1/5',
                },
                {
                  'title': 'Scan to Detect and Verify the Package',
                  'desc': 'Collected Data: Package',
                  'progress': '2/5',
                },
                {
                  'title': 'Maintain Live Detection while placing',
                  'desc': 'Collected Data: Placement Validation',
                  'progress': '3/5',
                },
                {
                  'title': 'Scan and Detect to Verify Locker',
                  'desc': 'Collected Data: Locker Frame',
                  'progress': '4/5',
                },
                {
                  'title': 'Scan and Detect to Verify Locker',
                  'desc': 'Collected Data: Locker Door Closed',
                  'progress': '5/5',
                },
              ];
              int stepIndex = (_currentStep - 2).clamp(0, scanSteps.length - 1);
              final step = scanSteps[stepIndex];

              // Door Closing Popup for step 6
              if (_currentStep == 6 && _showDoorCountdown) {
                // Show modal popup overlay
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _isCameraInitialized && _controller != null
                          ? CameraPreview(_controller!)
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 64,
                        color: const Color(0xFF4285F4),
                        alignment: Alignment.center,
                        child: const Text(
                          'Door Closing',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    // Popup overlay
                    Center(
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.85,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.door_front_door,
                              size: 64,
                              color: Colors.green,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Doors Closing in ${_doorCountdown}s.',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Close the Door immediately to complete the delivery. Failure to close the door will make you restart the entire process.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (_currentStep == 6 && !_showDoorCountdown) {
                // Success screen
                return Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 64,
                                color: Colors.green,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Success!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'VERIFIED DELIVERY',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2C3E50),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  _ChecklistItem(
                                    text: 'Waybill ID Match',
                                    success: true,
                                  ),
                                  _ChecklistItem(
                                    text: 'Package Match',
                                    success: true,
                                  ),
                                  _ChecklistItem(
                                    text: 'Placement Validation',
                                    success: true,
                                  ),
                                  _ChecklistItem(
                                    text: 'Locker Frame Match',
                                    success: true,
                                  ),
                                  _ChecklistItem(
                                    text: 'Locker Door Closed',
                                    success: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              final transactionManager =
                                  Provider.of<TransactionManager>(
                                    context,
                                    listen: false,
                                  );
                              final transactionData = {
                                'id':
                                    'Transaction ID: ${transactionManager.waybillId ?? "000000"}',
                                'recipient':
                                    'Recipient: ${transactionManager.auditData?.firstName ?? ""} ${transactionManager.auditData?.lastName ?? ""}',
                                'phone':
                                    '${transactionManager.auditData?.phoneNumber ?? "N/A"}',
                                'locker': 'Locker: Smart Locker 001',
                                'status': 'Delivered',
                                'timestamp':
                                    DateTime.now().millisecondsSinceEpoch,
                                'waybill_id': transactionManager.waybillId,
                                'waybill_details':
                                    transactionManager.waybillDetails,
                                'qr_scanned': 'Yes',
                                'package_details': 'Scanned and logged',
                                'verification_status': 'Verified',
                                'color': Colors.green,
                              };
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (context) => ViewTransactionScreen(
                                    transaction: transactionData,
                                  ),
                                ),
                                (route) => false,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4285F4),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Review Transaction',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _currentStep = 0;
                              });
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Return to Home',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Step card UI for steps 2-6
              return Stack(
                children: [
                  // Steps 2-6: Camera Preview (unified camera for everything)
                  if (_currentStep >= 2 && _currentStep <= 6)
                    Positioned.fill(
                      child: _isCameraInitialized && _controller != null
                          ? CameraPreview(_controller!)
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                    ),
                  // Detection Frame Overlay for Step 3 (Package Detection)
                  if (_currentStep == 3 &&
                      _showDetectionFrame &&
                      _detectionBox != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PackageDetectionPainter(
                          detectionBox: _detectionBox!,
                          isDetected: _packageInFrame,
                        ),
                      ),
                    ),
                  // Barcode scanning frame for Step 2
                  if (_currentStep == 2 && !_barcodeVerified)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 300,
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Scanning for Barcode...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      backgroundColor: Colors.black54,
                                    ),
                                  ),
                                  if (_referenceWaybillId != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Looking for: $_referenceWaybillId',
                                      style: const TextStyle(
                                        color: Colors.yellowAccent,
                                        fontSize: 12,
                                        backgroundColor: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Position barcode within frame',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Success indicator for Step 2 when barcode verified
                  if (_currentStep == 2 && _barcodeVerified)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 64,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Barcode Verified!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 64,
                      color: const Color(0xFF4285F4),
                      alignment: Alignment.center,
                      child: const Text(
                        'Scan Package',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.only(bottom: 32, top: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            step['title']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF212121),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (step['desc'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              step['desc']!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF757575),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                          if (step['progress'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              step['progress']!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF757575),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              width: double.infinity,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(0xFFB9F6CA),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Color(0xFF00C853),
                                  width: 2,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Processing 100%',
                                  style: TextStyle(
                                    color: Color(0xFF00C853),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Skip button for Step 2 if barcode won't scan
                          if (_currentStep == 2 && !_barcodeVerified)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    debugPrint(
                                      '⏭️ Skipping barcode verification',
                                    );
                                    setState(() {
                                      _barcodeVerified = true;
                                      _currentStep = 3;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Skip Barcode (Continue Anyway)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _currentStep = 0;
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFBDBDBD),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Color(0xFF757575),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // Step 6: Success Screen
            if (_currentStep == 6) {
              return Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 64,
                              color: Colors.green,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Success!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'VERIFIED DELIVERY',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ChecklistItem(
                                  text: 'Waybill ID Match',
                                  success: true,
                                ),
                                _ChecklistItem(
                                  text: 'Package Match',
                                  success: true,
                                ),
                                _ChecklistItem(
                                  text: 'Placement Validation',
                                  success: true,
                                ),
                                _ChecklistItem(
                                  text: 'Locker Frame Match',
                                  success: true,
                                ),
                                _ChecklistItem(
                                  text: 'Locker Door Closed',
                                  success: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            // Navigate to ViewTransactionScreen
                            final transactionManager =
                                Provider.of<TransactionManager>(
                                  context,
                                  listen: false,
                                );
                            final transactionData = {
                              'id':
                                  'Transaction ID: ${transactionManager.waybillId ?? "000000"}',
                              'recipient':
                                  'Recipient: ${transactionManager.auditData?.firstName ?? ""} ${transactionManager.auditData?.lastName ?? ""}',
                              'phone':
                                  '${transactionManager.auditData?.phoneNumber ?? "N/A"}',
                              'locker': 'Locker: Smart Locker 001',
                              'status': 'Delivered',
                              'timestamp':
                                  DateTime.now().millisecondsSinceEpoch,
                              'waybill_id': transactionManager.waybillId,
                              'waybill_details':
                                  transactionManager.waybillDetails,
                              'qr_scanned': 'Yes',
                              'package_details': 'Scanned and logged',
                              'verification_status': 'Verified',
                              'color': Colors.green,
                            };
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) => ViewTransactionScreen(
                                  transaction: transactionData,
                                ),
                              ),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Review Transaction',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _currentStep = 0;
                            });
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Return to Home',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Step 8: Failure Screen
            if (_currentStep == 8) {
              return Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Failed',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Make sure to clearly show and verify:',
                              style: TextStyle(fontSize: 13, color: Colors.red),
                            ),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ChecklistItem(
                                  text: 'Waybill ID',
                                  success: false,
                                ),
                                _ChecklistItem(
                                  text: 'Parcel Image',
                                  success: false,
                                ),
                                _ChecklistItem(
                                  text: 'Placement Validation',
                                  success: false,
                                ),
                                _ChecklistItem(
                                  text: 'Locker Frame',
                                  success: false,
                                ),
                                _ChecklistItem(
                                  text: 'Locker Door Closed',
                                  success: false,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _currentStep = 1;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Try Again',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            // TODO: Contact Support
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Contact Support',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Default fallback
            return const Center(child: Text('Unknown step'));
          },
        ),
      ),
    );
  }
}

// Checklist item widget for success/failure screens
class _ChecklistItem extends StatelessWidget {
  final String text;
  final bool success;
  const _ChecklistItem({required this.text, required this.success});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: success ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            success ? Icons.check_circle : Icons.cancel,
            color: success ? Colors.green : Colors.red,
            size: 18,
          ),
        ],
      ),
    );
  }
}

// Package Detection Painter for Step 2
class PackageDetectionPainter extends CustomPainter {
  final Rect detectionBox;
  final bool isDetected;

  PackageDetectionPainter({
    required this.detectionBox,
    required this.isDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDetected ? Colors.green : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final fillPaint = Paint()
      ..color = isDetected ? Colors.green.withOpacity(0.1) : Colors.transparent
      ..style = PaintingStyle.fill;

    // Draw filled rectangle if detected
    if (isDetected) {
      canvas.drawRect(detectionBox, fillPaint);
    }

    // Draw border
    canvas.drawRect(detectionBox, paint);

    // Draw corner brackets
    const double cornerLength = 40.0;

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

    // Draw instruction text
    if (!isDetected) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'Position package within frame',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: Colors.black,
                offset: Offset(2, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          detectionBox.center.dx - textPainter.width / 2,
          detectionBox.top - 40,
        ),
      );
    } else {
      // Show "Package Detected" text
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '✓ Package Detected',
          style: TextStyle(
            color: Colors.green,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: Colors.black,
                offset: Offset(2, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          detectionBox.center.dx - textPainter.width / 2,
          detectionBox.top - 40,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(PackageDetectionPainter oldDelegate) {
    return oldDelegate.detectionBox != detectionBox ||
        oldDelegate.isDetected != isDetected;
  }
}
