import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async';
import '../services/transaction_manager.dart';
import '../services/tflite_processor.dart';
import 'view_transaction_screen.dart';
import 'home_screen.dart';
import 'input_details_screen.dart';

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
          ResolutionPreset.medium,
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

        // If successful for 5 consecutive frames AND not yet started countdown
        if (_consecutiveSuccessFrames >= requiredConsecutiveFrames &&
            !_isVerificationStarted) {
          _startCloseDoorCountdown();
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
        _consecutiveSuccessFrames = 0;
      }
    }
  }

  /// Start the close door countdown after successful verification
  void _startCloseDoorCountdown() {
    debugPrint('Starting close door countdown');

    // Set verification started flag
    _isVerificationStarted = true;

    // a) Stop the image stream to pause continuous processing
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }

    // Reset countdown
    _countdown = 3;

    // b) Start countdown timer
    _closeDoorTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _verificationStatus =
              'Correct parcel in locker, ${_countdown}s to close door!';
        });
      }

      if (_countdown > 0) {
        _countdown--;
      } else {
        // c) Countdown reached 0 - finalize transaction
        timer.cancel();
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
      // Show cancellation success and navigate back
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
                  Text(
                    'Package Placed Successfully',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
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
                  'phone': transactionManager.auditData?.phoneNumber ?? "N/A",
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
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF4285F4),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: const Text(
                'Live Detection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Camera/Detection frame
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _isCameraInitialized && _controller != null
                      ? CameraPreview(_controller!)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Verification Status text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _verificationStatus,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isVerifying ? Colors.blue : Colors.grey,
                  fontSize: 14,
                  fontWeight: _isVerifying
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBDEFB)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF1976D2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Position the entire package within the frame. Ensure good lighting and clear visibility of all sides.',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  // Finalize Deposit button
                  ElevatedButton(
                    onPressed: _isVerifying ? null : _handleFinalizeDeposit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isVerifying ? 'Verifying...' : 'Finalize Deposit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Cancel Transaction button
                  OutlinedButton(
                    onPressed: _isVerifying ? null : _handleCancelTransaction,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      side: const BorderSide(color: Colors.red, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel Transaction',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
