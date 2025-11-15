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
  int _scanStep = 0; // 0: initial, 1: waybill id, 2: waybill details, 3: package, 4: success, 5: error
  Uint8List? _imageBytes;
  String? _waybillId;
  String? _waybillDetails;
  String? _errorMessage;

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
          ResolutionPreset.max, // Set to max for best quality
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
      // Step 1: Take the photo
      final XFile image = await _cameraController!.takePicture();
      _imageBytes = await File(image.path).readAsBytes();

      // Step 1: Extract barcode ID
      final ocrResult = await TFLiteProcessor.extractBarcodeIdAndOcr(image);
      _waybillId = ocrResult['waybillId'] ?? '';
      setState(() {
        _scanStep = 1;
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // Step 2: Extract waybill details
      _waybillDetails = ocrResult['waybillDetails'] ?? '';
      setState(() {
        _scanStep = 2;
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // Step 3: Generate embedding and log transaction (package)
      final embedding = await TFLiteProcessor.generateEmbedding(_imageBytes!);
      final transactionManager = Provider.of<TransactionManager>(
        context,
        listen: false,
      );
      if (transactionManager.auditData == null) {
        throw Exception(
          'Missing recipient information. Please go back and enter details.',
        );
      }
      try {
        await transactionManager.logTransactionData(
          lockerId: widget.lockerId ?? 'UNKNOWN_LOCKER',
          waybillId: _waybillId ?? '',
          waybillDetails: _waybillDetails ?? '',
          embedding: embedding,
        );
        setState(() {
          _scanStep = 3;
        });
        await Future.delayed(const Duration(milliseconds: 800));

        // Step 4: Success
        setState(() {
          _scanStep = 4;
        });
      } catch (e) {
        debugPrint('Error logging transaction: $e');
        setState(() {
          _errorMessage = e.toString();
          _scanStep = 5;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error capturing and logging: $e');
      setState(() {
        _errorMessage = e.toString();
        _scanStep = 5;
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera/Image preview fills screen below header
            Positioned.fill(
              top: 0,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    width: double.infinity,
                    color: const Color(0xFF4285F4),
                    child: Text(
                      _scanStep == 4
                          ? 'Scan Successful'
                          : _scanStep == 5
                              ? 'Scan Failed'
                              : 'Scan Package',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildStepContent(),
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

  Widget _buildStepContent() {
    // Step data for Figma-like flow
    final List<Map<String, String>> stepData = [
      {
        'title': 'Position the waybill QR/barcode. Ensure the view is clear.',
        'button': 'Capture & Log Waybill ID',
      },
      {
        'title': 'Scan to Log the Waybill ID',
        'desc': 'Collected Data: Waybill ID',
        'progress': '1/3',
      },
      {
        'title': 'Scan to Log the Waybill Details',
        'desc': 'Collected Data: Waybill Text Details',
        'progress': '2/3',
      },
      {
        'title': 'Scan to Log the Package',
        'desc': 'Collected Data: Package Image & Embedding',
        'progress': '3/3',
      },
    ];

    if (_scanStep == 0) {
      return Stack(
        children: [
          Positioned.fill(
            child: _isCameraInitialized && _cameraController != null
                ? CameraPreview(_cameraController!)
                : const Center(child: CircularProgressIndicator()),
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
                    stepData[0]['title']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF757575), fontSize: 14, fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _captureAndLog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                            : Text(
                                stepData[0]['button']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _scanStep = 0;
                            _isProcessing = false;
                            _imageBytes = null;
                            _waybillId = null;
                            _waybillDetails = null;
                            _errorMessage = null;
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

    if (_scanStep >= 1 && _scanStep <= 3) {
      final step = stepData[_scanStep];
      return Stack(
        children: [
          Positioned.fill(
            child: _imageBytes != null
                ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                : const Center(child: CircularProgressIndicator()),
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
                            _scanStep = 0;
                            _isProcessing = false;
                            _imageBytes = null;
                            _waybillId = null;
                            _waybillDetails = null;
                            _errorMessage = null;
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
    } else if (_scanStep == 4) {
      // Step 4: Scan successful
      return Column(
        children: [
          const SizedBox(height: 32),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, size: 64, color: Colors.green),
                const SizedBox(height: 8),
                const Text(
                  'Scan Successful',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Waybill ID\n2. Waybill Details\n3. Package',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LiveScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Proceed to Live Detection',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      );
    } else if (_scanStep == 5) {
      // Step 5: Scan failed
      return Column(
        children: [
          const SizedBox(height: 32),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 8),
                const Text(
                  'Package Scan Failed',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'Unknown error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Make sure to clearly show:\n1. Waybill ID\n2.Waybill Details \n3. Parcel Image and Embedding',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _scanStep = 0;
                        _errorMessage = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // TODO: Implement support contact
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Contact Support',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}


