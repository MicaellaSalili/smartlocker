import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
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
  String _scannedWaybillId = '';
  String _scannedText = '';

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
      // 1. Take the photo
      debugPrint('\n📸 Capturing image...');
      final XFile image = await _cameraController!.takePicture();
      debugPrint('✅ Image captured: ${image.path}');
      debugPrint('📏 Image size: ${await image.length()} bytes');

      // 2. Call TFLiteProcessor methods
      // Extract barcode ID and OCR details
      debugPrint('🔍 Starting OCR processing...');
      final ocrResult = await TFLiteProcessor.extractBarcodeIdAndOcr(image);

      debugPrint('\n🟡 RAW OCR RESULT FROM PROCESSOR:');
      debugPrint('   Keys in result: ${ocrResult.keys.toList()}');
      debugPrint('   waybillId value: ${ocrResult['waybillId']}');
      debugPrint(
        '   waybillDetails length: ${ocrResult['waybillDetails']?.length ?? 0}',
      );

      final waybillId = ocrResult['waybillId'] ?? '';
      final waybillDetails = ocrResult['waybillDetails'] ?? '';

      debugPrint('\n========== SCAN RESULTS ==========');
      debugPrint('📦 Waybill ID: $waybillId');
      debugPrint('📄 Full Details:\n$waybillDetails');
      debugPrint('==================================\n');

      // Store scanned text for display
      if (mounted) {
        setState(() {
          _scannedWaybillId = waybillId;
          _scannedText = waybillDetails;
        });

        // Show warning if no text was detected
        if (waybillId.contains('[NO_TEXT_DETECTED]') || 
            waybillId.contains('[ERROR') || 
            waybillId.contains('[EMPTY]')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ No text detected! Check:\n• Lighting is bright\n• Waybill is flat and in focus\n• Text is clearly visible',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      // Generate embedding vector
      final Uint8List imageBytes = await File(image.path).readAsBytes();
      final embedding = await TFLiteProcessor.generateEmbedding(imageBytes);

      // 3. Call TransactionManager.logTransactionData
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

        await transactionManager.logTransactionData(
          lockerId: widget.lockerId ?? 'UNKNOWN_LOCKER',
          waybillId: waybillId,
          waybillDetails: waybillDetails,
          embedding: embedding,
        );

        debugPrint('📊 Final Transaction Summary:');
        final summary = transactionManager.getTransactionSummary();
        summary.forEach((key, value) => debugPrint('  $key: $value'));

        // 4. Navigate to success screen (using dialog then LiveScreen)
        _showScanSuccessDialog();
      }
    } catch (e) {
      debugPrint('Error capturing and logging: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            const SizedBox(height: 16),

            // Scanned Text Display
            if (_scannedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border.all(
                      color: const Color(0xFF4285F4),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF4285F4),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Scanned Text:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_scannedWaybillId.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'Waybill ID: ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _scannedWaybillId,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                      ],
                      const Text(
                        'Full Text:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: SingleChildScrollView(
                          child: Text(
                            _scannedText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
