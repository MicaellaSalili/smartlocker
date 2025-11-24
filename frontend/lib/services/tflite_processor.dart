// import 'dart:ui'; // Removed unused import
// import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter_vision/flutter_vision.dart'; 
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart'; // Removed image_picker as it wasn't strictly used in this snippet
// import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // Removed unused import
import 'text_recognition_service.dart';
import 'labels_loader.dart';

class TFLiteProcessor {
  static FlutterVision? _vision; // For YOLOv8
  static List<String>? _labels;
  static bool _isProcessingFrame = false;

  // Private constructor
  TFLiteProcessor._();

  /// Loads the MobileNet (Embedding) Model
  static Future<void> loadModel() async {
    // Temporarily disabled due to TensorFlow Lite conflicts
    // if (_interpreter != null) return;
    // try {
    //   final options = InterpreterOptions();
    //   _interpreter = await Interpreter.fromAsset('mobile_net_v2.tflite', options: options);
    //   print('✅ MobileNet Interpreter Loaded');
    // } catch (e) {
    //   print('❌ Error loading MobileNet: $e');
    // }
    print('⚠️ MobileNet loading disabled due to dependency conflicts');
  }

  /// Loads the YOLOv8 detection model using flutter_vision
  static Future<void> loadYoloModel() async {
    if (_vision != null) return;
    _vision = FlutterVision();
    try {
      debugPrint('TFLiteProcessor: attempting to load YOLO model with GPU delegate');
      await _vision!.loadYoloModel(
        modelPath: 'assets/models/yolov8_model.tflite',
        labels: 'assets/models/labels.txt',
        modelVersion: "yolov8",
        quantization: false,
        numThreads: 2,
        useGpu: true,
      );
      debugPrint('✅ YOLOv8 Model Loaded (GPU)');
      try {
        _labels = await ModelLabels.load();
        debugPrint('Model labels: $_labels');
      } catch (e) {
        debugPrint('Error loading model labels: $e');
      }
    } catch (e, s) {
      debugPrint('❌ Error loading YOLO model with GPU: $e');
      debugPrint('$s');
      // Try CPU-only fallback
      try {
        debugPrint('TFLiteProcessor: retrying YOLO model load with CPU-only');
        await _vision!.loadYoloModel(
          modelPath: 'assets/models/yolov8_model.tflite',
          labels: 'assets/models/labels.txt',
          modelVersion: "yolov8",
          quantization: false,
          numThreads: 2,
          useGpu: false,
        );
        debugPrint('✅ YOLOv8 Model Loaded (CPU)');
        try {
          _labels = await ModelLabels.load();
          debugPrint('Model labels: $_labels');
        } catch (e) {
          debugPrint('Error loading model labels: $e');
        }
      } catch (e2, s2) {
        debugPrint('❌ Error loading YOLO model with CPU fallback: $e2');
        debugPrint('$s2');
        // Keep _vision non-null so subsequent calls don't repeatedly attempt failing loads
      }
    }
  }

  /// Converts a CameraImage (YUV420) to an RGB img.Image
  static img.Image convertCameraImageToImage(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    
    final planeY = frame.planes[0];
    final planeU = frame.planes[1];
    final planeV = frame.planes[2];
    
    // Helper to safely access pixel data
    int uvIndex(int x, int y, int bytesPerRow, int bytesPerPixel) {
      return (y >> 1) * bytesPerRow + (x >> 1) * bytesPerPixel;
    }

    final imgImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * planeY.bytesPerRow + x;
        final int indexU = uvIndex(x, y, planeU.bytesPerRow, planeU.bytesPerPixel ?? 1);
        final int indexV = uvIndex(x, y, planeV.bytesPerRow, planeV.bytesPerPixel ?? 1);

        final yp = planeY.bytes[yIndex];
        final up = planeU.bytes[indexU];
        final vp = planeV.bytes[indexV];

        // YUV to RGB conversion math
        int r = (yp + 1.402 * (vp - 128)).toInt();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).toInt();
        int b = (yp + 1.772 * (up - 128)).toInt();

