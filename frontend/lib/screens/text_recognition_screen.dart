import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import '../services/text_recognition_service.dart';

class TextRecognitionScreen extends StatefulWidget {
  const TextRecognitionScreen({super.key});

  @override
  State<TextRecognitionScreen> createState() => _TextRecognitionScreenState();
}

class _TextRecognitionScreenState extends State<TextRecognitionScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _recognizedText = '';
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera initialization failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _captureAndRecognizeText() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _recognizedText = 'Processing...';
    });

    try {
      // Capture image
      final XFile image = await _cameraController!.takePicture();

      // Use the text recognition service for consistent results
      final textRecognitionService = TextRecognitionService();
      final result = await textRecognitionService.processImageFile(image);
      textRecognitionService.dispose();

      // Debug: Print what was actually recognized
      print('\n======= OCR DEBUG =======');
      print('Full Text Recognized:');
      print(result['fullText']);
      print('\nExtracted Data:');
      print('Order ID: ${result['orderId']}');
      print('Waybill ID: ${result['waybillId']}');
      print('Buyer Name: ${result['buyerName']}');
      print('Barcode: ${result['barcode']}');
      print('Tracking: ${result['trackingNumber']}');
      print('Weight: ${result['weight']}');
      print('Quantity: ${result['productQuantity']}');
      print('========================\n');

      // Format J&T Express data
      final StringBuffer displayBuffer = StringBuffer();

      if (result['orderId'] != null &&
          result['orderId'].toString().isNotEmpty) {
        displayBuffer.writeln('📋 Order ID: ${result['orderId']}');
      }
      if (result['trackingNumber'] != null &&
          result['trackingNumber'].toString().isNotEmpty) {
        displayBuffer.writeln('🔢 Tracking: ${result['trackingNumber']}');
      }
      if (result['barcode'] != null &&
          result['barcode'].toString().isNotEmpty) {
        displayBuffer.writeln('📊 Barcode: ${result['barcode']}');
      }
      if (result['buyerName'] != null &&
          result['buyerName'].toString().isNotEmpty) {
        displayBuffer.writeln('👤 Buyer: ${result['buyerName']}');
      }
      if (result['productQuantity'] != null &&
          result['productQuantity'].toString().isNotEmpty) {
        displayBuffer.writeln('📦 Quantity: ${result['productQuantity']}');
      }
      if (result['weight'] != null && result['weight'].toString().isNotEmpty) {
        displayBuffer.writeln('⚖️ Weight: ${result['weight']}');
      }

      displayBuffer.writeln('\n--- Full Text ---');
      displayBuffer.writeln(result['fullText'] ?? '');

      // Clean up temp file
      await File(image.path).delete();

      if (mounted) {
        setState(() {
          _recognizedText = displayBuffer.toString().trim();
          if (_recognizedText.isEmpty) {
            _recognizedText = 'No text detected. Please try again.';
          }
        });
      }
    } catch (e) {
      debugPrint('Error recognizing text: $e');
      if (mounted) {
        setState(() {
          _recognizedText = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _copyToClipboard() {
    if (_recognizedText.isNotEmpty &&
        !_recognizedText.contains('Processing') &&
        !_recognizedText.contains('No text detected')) {
      // You can use the clipboard package or show a dialog
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Text copied to clipboard')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Text Recognition'),
        backgroundColor: const Color(0xFF4285F4),
      ),
      body: Column(
        children: [
          // Camera Preview
          Expanded(
            flex: 3,
            child: _isCameraInitialized
                ? ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    child: CameraPreview(_cameraController!),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),

          // Recognized Text Display
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recognized Text:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_recognizedText.isNotEmpty &&
                          !_recognizedText.contains('Processing') &&
                          !_recognizedText.contains('No text detected'))
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: _copyToClipboard,
                          tooltip: 'Copy text',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _recognizedText.isEmpty
                            ? 'Tap the camera button to scan text'
                            : _recognizedText,
                        style: TextStyle(
                          fontSize: 16,
                          color: _recognizedText.isEmpty
                              ? Colors.grey
                              : Colors.black,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _captureAndRecognizeText,
        backgroundColor: const Color(0xFF4285F4),
        icon: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.camera_alt),
        label: Text(_isProcessing ? 'Processing...' : 'Scan Text'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
