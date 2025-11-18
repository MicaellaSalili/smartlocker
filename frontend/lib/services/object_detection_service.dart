import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection_v2/google_mlkit_object_detection_v2.dart';
import 'package:camera/camera.dart';
import 'dart:ui' as ui;

class ObjectDetectionService {
  ObjectDetector? _objectDetector;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final options = ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      );

      _objectDetector = ObjectDetector(options: options);
      _isInitialized = true;
      debugPrint('✅ Object Detector initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing Object Detector: $e');
      rethrow;
    }
  }

  Future<List<DetectedObject>> detectObjects(InputImage inputImage) async {
    if (!_isInitialized || _objectDetector == null) {
      throw Exception('Object Detector not initialized');
    }

    try {
      final objects = await _objectDetector!.processImage(inputImage);
      return objects;
    } catch (e) {
      debugPrint('Error detecting objects: $e');
      return [];
    }
  }

  void dispose() {
    _objectDetector?.close();
    _isInitialized = false;
  }
}

class DetectionPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final Size screenSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  DetectionPainter({
    required this.objects,
    required this.imageSize,
    required this.screenSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.green.withOpacity(0.15);

    for (final DetectedObject detectedObject in objects) {
      final rect = _scaleRect(
        rect: detectedObject.boundingBox,
        imageSize: imageSize,
        widgetSize: size,
        rotation: rotation,
        cameraLensDirection: cameraLensDirection,
      );

      // Draw filled rectangle
      canvas.drawRect(rect, fillPaint);

      // Draw border
      canvas.drawRect(rect, paint);

      // Draw corner brackets for better visibility
      _drawCornerBrackets(canvas, rect, paint);

      // Draw labels if available
      if (detectedObject.labels.isNotEmpty) {
        final label = detectedObject.labels.first;
        final textPainter = TextPainter(
          text: TextSpan(
            text:
                '${label.text} ${(label.confidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.green,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(rect.left, rect.top - 20));
      }
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    final double cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(0, cornerLength),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLength),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLength),
      paint,
    );
  }

  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
    required InputImageRotation rotation,
    required CameraLensDirection cameraLensDirection,
  }) {
    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;

    if (rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg) {
      return Rect.fromLTRB(
        rect.left * scaleY,
        rect.top * scaleX,
        rect.right * scaleY,
        rect.bottom * scaleX,
      );
    }

    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.objects != objects;
  }
}
