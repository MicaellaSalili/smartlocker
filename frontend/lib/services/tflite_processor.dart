import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:google_mlkit_commons/google_mlkit_commons.dart'; // For InputImageRotation (keep if needed for InputImage)
import 'package:flutter/material.dart' show Size; // For Size in InputImageMetadata (Needed for the helper)

class TFLiteProcessor {
  // Private constructor to prevent instantiation
  TFLiteProcessor._();

  // --- Helper Methods (Keep or modify as needed) ---

  // Helper function to generate a consistent placeholder embedding
  static List<double> _generatePlaceholderEmbedding(int size) {
    return List<double>.generate(
      size,
      (index) => (index * 0.01) % 1.0, // Simple deterministic placeholder
    );
  }

  /// Processes an image scan: extracts waybill_id using ML Kit Text Recognition,
  /// runs MobileNetV2 TFLite model to generate a 128-element embedding vector.
  /// NOTE: The TFLite logic is commented out and replaced with a placeholder.
  static Future<Map<String, dynamic>> processScan(String imagePath) async {
    try {
      // 1. Load image from path
      final imageFile = File(imagePath);
      if (!imageFile.existsSync()) {
        return { 'error': 'Image file not found' };
      }
      final inputImage = InputImage.fromFile(imageFile);

      // 2. Use ML Kit Text Recognition to extract waybill_id and details
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      textRecognizer.close();

      // Find the largest alphanumeric string as waybill_id
      String waybillId = '';
      StringBuffer waybillDetailsBuffer = StringBuffer();
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final candidate = line.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
          if (candidate.length > waybillId.length) {
            waybillId = candidate;
          }
          waybillDetailsBuffer.writeln(line.text);
        }
      }
      final waybillDetails = waybillDetailsBuffer.toString().trim();
      if (waybillId.isEmpty) {
        return { 'error': 'Waybill ID not found in image' };
      }
      if (waybillDetails.isEmpty) {
        return { 'error': 'Waybill details not found in image' };
      }

      // 3. Load MobileNetV2 TFLite model
      final interpreter = await Interpreter.fromAsset('assets/models/mobilenet_v2.tflite');

      // 4. Preprocess image: resize to 224x224, normalize
      final rawBytes = await imageFile.readAsBytes();
      img.Image? oriImage = img.decodeImage(rawBytes);
      if (oriImage == null) {
        return { 'error': 'Failed to decode image' };
      }
      img.Image resizedImage = img.copyResize(oriImage, width: 224, height: 224);

