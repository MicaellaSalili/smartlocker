import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/yolo_detector.dart';
import '../services/camera_utils.dart';

class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  // Isolate
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _mainReceivePort;

  // Detections for overlay
  List<Map<String, dynamic>> _detections = [];

  // Throttle
  int _minIntervalMs = 250; // ~4 FPS
  int _lastInferMs = 0;

  // Multi-frame capture
  bool _captureMulti = false;
  final List<Map<String, dynamic>> _multiResults = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _isolate?.kill(priority: Isolate.immediate);
    _mainReceivePort?.close();
    super.dispose();
  }

  Future<void> _init() async {
    _cameras = await availableCameras();
    final cam = _cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    _controller = CameraController(cam, ResolutionPreset.low, enableAudio: false);
    await _controller!.initialize();
    setState(() => _isInitialized = true);

    // Spawn isolate
    _mainReceivePort = ReceivePort();
    _isolate = await Isolate.spawn(yoloIsolateEntry, _mainReceivePort!.sendPort);
    final sp = await _mainReceivePort!.first as SendPort;
    _isolateSendPort = sp;

    // Start image stream
    _controller!.startImageStream(_onCameraImage);
  }

  void _onCameraImage(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastInferMs < _minIntervalMs) return; // throttle
    _lastInferMs = now;

    // Convert to RGB bytes on main isolate (camera image not transferable)
    final rgb = convertYUV420ToRgb(image);

    if (_isolateSendPort == null) return;
    final responsePort = ReceivePort();
    _isolateSendPort!.send(DetectorIsolateMessage(rgb, image.width, image.height, responsePort.sendPort));

    final res = await responsePort.first as List<dynamic>;
    // result is List<Map>
    setState(() {
      _detections = List<Map<String, dynamic>>.from(res.map((e) => Map<String, dynamic>.from(e)));
    });

    if (_captureMulti) {
      _multiResults.addAll(_detections);
      if (_multiResults.length >= 3) {
        _captureMulti = false;
        _showMultiDialog(_multiResults);
        _multiResults.clear();
      }
    }
  }

  void _showMultiDialog(List<Map<String, dynamic>> aggregated) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Multi-frame Results'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(aggregated.toString())),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detector')),
      body: _isInitialized && _controller != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),
                CustomPaint(
                  painter: _DetectionPainter(_detections, _controller!.value.previewSize),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'multi',
            child: const Icon(Icons.camera),
            onPressed: () {
              // request 3-frame capture
              _captureMulti = true;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capturing 3 frames...')));
            },
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'throttle',
            child: const Icon(Icons.speed),
            onPressed: () {
              setState(() {
                _minIntervalMs = _minIntervalMs == 250 ? 500 : 250; // toggle 4FPS/2FPS
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Throttle set to ${_minIntervalMs}ms')));
            },
          ),
        ],
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final Size? previewSize;
  _DetectionPainter(this.detections, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    if (previewSize == null) return;

    final scaleX = size.width / previewSize!.height; // camera preview often rotated
    final scaleY = size.height / previewSize!.width;

    for (final d in detections) {
      final x1 = (d['x1'] as num).toDouble() * scaleX;
      final y1 = (d['y1'] as num).toDouble() * scaleY;
      final x2 = (d['x2'] as num).toDouble() * scaleX;
      final y2 = (d['y2'] as num).toDouble() * scaleY;
      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, paint);

      final label = d['label']?.toString() ?? '';
      final score = d['score'] is num ? (d['score'] as num).toDouble() : 0.0;
      final text = '$label ${(score * 100).toStringAsFixed(0)}%';

      textPainter.text = TextSpan(text: text, style: const TextStyle(color: Colors.white, fontSize: 12, backgroundColor: Colors.black54));
      textPainter.layout();
      textPainter.paint(canvas, Offset(x1, y1 - textPainter.height - 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
