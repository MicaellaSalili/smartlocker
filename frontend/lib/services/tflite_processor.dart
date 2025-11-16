import 'dart:typed_data';
// import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';

class TFLiteProcessor {
  // static Interpreter? _interpreter; // Removed duplicate

  /// Converts a CameraImage (YUV420) to an RGB img.Image
  static img.Image _convertCameraImageToImage(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    final imgImage = img.Image(width: width, height: height);

    final planeY = frame.planes[0];
    final planeU = frame.planes[1];
    final planeV = frame.planes[2];

    final bytesY = planeY.bytes;
    final bytesU = planeU.bytes;
    final bytesV = planeV.bytes;

    final strideY = planeY.bytesPerRow;
    final strideU = planeU.bytesPerRow;
    final strideV = planeV.bytesPerRow;
    final pixelStrideU = planeU.bytesPerPixel ?? 1;
    final pixelStrideV = planeV.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvRow = y >> 1;
        final uvCol = x >> 1;
        final uvIndexU = uvRow * strideU + uvCol * pixelStrideU;
        final uvIndexV = uvRow * strideV + uvCol * pixelStrideV;
        final yIndex = y * strideY + x;

        final Y = bytesY[yIndex];
        final U = bytesU[uvIndexU];
        final V = bytesV[uvIndexV];

        // YUV420 to RGB conversion
        double yVal = (Y - 16) * 1.164;
        double uVal = (U - 128).toDouble();
        double vVal = (V - 128).toDouble();

        int r = (yVal + 1.596 * vVal).round().clamp(0, 255);
        int g = (yVal - 0.813 * vVal - 0.391 * uVal).round().clamp(0, 255);
        int b = (yVal + 2.018 * uVal).round().clamp(0, 255);

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return imgImage;
  }
  static Interpreter? _interpreter;
    /// Loads the TFLite model from assets/models/model_128.tflite
    static Future<void> loadModel() async {
      if (_interpreter != null) return;
      final interpreter = await Interpreter.fromAsset('assets/models/model_128.tflite');
      interpreter.allocateTensors();
      _interpreter = interpreter;
    }
    /// Preprocesses the image for MobileNetV2: resize to 224x224, normalize to [-1, 1], flatten to Float32List
  static Float32List _processImageForModel(img.Image image) {
    final resized = img.copyResize(image, width: 128, height: 128);
    final input = Float32List(1 * 128 * 128 * 3);
    int i = 0;
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        final pixel = resized.getPixel(x, y);
        int r, g, b;
        if (pixel is int) {
          r = pixel.r.toInt();
          g = pixel.g.toInt();
          b = pixel.b.toInt();
        } else {
          r = pixel.r.toInt();
          g = pixel.g.toInt();
          b = pixel.b.toInt();
        }
        input[i++] = (r / 127.5) - 1.0;
        input[i++] = (g / 127.5) - 1.0;
        input[i++] = (b / 127.5) - 1.0;
      }
    }
    return input;
  }
  // Private constructor to prevent instantiation
  TFLiteProcessor._();

  // Simulated waybill ID for consistent testing (normally would come from real OCR)
  static String _simulatedWaybillId = 'WB123456789';

  /// Simulates running OCR on an image to extract barcode ID and waybill details
  /// Returns a map with 'waybillId' and 'waybillDetails'
  static Future<Map<String, String>> extractBarcodeIdAndOcr(XFile imageFile) async {
    // TODO: Implement actual OCR processing using google_mlkit_text_recognition
    // This is a placeholder that simulates the OCR process
    
    await Future.delayed(const Duration(seconds: 1)); // Simulate processing time
    
    // Generate a consistent waybill ID for this session
    _simulatedWaybillId = 'WB${DateTime.now().millisecondsSinceEpoch}';
    
    // Simulated OCR results - include waybill ID in details
    return {
      'waybillId': _simulatedWaybillId,
      'waybillDetails': 'Sample waybill details - ID: $_simulatedWaybillId - Sender: ABC Corp',
    };
  }

  /// Generates a real embedding using TFLite MobileNetV2 (128d output)
  /// Returns a list of doubles representing the embedding
  static Future<List<double>> generateEmbedding(Uint8List imageBytes) async {
    await loadModel();
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Failed to decode image');
    final inputTensor = _processImageForModel(image);
    final outputTensor = List<double>.filled(128, 0.0).reshape([1, 128]);
    _interpreter!.run(inputTensor.reshape([1, 128, 128, 3]), outputTensor);
    return List<double>.from(outputTensor[0]);
  }

  /// Simulates live verification processing on a camera frame
  /// Returns a map containing object detection boxes, live embedding, OCR text, and locker detection
  static Future<Map<String, dynamic>> runLiveVerification(CameraImage frame) async {
    // TODO: Implement actual TFLite and OCR processing
    // This is a placeholder that simulates the live verification process
    
    await Future.delayed(const Duration(milliseconds: 300)); // Simulate processing time
    
    // a) Simulate TFLite Model 1 (Object Detection) - bounding boxes
    final boundingBoxes = [
      {
        'class': 'package',
        'confidence': 0.95,
        'x': 100.0,
        'y': 150.0,
        'width': 200.0,
        'height': 250.0,
      },
      {
        'class': 'waybill',
        'confidence': 0.88,
        'x': 120.0,
        'y': 180.0,
        'width': 160.0,
        'height': 80.0,
      },
      {
        'class': 'locker_frame',
        'confidence': 0.92,
        'x': 50.0,
        'y': 100.0,
        'width': 300.0,
        'height': 350.0,
      },
    ];
    
    // Check if locker_frame is detected with sufficient confidence
    bool lockerDetected = false;
    for (var box in boundingBoxes) {
      if (box['class'] == 'locker_frame' && (box['confidence'] as double) >= 0.85) {
        lockerDetected = true;
        break;
      }
    }
    
    // b) TFLite Model 2 (Embedding Generation) - real embedding from cropped package image
    List<double> liveEmbedding;
    try {
      final fullImage = _convertCameraImageToImage(frame);
      final packageBox = boundingBoxes.firstWhere(
        (box) => box['class'] == 'package',
        orElse: () => <String, Object>{},
      );
      if (packageBox.isNotEmpty) {
        int x = (packageBox['x'] as double).round();
        int y = (packageBox['y'] as double).round();
        int w = (packageBox['width'] as double).round();
        int h = (packageBox['height'] as double).round();
        final cropped = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);
        final inputTensor = _processImageForModel(cropped);
        final outputTensor = List<double>.filled(128, 0.0).reshape([1, 128]);
        await loadModel();
        _interpreter!.run(inputTensor.reshape([1, 128, 128, 3]), outputTensor);
        liveEmbedding = List<double>.from(outputTensor[0]);
      } else {
        liveEmbedding = List<double>.filled(128, 0.0);
      }
    } catch (e) {
      liveEmbedding = List<double>.filled(128, 0.0);
    }
    
    // c) Simulate OCR - live waybill details (must include the waybill ID for ID matching)
    final liveWaybillDetails = 'Sample waybill details - ID: $_simulatedWaybillId - Sender: ABC Corp';
    
    return {
      'boundingBoxes': boundingBoxes,
      'liveEmbedding': liveEmbedding,
      'liveWaybillDetails': liveWaybillDetails,
      'lockerDetected': lockerDetected, // New field for locker frame detection
    };
  }

  /// Generate a placeholder parcel (waybill id, details and embedding) for bypass/testing flows
  static Future<Map<String, dynamic>> generatePlaceholderParcel() async {
    // Reuse the simulated waybill id and embedding
    _simulatedWaybillId = 'WB_PLACEHOLDER_${DateTime.now().millisecondsSinceEpoch}';

    final waybillDetails = 'Placeholder waybill details - ID: $_simulatedWaybillId - (bypass)';

    final embedding = List<double>.generate(
      128,
      (index) => (index * 0.01) % 1.0,
    );

    return {
      'waybillId': _simulatedWaybillId,
      'waybillDetails': waybillDetails,
      'embedding': embedding,
    };
  }
}