        // Clamp values 0-255
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return imgImage;
  }

  /// Preprocess image for MobileNet (128x128, normalized)
  // static List<dynamic> _processImageForModel(img.Image image) {
  //   // Resize to 128x128 as expected by standard MobileNetV2
  //   final resizedImage = img.copyResize(image, width: 128, height: 128);
  //   
  //   // Convert to float32 list and normalize (-1 to 1 or 0 to 1 depending on training)
  //   // Assuming standard MobileNet: (pixel - 127.5) / 127.5
  //   var inputBytes = Float32List(1 * 128 * 128 * 3);
  //   int pixelIndex = 0;
  //   for (int y = 0; y < 128; y++) {
  //     for (int x = 0; x < 128; x++) {
  //       final pixel = resizedImage.getPixel(x, y);
  //       inputBytes[pixelIndex++] = (pixel.r - 127.5) / 127.5;
  //       inputBytes[pixelIndex++] = (pixel.g - 127.5) / 127.5;
  //       inputBytes[pixelIndex++] = (pixel.b - 127.5) / 127.5;
  //     }
  //   }
  //   return inputBytes.reshape([1, 128, 128, 3]);
  // }

  /// Generates a real embedding using TFLite MobileNetV2 (128d output)
  static Future<List<double>> generateEmbedding(Uint8List imageBytes) async {
    // Temporarily return placeholder due to dependency conflicts
    // await loadModel();
    // final image = img.decodeImage(imageBytes);
    // if (image == null) throw Exception('Failed to decode image');
    // 
    // final inputTensor = _processImageForModel(image);
    // final outputTensor = List<double>.filled(128, 0.0).reshape([1, 128]);
    // 
    // _interpreter!.run(inputTensor, outputTensor);
    // return List<double>.from(outputTensor[0]);
    print('⚠️ Using placeholder embedding due to dependency conflicts');
    return List<double>.generate(128, (index) => (index * 0.01) % 1.0);
  }

  /// Detects objects using YOLOv8 directly on CameraImage
  static Future<List<Map<String, dynamic>>> detectYoloOnFrame(CameraImage cameraImage) async {
    if (_vision == null) await loadYoloModel();

    // Simple re-entrancy guard: if a frame is already being processed, skip this frame
    if (_isProcessingFrame) {
      return <Map<String, dynamic>>[];
    }

    _isProcessingFrame = true;
    try {
      // Run inference
      final result = await _vision!.yoloOnFrame(
        bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
        imageHeight: cameraImage.height,
        imageWidth: cameraImage.width,
        iouThreshold: 0.4,
        confThreshold: 0.35,
        classThreshold: 0.5,
      );

      debugPrint('TFLiteProcessor.yoloOnFrame returned ${result.length} items');
      if (result.isNotEmpty) debugPrint('First detection sample: ${result.first}');

      // Map numeric class indices (if present) to canonical model labels
      try {
        for (final d in result) {
          try {
            dynamic cls = d['class'] ?? d['class_id'] ?? d['index'];
            int? idx;
            if (cls is num) idx = cls.toInt();
            else if (cls is String) idx = int.tryParse(cls);

            if (idx != null && _labels != null && idx >= 0 && idx < _labels!.length) {
              d['model_label'] = _labels![idx];
            } else if (d.containsKey('label') && d['label'] is String) {
              // fall back to label string if provided by the detector
              d['model_label'] = d['label'];
            }
          } catch (_) {}
        }
      } catch (_) {}

      return result;
    } catch (e, s) {
      debugPrint('❌ Error during yoloOnFrame: $e');
      debugPrint('$s');
      return <Map<String, dynamic>>[];
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Clean up resources
  static Future<void> close() async {
     if (_vision != null) {
       await _vision!.closeYoloModel();
       _vision = null;
     }
     // _interpreter?.close();
     // _interpreter = null;
  }

  /// Extracts barcode ID and OCR text from an image using Google ML Kit
  static Future<Map<String, String>> extractBarcodeIdAndOcr(XFile imageFile) async {
    // ... [Keep your existing OCR implementation here] ...
    // I'm condensing this part for brevity, paste your existing extractBarcodeIdAndOcr logic here
    final textRecognitionService = TextRecognitionService();
    try {
      final result = await textRecognitionService.processImageFile(imageFile);
      textRecognitionService.dispose();
      return {
        'waybillId': result['waybillId'] ?? '[EMPTY]', 
        'waybillDetails': result['fullText'] ?? ''
      };
    } catch(e) {
      return {'waybillId': 'Error', 'waybillDetails': e.toString()};
    }
  }

  /// Generate a placeholder parcel
  static Future<Map<String, dynamic>> generatePlaceholderParcel() async {
    final placeholderWaybillId = 'WB_PLACEHOLDER_${DateTime.now().millisecondsSinceEpoch}';
    final embedding = List<double>.generate(128, (index) => (index * 0.01) % 1.0);

    return {
      'waybillId': placeholderWaybillId,
      'waybillDetails': 'Placeholder Details',
      'embedding': embedding,
    };
  }
}
