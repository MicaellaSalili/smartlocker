import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async';
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';
import 'view_transaction_screen.dart';
import 'home_screen.dart';
import 'input_details_screen.dart';

  int _currentStep = 0; // 0: Guide, 1: Live Detection, 2-6: Scan Steps, 7: Success, 8: Failure
  String _stepStatus = '';
  int _scanProgress = 1;
  int _scanTotal = 5;
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

  // Frame processing retry/backoff state
  int _frameProcessFailureCount = 0;
  Timer? _frameProcessBackoffTimer;

  static const int requiredConsecutiveFrames = 5;
  static const double similarityThreshold = 0.85;
  static const double positionConfidenceThreshold = 0.80;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

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

    // Start image stream for live verification
    _controller!.startImageStream((CameraImage image) async {
      if (!_isVerifying || _isProcessingFrame) {
        return;
      }

      _isProcessingFrame = true;
      await _processFrame(image);
      _isProcessingFrame = false;
    });
  }

  /// Process a single camera frame for verification
  Future<void> _processFrame(CameraImage frame) async {
    try {
      // a) Call TFLiteProcessor.runLiveVerification
      final liveData = await TFLiteProcessor.runLiveVerification(frame);

      final List<double> liveEmbedding = List<double>.from(
        liveData['liveEmbedding'],
      );
      final String liveWaybillDetails = liveData['liveWaybillDetails'];
      final List<dynamic> boundingBoxes = liveData['boundingBoxes'];
      final bool lockerDetected = liveData['lockerDetected'] as bool;

      // b) Calculate Cosine Similarity between live and reference embeddings
      final similarity = _calculateCosineSimilarity(
        liveEmbedding,
        _referenceEmbedding!,
      );

      // c) Full Match Check - ALL FIVE criteria must be true
      final bool vectorMatch = similarity >= similarityThreshold;
      final bool textMatch = _checkTextMatch(
        liveWaybillDetails,
        _referenceWaybillDetails ?? '',
      );
      final bool idMatch = _checkIdMatch(
        liveWaybillDetails,
        _referenceWaybillId ?? '',
      );
      final bool positionCheck = _checkPositionQuality(boundingBoxes);
      final bool lockerFrameCheck = lockerDetected;

      debugPrint(
        'Verification scores - Similarity: ${similarity.toStringAsFixed(3)}, '
        'Vector: $vectorMatch, Text: $textMatch, ID: $idMatch, Position: $positionCheck, Locker: $lockerFrameCheck',
      );

      // Check if all 5 conditions are met
      final bool allChecksPassed =
          vectorMatch &&
          textMatch &&
          idMatch &&
          positionCheck &&
          lockerFrameCheck;

      // Handle verification during countdown - detect mismatch
      if (_isVerificationStarted && !allChecksPassed) {
        // Mismatch detected during countdown - parcel was removed
        debugPrint(
          'Mismatch detected during countdown! Resetting transaction.',
        );
        await _resetTransaction();
        return;
      }

      // Normal verification flow
      if (allChecksPassed) {
        _consecutiveSuccessFrames++;

        if (mounted) {
          setState(() {
            _verificationStatus =
                'Match detected! ($_consecutiveSuccessFrames/$requiredConsecutiveFrames)';
          });
        }

        // Advance step after required consecutive frames
        if (_consecutiveSuccessFrames >= requiredConsecutiveFrames && !_isVerificationStarted) {
          if (mounted) {
            setState(() {
              if (_currentStep < 7) {
                _currentStep++;
                _consecutiveSuccessFrames = 0;
              }
              // Only start countdown at last step
              if (_currentStep == 7) {
                _startCloseDoorCountdown();
              }
            });
          }
        }
      } else {
        // Reset counter if any check fails (only if countdown hasn't started)
        if (!_isVerificationStarted) {
          _consecutiveSuccessFrames = 0;

          if (mounted) {
            setState(() {
              String status =
                  'Verifying... Similarity: ${(similarity * 100).toStringAsFixed(1)}%';
              if (!lockerFrameCheck) {
                status = 'Position package in locker frame';
              }
              _verificationStatus = status;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing frame: $e');
      if (!_isVerificationStarted) {
        _frameProcessFailureCount++;
        _consecutiveSuccessFrames = 0;
        if (_frameProcessFailureCount >= 3) {
          await _handleFatalProcessingFailure();
          return;
        } else {
          _startFrameBackoff();
          return;
        }
      }
    }
  }

  /// Start exponential backoff after frame processing failure
  void _startFrameBackoff() {
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    int delayMs = 1000 * (1 << (_frameProcessFailureCount - 1)); // 1s, 2s, 4s
    debugPrint('Frame processing backoff: ${delayMs ~/ 1000}s');
    _frameProcessBackoffTimer?.cancel();
    _frameProcessBackoffTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_controller != null && !_controller!.value.isStreamingImages) {
        _controller!.startImageStream((CameraImage image) async {
          if (!_isVerifying || _isProcessingFrame) return;
          _isProcessingFrame = true;
          await _processFrame(image);
          _isProcessingFrame = false;
        });
      }
      _frameProcessBackoffTimer = null;
      _frameProcessFailureCount = 0;
    });
  }

  /// Handle fatal frame processing failure (after 3 consecutive failures)
  Future<void> _handleFatalProcessingFailure() async {
    debugPrint('Fatal frame processing failure. Rolling back transaction.');
    _stopLiveVerification();
    setState(() {
      _currentStep = 8;
      _verificationStatus = 'Frame processing failed. Please try again.';
    });
    await _resetTransaction();
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
        // Countdown finished, finalize transaction and navigate to success
        timer.cancel();
        _closeDoorTimer = null;
        _stopAndFinalize(true);
      }
    });
  }

  /// Reset transaction on failure or mismatch during countdown
  Future<void> _resetTransaction() async {
    debugPrint('Resetting transaction due to failure/mismatch');

    // a) Cancel close door timer if active
    _closeDoorTimer?.cancel();
    _closeDoorTimer = null;

    // Stop verification
    _stopLiveVerification();

    final transactionManager = Provider.of<TransactionManager>(
      context,
      listen: false,
    );

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    // b) Call TransactionManager.deleteTransaction() for database rollback
    final deleted = await transactionManager.deleteTransaction();

    // Close loading indicator
    if (mounted) {
      Navigator.of(context).pop();
    }

    if (deleted && mounted) {
      // Show failure message
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Verification Failed'),
          content: const Text(
            'Package verification failed or was interrupted. Transaction has been cancelled. Please start again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // c) Navigate back to Input Details Screen to restart
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const InputDetailsScreen(lockerId: null),
          ),
          (route) => false,
        );
      }
    } else if (mounted) {
      // Show error if deletion failed
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Error'),
          content: const Text('Failed to reset transaction. Please try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
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

  /// Check if live waybill text matches reference text using robust token-based comparison
  bool _checkTextMatch(String liveText, String referenceText) {
    // Use the robust text comparison utility from TransactionManager
    return TransactionManager.isTextContentMatch(liveText, referenceText);
  }

  /// Check if live text contains the reference waybill ID
  bool _checkIdMatch(String liveText, String referenceId) {
    if (referenceId.isEmpty) return true; // Skip check if no reference

    // Normalize both texts for comparison
    final liveNormalized = liveText.toLowerCase().trim();
    final idNormalized = referenceId.toLowerCase().trim();

    return liveNormalized.contains(idNormalized);
  }

  /// Check if detected objects have good positioning and confidence
  bool _checkPositionQuality(List<dynamic> boundingBoxes) {
    if (boundingBoxes.isEmpty) return false;

    // Check if we have both package and waybill detected
    bool hasPackage = false;
    bool hasWaybill = false;

    for (var box in boundingBoxes) {
      final confidence = box['confidence'] as double;
      final className = box['class'] as String;

      if (confidence >= positionConfidenceThreshold) {
        if (className == 'package') hasPackage = true;
        if (className == 'waybill') hasWaybill = true;
      }
    }

    return hasPackage && hasWaybill;
  }

  /// Stop verification and finalize the transaction
  /// Called when countdown hits zero (isSuccess = true)
  Future<void> _stopAndFinalize(bool isSuccess) async {
    debugPrint('Finalizing transaction with success: $isSuccess');

    _stopLiveVerification();
    _closeDoorTimer?.cancel();
    _closeDoorTimer = null;

    if (isSuccess && mounted) {
      final transactionManager = Provider.of<TransactionManager>(
        context,
        listen: false,
      );

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Call finalizeTransaction to update status to VERIFIED_SUCCESS
      final success = await transactionManager.finalizeTransaction();

      // Close loading indicator
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (success && mounted) {
        // Show success dialog and navigate to delivery successful screen
        _showSuccessDialog();
      } else if (mounted) {
        // Show error if finalization failed
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text('Error'),
            content: const Text(
              'Failed to finalize transaction. Please contact support.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                    (route) => false,
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Handle "Finalize Deposit" button press
  Future<void> _handleFinalizeDeposit() async {
    _stopLiveVerification();

    final transactionManager = Provider.of<TransactionManager>(
      context,
      listen: false,
    );

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    // Call finalizeTransaction
    final success = await transactionManager.finalizeTransaction();

    // Close loading indicator
    if (mounted) {
      Navigator.of(context).pop();
    }

    if (success && mounted) {
      _showSuccessDialog();
    } else if (mounted) {
      // Show error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Error'),
          content: const Text(
            'Failed to finalize transaction. Please try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Handle "Cancel Transaction" button press
  Future<void> _handleCancelTransaction() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cancel Transaction?'),
        content: const Text(
          'Are you sure you want to cancel this transaction? This will delete all transaction data and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, Keep Transaction'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _stopLiveVerification();

    final transactionManager = Provider.of<TransactionManager>(
      context,
      listen: false,
    );

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    // Call deleteTransaction
    final deleted = await transactionManager.deleteTransaction();

    // Close loading indicator
    if (mounted) {
      Navigator.of(context).pop();
    }

    if (deleted && mounted) {
      // Show cancellation success and navigate to HomeScreen
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Transaction Cancelled'),
          content: const Text(
            'The transaction has been cancelled and all data has been deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else if (mounted) {
      // Show error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('Error'),
          content: const Text(
            'Failed to cancel transaction. Please try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showSuccessDialog() async {
    // Immediately send lock command to ESP32
    await _sendLockCommand();

    // Show success dialog
    _showFinalSuccessDialog();
  }

  Future<void> _sendLockCommand() async {
    final transactionManager = Provider.of<TransactionManager>(
      context,
      listen: false,
    );
    final success = await transactionManager.lockLocker();

    if (success) {
      debugPrint('✅ Lock command sent to ESP32 after successful verification');
    } else {
      debugPrint('⚠️  Failed to send lock command to ESP32');
    }
  }

  void _showFinalSuccessDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    'Success!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.green,
                    ),
                  ),
                  SizedBox(height: 12),
                  // Removed success message
                  SizedBox(height: 8),
                  Text(
                    'Verification complete. Door has been locked automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF2C3E50)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Get transaction data before navigation
                final transactionManager = Provider.of<TransactionManager>(
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
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'waybill_id': transactionManager.waybillId,
                  'waybill_details': transactionManager.waybillDetails,
                  'qr_scanned': 'Yes',
                  'package_details': 'Scanned and logged',
                  'verification_status': 'Verified',
                  'color': Colors.green,
                };

                // Close dialog first
                Navigator.of(dialogContext).pop();

                // Navigate to ViewTransactionScreen and replace entire stack
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) =>
                        ViewTransactionScreen(transaction: transactionData),
                  ),
                  (route) => false, // Remove all previous routes
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 32,
                ),
                minimumSize: const Size(double.infinity, 50),
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
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false,
                );
              },
              child: const Text(
                'Return to Home',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _stopLiveVerification() {
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _frameProcessBackoffTimer?.cancel();
    _frameProcessBackoffTimer = null;
    _frameProcessFailureCount = 0;
    setState(() {
      _isVerifying = false;
    });
  }

  @override
  void dispose() {
    _closeDoorTimer?.cancel();
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
                            child: const Icon(Icons.inventory_2, size: 64, color: Colors.brown),
                          ),
                          const SizedBox(height: 18),
                          // Guide instructions
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('1. Center the PACKAGE', style: TextStyle(fontSize: 16)),
                              SizedBox(height: 6),
                              Text('2. Ensure WAYBILL & QR/BARCODE are FLAT & FACING FRONT', style: TextStyle(fontSize: 16)),
                              SizedBox(height: 6),
                              Text('3. Check for CLEAR, Bright LIGHTING', style: TextStyle(fontSize: 16)),
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Colors.grey, width: 2),
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
                            child: const Center(child: CircularProgressIndicator()),
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
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
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
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4285F4),
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Colors.grey, width: 2),
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
                  'progress': '1/6',
                },
                {
                  'title': 'Scan to Detect and Verify the Waybill Info',
                  'desc': 'Collected Data: Waybill Text Details',
                  'progress': '2/6',
                },
                {
                  'title': 'Scan to Detect and Verify the Package',
                  'desc': 'Collected Data: Package',
                  'progress': '3/6',
                },
                {
                  'title': 'Maintain Live Detection while placing',
                  'desc': 'Collected Data: Placement Validation',
                  'progress': '4/6',
                },
                {
                  'title': 'Scan and Detect to Verify Locker',
                  'desc': 'Collected Data: Locker Frame',
                  'progress': '5/6',
                },
                {
                  'title': 'Scan and Detect to Verify Locker',
                  'desc': 'Collected Data: Locker Door Closed',
                  'progress': '6/6',
                },
              ];
              int stepIndex = (_currentStep - 2).clamp(0, scanSteps.length - 1);
              final step = scanSteps[stepIndex];

              // Door Closing Popup for step 6
              if (_currentStep == 7 && _showDoorCountdown) {
                // Show modal popup overlay
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _isCameraInitialized && _controller != null
                          ? CameraPreview(_controller!)
                          : Container(
                              color: Colors.black,
                              child: const Center(child: CircularProgressIndicator()),
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
                            const Icon(Icons.door_front_door, size: 64, color: Colors.green),
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
                              style: TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (_currentStep == 7 && !_showDoorCountdown) {
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
                              const Icon(Icons.check_circle, size: 64, color: Colors.green),
                              const SizedBox(height: 8),
                              const Text('Success!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green)),
                              const SizedBox(height: 8),
                              const Text('VERIFIED DELIVERY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  _ChecklistItem(text: 'Package Match', success: true),
                                  _ChecklistItem(text: 'Waybill ID Match', success: true),
                                  _ChecklistItem(text: 'Waybill Text Match', success: true),
                                  _ChecklistItem(text: 'Placement Validation', success: true),
                                  _ChecklistItem(text: 'Locker Frame Match', success: true),
                                  _ChecklistItem(text: 'Locker Door Closed', success: true),
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
                              final transactionManager = Provider.of<TransactionManager>(
                                context,
                                listen: false,
                              );
                              final transactionData = {
                                'id': 'Transaction ID: ${transactionManager.waybillId ?? "000000"}',
                                'recipient': 'Recipient: ${transactionManager.auditData?.firstName ?? ""} ${transactionManager.auditData?.lastName ?? ""}',
                                'phone': '${transactionManager.auditData?.phoneNumber ?? "N/A"}',
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Review Transaction', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
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
                            child: const Text('Return to Home', style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w500)),
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
                  Positioned.fill(
                    child: _isCameraInitialized && _controller != null
                        ? CameraPreview(_controller!)
                        : Container(
                            color: Colors.black,
                            child: const Center(child: CircularProgressIndicator()),
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
                            style: const TextStyle(color: Color(0xFF212121), fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          if (step['desc'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              step['desc']!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF757575), fontSize: 13, fontWeight: FontWeight.w400),
                            ),
                          ],
                          if (step['progress'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              step['progress']!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF757575), fontSize: 13, fontWeight: FontWeight.w400),
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
                                border: Border.all(color: Color(0xFF00C853), width: 2),
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
                                  side: const BorderSide(color: Color(0xFFBDBDBD)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
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

            // Step 7: Success Screen
            if (_currentStep == 7) {
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
                            const Icon(Icons.check_circle, size: 64, color: Colors.green),
                            const SizedBox(height: 8),
                            const Text('Success!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green)),
                            const SizedBox(height: 8),
                            const Text('VERIFIED DELIVERY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ChecklistItem(text: 'Package Match', success: true),
                                _ChecklistItem(text: 'Waybill ID Match', success: true),
                                _ChecklistItem(text: 'Waybill Text Match', success: true),
                                _ChecklistItem(text: 'Placement Validation', success: true),
                                _ChecklistItem(text: 'Locker Frame Match', success: true),
                                _ChecklistItem(text: 'Locker Door Closed', success: true),
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
                            final transactionManager = Provider.of<TransactionManager>(
                              context,
                              listen: false,
                            );
                            final transactionData = {
                              'id': 'Transaction ID: ${transactionManager.waybillId ?? "000000"}',
                              'recipient': 'Recipient: ${transactionManager.auditData?.firstName ?? ""} ${transactionManager.auditData?.lastName ?? ""}',
                              'phone': '${transactionManager.auditData?.phoneNumber ?? "N/A"}',
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Review Transaction', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
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
                          child: const Text('Return to Home', style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w500)),
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
                            const Icon(Icons.error, size: 64, color: Colors.red),
                            const SizedBox(height: 8),
                            const Text('Failed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.red)),
                            const SizedBox(height: 8),
                            const Text('Make sure to clearly show and verify:', style: TextStyle(fontSize: 13, color: Colors.red)),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ChecklistItem(text: 'Parcel Image', success: false),
                                _ChecklistItem(text: 'Waybill ID', success: false),
                                _ChecklistItem(text: 'Waybill Details', success: false),
                                _ChecklistItem(text: 'Placement Validation', success: false),
                                _ChecklistItem(text: 'Locker Frame', success: false),
                                _ChecklistItem(text: 'Locker Door Closed', success: false),
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
                          child: const Text('Try Again', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
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
                          child: const Text('Contact Support', style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w500)),
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
