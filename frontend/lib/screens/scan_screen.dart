import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import '../services/tflite_processor.dart';
import '../services/transaction_manager.dart';
import 'live_screen.dart';

class ScanScreen extends StatefulWidget {
  final String? lockerId;

  const ScanScreen({super.key, this.lockerId});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    // Show pre-scan guide once when the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPreScanGuide(context);
    });
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
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureAndLog() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      debugPrint('📦 Starting parcel scan with real camera data...');

      // STEP 1: Capture high-quality image
      final XFile image = await _cameraController!.takePicture();
      debugPrint('📸 Image captured: ${image.path}');

      // STEP 2: Extract waybill data using real OCR
      final ocrResult = await TFLiteProcessor.extractBarcodeIdAndOcr(image);
      final waybillId = ocrResult['waybillId'] ?? '';
      final waybillDetails = ocrResult['waybillDetails'] ?? '';

      debugPrint('📄 Waybill ID: $waybillId');
      debugPrint('📝 Details: $waybillDetails');

      // STEP 3: Generate embedding from captured image
      final Uint8List imageBytes = await File(image.path).readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      debugPrint('🧠 Embedding generated: ${embedding.length} dimensions');

      // STEP 4: Validate and log transaction with real data
      if (mounted) {
        final transactionManager = Provider.of<TransactionManager>(
          context,
          listen: false,
        );

        // Validate data completeness before logging
        if (transactionManager.auditData == null) {
          throw Exception(
            'Missing recipient information. Please go back and enter details.',
          );
        }

        debugPrint('✅ All data validated. Logging transaction...');

        // STEP 5: Log complete transaction with real data
        await transactionManager.logTransactionData(
          lockerId: widget.lockerId ?? 'UNKNOWN_LOCKER',
          waybillId: waybillId,
          waybillDetails: waybillDetails,
          embedding: embedding,
        );

        // STEP 6: Store for live verification
        transactionManager.setStoredData(
          waybillId: waybillId,
          waybillDetails: waybillDetails,
          embedding: embedding,
        );

        debugPrint('📊 Final Transaction Summary:');
        final summary = transactionManager.getTransactionSummary();
        summary.forEach((key, value) => debugPrint('  $key: $value'));
        debugPrint('💾 Data stored for live verification');

        // STEP 7: Navigate to live verification
        _showScanSuccessDialog();
      }
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showScanSuccessDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 8),
                  Text(
                    'Package Scanned Successfully',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Package scanned and verified. You may capture a photo for placement evidence.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LiveScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                child: Text('Proceed to Live Detection'),
              ),
            ),
          ],
        ),
      ),
    );
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
                'Scan Package',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Scanning frame
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _isCameraInitialized && _cameraController != null
                      ? CameraPreview(_cameraController!)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Instruction text
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Position the entire package, waybill, and QR/barcode. Ensure the view is clear.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
            const Spacer(),

            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _captureAndLog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
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
                            'Capture & Log Package',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
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
                        fontWeight: FontWeight.w500,
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

  void _showPreScanGuide(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    height: 220,
                    width: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/guide.png',
                        fit: BoxFit
                            .contain, // show entire image without cropping
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '1. Center the PACKAGE',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '2. Ensure WAYBILL & QR/BARCODE are FLAT & FACING FRONT',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '3. Check for CLEAR, Bright LIGHTING',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Got it! Start Scanning'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).maybePop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
