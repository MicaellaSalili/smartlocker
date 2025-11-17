import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:io';
import '../services/tflite_processor.dart';
import '../services/transaction_manager.dart';
import '../services/text_recognition_service.dart';
import 'live_screen.dart';

class ScanScreen extends StatefulWidget {
  final String? lockerId;

  const ScanScreen({super.key, this.lockerId});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // Step tracking: 0=guide, 1=barcode, 2=text, 3=package, 4=success
  int _currentStep = 0;

  // Mobile scanner for barcode/QR
  MobileScannerController? _barcodeController;

  // Camera for text and package capture
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // Processing flags
  bool _isProcessing = false;
  bool _barcodeDetected = false;

  // Captured data
  String? _scannedBarcode;
  String? _extractedText;
  Uint8List? _packageImage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeBarcodeScanner();
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

  @override
  void dispose() {
    _barcodeController?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // Step 0: Show guide
  Widget _buildGuideStep() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              color: const Color(0xFF4285F4),
              child: const Text(
                'Scan Package - 3 Steps',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner,
                      size: 100,
                      color: Color(0xFF4285F4),
                    ),
                    const SizedBox(height: 32),

                    // Step indicators
                    _buildStepIndicator(
                      1,
                      'Scan Barcode/QR',
                      'Position barcode within frame',
                      true,
                    ),
                    const SizedBox(height: 16),
                    _buildStepIndicator(
                      2,
                      'Scan Waybill Text',
                      'Capture waybill details',
                      false,
                    ),
                    const SizedBox(height: 16),
                    _buildStepIndicator(
                      3,
                      'Capture Package',
                      'Take photo of entire package',
                      false,
                    ),

                    const Spacer(),

                    // Start button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _currentStep = 1; // Start with barcode scan
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
                          'Start Scanning',
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
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.grey),
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
        ),
      ),
    );
  }

  Widget _buildStepIndicator(
    int stepNumber,
    String title,
    String description,
    bool isActive,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE3F2FD) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? const Color(0xFF4285F4) : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isActive ? const Color(0xFF4285F4) : Colors.grey,
            radius: 20,
            child: Text(
              '$stepNumber',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isActive ? const Color(0xFF4285F4) : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 1: Barcode/QR scanner
  Widget _buildBarcodeStep() {
    return Stack(
      children: [
        // Barcode scanner
        MobileScanner(
          controller: _barcodeController,
          onDetect: (capture) {
            if (_barcodeDetected || _isProcessing) return;

            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isEmpty) return;

            final barcode = barcodes.first;
            if (barcode.rawValue == null) return;

            setState(() {
              _barcodeDetected = true;
              _isProcessing = true;
              _scannedBarcode = barcode.rawValue;
            });

            debugPrint(
              '============================================================',
            );
            debugPrint('📦 STEP 1 - BARCODE SCANNED:');
            debugPrint(
              '============================================================',
            );
            debugPrint('✅ Barcode: $_scannedBarcode');
            debugPrint('✅ Format: ${barcode.format.name}');
            debugPrint(
              '============================================================',
            );

            // Auto advance after 1 second
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                _barcodeController?.stop();
                _initializeCamera(); // Prepare camera for next steps
                setState(() {
                  _currentStep = 2;
                  _isProcessing = false;
                });
              }
            });
          },
        ),

        // Scanning frame overlay
        Center(
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(
                color: _barcodeDetected ? Colors.green : Colors.white,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Overlay with instructions
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black54,
            child: SafeArea(
              child: Column(
                children: [
                  const Text(
                    'Step 1 of 3: Scan Barcode/QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Position the barcode or QR code within the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  if (_barcodeDetected) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Barcode Detected: $_scannedBarcode',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Cancel button
        Positioned(
          bottom: 32,
          left: 32,
          right: 32,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Colors.grey),
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
    );
  }

  // Step 2: Text extraction from waybill
  Widget _buildTextExtractionStep() {
    return Stack(
      children: [
        // Camera preview
        _isCameraInitialized && _cameraController != null
            ? CameraPreview(_cameraController!)
            : const Center(child: CircularProgressIndicator()),

        // Scanning frame overlay
        Center(
          child: Container(
            width: 320,
            height: 400,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black54,
            child: SafeArea(
              child: Column(
                children: [
                  const Text(
                    'Step 2 of 3: Scan Waybill Text',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Position the waybill to capture Order ID, Buyer Name, and other details',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  if (_scannedBarcode != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '✓ Barcode: $_scannedBarcode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Bottom buttons
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _captureWaybillText,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Capture Waybill Text',
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
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.grey),
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

  Future<void> _captureWaybillText() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();

      // Extract text using Google ML Kit
      final textService = TextRecognitionService();
      final ocrResult = await textService.processImageFile(image);

      final extractedText = ocrResult['waybillDetails'] ?? '';

      debugPrint(
        '============================================================',
      );
      debugPrint('📦 STEP 2 - TEXT EXTRACTED:');
      debugPrint(
        '============================================================',
      );
      debugPrint('✅ Order ID: ${ocrResult['orderId']}');
      debugPrint('✅ Buyer Name: ${ocrResult['buyerName']}');
      debugPrint('✅ Tracking: ${ocrResult['trackingNumber']}');
      debugPrint('✅ Full Details:\n$extractedText');
      debugPrint(
        '============================================================',
      );

      setState(() {
        _extractedText = extractedText; // Store in setState for UI update
        _currentStep = 3; // Move to package capture
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('❌ Error extracting text: $e');
      setState(() {
        _errorMessage = 'Failed to extract text: $e';
        _isProcessing = false;
      });
    }
  }

  // Step 3: Package image capture
  Widget _buildPackageCaptureStep() {
    return Stack(
      children: [
        // Camera preview
        _isCameraInitialized && _cameraController != null
            ? CameraPreview(_cameraController!)
            : const Center(child: CircularProgressIndicator()),

        // Scanning frame overlay
        Center(
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black54,
            child: SafeArea(
              child: Column(
                children: [
                  const Text(
                    'Step 3 of 3: Capture Package',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Capture the entire package including waybill',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '✓ Barcode',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '✓ Text',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom buttons
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _capturePackageImage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Capture Package Image',
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
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.grey),
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

  Future<void> _capturePackageImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _cameraController!.takePicture();
      _packageImage = await File(image.path).readAsBytes();

      // Generate embedding
      final embedding = await TFLiteProcessor.generateEmbedding(_packageImage!);

      debugPrint(
        '============================================================',
      );
      debugPrint('📦 STEP 3 - PACKAGE CAPTURED:');
      debugPrint(
        '============================================================',
      );
      debugPrint('✅ Image size: ${_packageImage!.length} bytes');
      debugPrint('✅ Embedding length: ${embedding.length}');
      debugPrint(
        '============================================================',
      );

      // Log transaction
      final transactionManager = Provider.of<TransactionManager>(
        context,
        listen: false,
      );

      if (transactionManager.auditData == null) {
        debugPrint('⚠️ No recipient info, using test data');
        transactionManager.updateAuditData(
          firstName: 'Test',
          lastName: 'User',
          phoneNumber: '0000000000',
        );
      }

      await transactionManager.logTransactionData(
        lockerId: widget.lockerId ?? 'UNKNOWN_LOCKER',
        waybillId: _scannedBarcode ?? 'NO_BARCODE',
        waybillDetails: _extractedText ?? 'NO_TEXT',
        embedding: embedding,
      );

      setState(() {
        _currentStep = 4; // Show success
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint('❌ Error capturing package: $e');
      setState(() {
        _errorMessage = 'Failed to capture package: $e';
        _isProcessing = false;
      });
    }
  }

  // Step 4: Success screen
  Widget _buildSuccessStep() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              color: const Color(0xFF4285F4),
              child: const Text(
                'Scan Complete',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                            size: 80,
                            color: Colors.green,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'All Steps Verified!',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSuccessItem(
                            Icons.qr_code,
                            'Barcode',
                            _scannedBarcode ?? 'N/A',
                          ),
                          const SizedBox(height: 12),
                          _buildSuccessItem(
                            Icons.photo_camera,
                            'Package Image',
                            'Captured',
                          ),
                          const SizedBox(height: 16),
                          // Full extracted text display
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.green.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.text_fields,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Extracted Waybill Text:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  constraints: const BoxConstraints(
                                    maxHeight: 150,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      _extractedText ?? 'No text extracted',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade800,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Proceed button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LiveScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Proceed to Live Detection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Return home button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Return to Home',
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
        ),
      ),
    );
  }

  Widget _buildSuccessItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.green, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Text(
                value,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Icon(Icons.check, color: Colors.green, size: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _currentStep == 0
          ? _buildGuideStep()
          : _currentStep == 1
          ? _buildBarcodeStep()
          : _currentStep == 2
          ? _buildTextExtractionStep()
          : _currentStep == 3
          ? _buildPackageCaptureStep()
          : _buildSuccessStep(),
    );
  }
}