      // Prepare input for TFLite: [1,224,224,3] Float32List normalized to [0,1]
      var inputBuffer = Float32List(1 * 224 * 224 * 3);
      int bufferIndex = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resizedImage.getPixel(x, y);
          inputBuffer[bufferIndex++] = pixel.r / 255.0; // Red
          inputBuffer[bufferIndex++] = pixel.g / 255.0; // Green
          inputBuffer[bufferIndex++] = pixel.b / 255.0; // Blue
        }
      }

      // 5. Run inference
      var outputShape = interpreter.getOutputTensor(0).shape;
      // Assume output is [1,128] or [128]
      var outputBuffer = List.filled(outputShape.reduce((a, b) => a * b), 0.0);
      interpreter.run(inputBuffer.buffer.asFloat32List(), outputBuffer);

      // Get embedding vector (assume output is [1,128] or [128])
      List<double> embedding;
      if (outputBuffer.length == 128) {
        embedding = outputBuffer.cast<double>();
      } else if (outputBuffer.length > 128) {
        embedding = outputBuffer.cast<double>().sublist(0, 128);
      } else {
        return { 'error': 'Model output size is not 128' };
      }

      interpreter.close();

      return {
        'waybill_id': waybillId,
        'waybill_details': waybillDetails,
        'image_embedding_vector': embedding,
      };
    } catch (e) {
      return { 'error': 'processScan failed', 'details': e.toString() };
    }
  }

  // Simulated waybill ID for consistent testing (normally would come from real OCR)
  static String _simulatedWaybillId = 'WB123456789';

  /// Simulates running OCR on an image to extract barcode ID and waybill details (REAL OCR)
  /// Returns a map with 'waybillId' and 'waybillDetails'
  static Future<Map<String, String>> extractBarcodeIdAndOcr(XFile imageFile) async {
    try {
      // 1. Load image from XFile
      final inputImage = InputImage.fromFilePath(imageFile.path);

      // 2. Use ML Kit Text Recognition to extract text (REAL)
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      textRecognizer.close();

      // 3. Analyze extracted text
      String waybillId = '';
      StringBuffer waybillDetailsBuffer = StringBuffer();

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final candidate = line.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
          if (candidate.length > waybillId.length) {
            waybillId = candidate;
          }
          waybillDetailsBuffer.writeln(line.text);
        }
      }

      final waybillDetails = waybillDetailsBuffer.toString().trim();

      if (waybillId.isEmpty || waybillDetails.isEmpty) {
        throw Exception('OCR failed: No text detected');
      }

      return {
        'waybillId': waybillId,
        'waybillDetails': waybillDetails,
      };
    } catch (e) {
      throw Exception('extractBarcodeIdAndOcr failed: ${e.toString()}');
    }
  }

  /// Simulates TFLite Model 2 execution to generate an embedding vector (MOCKED)
  /// Returns a list of doubles representing the embedding
  // static Interpreter? _mobilenetInterpreter; // MOCKED
  static Future<List<double>> generateEmbedding(Uint8List imageBytes) async {
    // try { // Removed try-catch since no actual TFLite logic is running
      // All TFLite/Image processing steps are MOCKED
      // 1. Load MobileNetV2 TFLite model (MOCKED)
      // 2. Decode image and resize to 224x224 (MOCKED)
      // 3. Prepare input: [1,224,224,3] (MOCKED)
      // 4. Run inference (MOCKED)
      // 5. Get embedding vector (MOCKED)

      return _generatePlaceholderEmbedding(128); // Placeholder 128-element vector
    // } catch (e) {
    //   throw Exception('generateEmbedding failed: ${e.toString()}');
    // }
  }

  /// Simulates live verification processing on a camera frame (MOCKED)
  /// Returns a map containing object detection boxes, live embedding, OCR text, and locker detection
  static Future<Map<String, dynamic>> runLiveVerification(CameraImage frame) async {
    try {
      // 1. Convert CameraImage to RGB bytes and InputImage (Keep conversion helpers for structure)
      // Uint8List rgbBytes = _convertCameraImageToRGBBytes(frame);
      InputImage inputImage = _cameraImageToInputImage(frame);

      // 2. Object Detection (ML Kit) (MOCKED)
      // final objectDetector = ...;
      // final List<DetectedObject> objects = await objectDetector.processImage(inputImage);
      // objectDetector.close();

      List<dynamic> boundingBoxes = [
        { // Example placeholder bounding box
          'class': 'package',
          'confidence': 0.95,
          'x': frame.width * 0.25,
          'y': frame.height * 0.3,
          'width': frame.width * 0.5,
          'height': frame.height * 0.4,
        }
      ];
      bool lockerDetected = true; // Placeholder value

      // 3. Text Recognition (ML Kit) (REAL, but less useful for live stream simulation)
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      textRecognizer.close();

      StringBuffer waybillDetailsBuffer = StringBuffer();
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          waybillDetailsBuffer.writeln(line.text);
        }
      }
      final liveWaybillDetails = waybillDetailsBuffer.toString().isNotEmpty 
          ? waybillDetailsBuffer.toString().trim()
          : 'Live OCR Placeholder Text'; // Fallback placeholder if no text is found

      // 4. Embedding Generation (TFLite) (MOCKED)
      final liveEmbedding = _generatePlaceholderEmbedding(128);

      // 5. Return results
      return {
        'liveEmbedding': liveEmbedding,
        'liveWaybillDetails': liveWaybillDetails,
        'boundingBoxes': boundingBoxes,
        'lockerDetected': lockerDetected,
      };
    } catch (e) {
      throw Exception('runLiveVerification failed: ${e.toString()}');
    }
  }

  /// Generate a placeholder parcel (waybill id, details and embedding) for bypass/testing flows
  static Future<Map<String, dynamic>> generatePlaceholderParcel() async {
    // Reuse the simulated waybill id and embedding
    _simulatedWaybillId = 'WB_PLACEHOLDER_${DateTime.now().millisecondsSinceEpoch}';

    final waybillDetails = 'Placeholder waybill details - ID: $_simulatedWaybillId - (bypass)';

    final embedding = _generatePlaceholderEmbedding(128);

    return {
      'waybillId': _simulatedWaybillId,
      'waybillDetails': waybillDetails,
      'embedding': embedding,
    };
  }

  // --- Utility Methods (Kept for structural integrity) ---

  /// Converts CameraImage (YUV420_888) to ML Kit InputImage for Text/Object Detection
  static InputImage _cameraImageToInputImage(CameraImage image) {
    // NOTE: This conversion is only kept if you need a valid InputImage for 
    // real ML Kit Text Recognition within runLiveVerification (which is kept real)
    Uint8List rgbBytes = _convertCameraImageToRGBBytes(image);

    final int width = image.width;
    final int height = image.height;
    final InputImageRotation rotation = InputImageRotation.rotation0deg;
    final InputImageFormat format = InputImageFormat.yuv_420_888;

    final metadata = InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: width * 3, // RGB stride
    );

    return InputImage.fromBytes(bytes: rgbBytes, metadata: metadata);
  }

  /// Converts CameraImage (YUV420_888) to RGB Uint8List suitable for TFLite input
  /// NOTE: This helper is kept as it is necessary for _cameraImageToInputImage to function.
  static Uint8List _convertCameraImageToRGBBytes(CameraImage image) {
    // ... original YUV to RGB conversion logic ...
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    final Uint8List yPlane = image.planes[0].bytes;
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;

    final Uint8List rgbBytes = Uint8List(width * height * 3);
    int pixelIndex = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final int yp = yPlane[y * width + x];
        final int up = uPlane[uvIndex];
        final int vp = vPlane[uvIndex];

        // YUV to RGB conversion (BT.601 standard)
        double yVal = yp.toDouble();
        double uVal = up.toDouble() - 128.0;
        double vVal = vp.toDouble() - 128.0;

        int r = (yVal + 1.402 * vVal).round();
        int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round();
        int b = (yVal + 1.772 * uVal).round();

        // Clamp values
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        rgbBytes[pixelIndex++] = r;
        rgbBytes[pixelIndex++] = g;
        rgbBytes[pixelIndex++] = b;
      }
    }
    return rgbBytes;
  }
}
  // Helper: Check if bounding box is in locker area
