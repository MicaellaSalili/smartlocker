import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'text_recognition_service.dart';

class TFLiteProcessor {
  // Private constructor to prevent instantiation
  TFLiteProcessor._();

  /// Helper: Convert CameraImage to InputImage for real-time processing
  /// Platform-specific implementation for Android/iOS
  static InputImage convertCameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
    int sensorOrientation,
  ) {
    // Get image rotation
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) {
      throw Exception('Invalid sensor orientation: $sensorOrientation');
    }

    // Get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      throw Exception('Unsupported image format: ${image.format.raw}');
    }

    // Concatenate all plane bytes
    final allBytes = BytesBuilder();
    for (final plane in image.planes) {
      allBytes.add(plane.bytes);
    }
    final bytes = allBytes.toBytes();

    // Build metadata
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  /// Extracts barcode ID and OCR text from an image using Google ML Kit
  /// Returns a map with 'waybillId' and 'waybillDetails'
  static Future<Map<String, String>> extractBarcodeIdAndOcr(
    XFile imageFile,
  ) async {
    print('\n🔵 ENTERING extractBarcodeIdAndOcr()');
    print('📁 Image file path: ${imageFile.path}');

    try {
      print('🔵 Creating TextRecognitionService...');
      final textRecognitionService = TextRecognitionService();

      print('🔵 Calling processImageFile...');
      final result = await textRecognitionService.processImageFile(imageFile);

      print('🔵 Got result from processImageFile');
      print('🔵 Result keys: ${result.keys.toList()}');
      print('🔵 Result waybillId: ${result['waybillId']}');
      print(
        '🔵 Result fullText length: ${result['fullText']?.toString().length ?? 0}',
      );

      textRecognitionService.dispose();

      // NEVER auto-generate - always use what ML Kit actually scanned
      final String waybillId = result['waybillId'] ?? '[EMPTY]';

      print('🔵 Final waybillId after processing: $waybillId');

      if (waybillId == '[EMPTY]' || waybillId == '[NO_TEXT_DETECTED]') {
        print('⚠️ WARNING: ML Kit did not detect any text!');
        print('   Check: lighting, focus, text visibility, camera permissions');
      }

      // Get the full recognized text
      final String fullText = result['fullText'] ?? '';
      print(
        '🔵 Full text first 100 chars: ${fullText.substring(0, fullText.length > 100 ? 100 : fullText.length)}',
      );

      // Format J&T Express specific details
      final StringBuffer detailsBuffer = StringBuffer();
      detailsBuffer.writeln('=== J&T EXPRESS WAYBILL ===');

      if (result['orderId'] != null &&
          result['orderId'].toString().isNotEmpty) {
        detailsBuffer.writeln('Order ID: ${result['orderId']}');
      }
      if (result['trackingNumber'] != null &&
          result['trackingNumber'].toString().isNotEmpty) {
        detailsBuffer.writeln('Tracking: ${result['trackingNumber']}');
      }
      if (result['barcode'] != null &&
          result['barcode'].toString().isNotEmpty) {
        detailsBuffer.writeln('Barcode: ${result['barcode']}');
      }
      if (result['buyerName'] != null &&
          result['buyerName'].toString().isNotEmpty) {
        detailsBuffer.writeln('Buyer: ${result['buyerName']}');
      }
      if (result['productQuantity'] != null &&
          result['productQuantity'].toString().isNotEmpty) {
        detailsBuffer.writeln('Quantity: ${result['productQuantity']}');
      }
      if (result['weight'] != null && result['weight'].toString().isNotEmpty) {
        detailsBuffer.writeln('Weight: ${result['weight']}');
      }
      detailsBuffer.writeln('========================');
      detailsBuffer.writeln('\nFull Text:\n$fullText');

      final String waybillDetails = detailsBuffer.toString();

      // Check if OCR actually read anything
      if (fullText.isEmpty || fullText.length < 10) {
        print('⚠️ WARNING: OCR returned very little or no text!');
        print('   This usually means:');
        print('   - Poor lighting');
        print('   - Text is blurry/out of focus');
        print('   - Image quality too low');
        print('   - Text is too small in the frame');
      }

      // Debug logging with clear separation
      print('\n' + '=' * 50);
      print('🔍 OCR DEBUG - WHAT ML KIT ACTUALLY SAW:');
      print('=' * 50);
      print('📝 FULL RAW TEXT FROM IMAGE:');
      print('---');
      print(result['fullText'] ?? '[EMPTY - NO TEXT DETECTED]');
      print('---');
      print('\n🎯 Extracted Data:');
      print('  • Order ID (Waybill ID): $waybillId');
      print('  • All Barcodes: ${result['barcodes']}');
      print('  • Buyer Name: ${result['buyerName']}');
      print('  • Weight: ${result['weight']}');
      print('  • Quantity: ${result['productQuantity']}');
      print('=' * 50 + '\n');

      return {'waybillId': waybillId, 'waybillDetails': waybillDetails};
    } catch (e) {
      print('❌ ERROR in extractBarcodeIdAndOcr: $e');
      print('Stack trace: ${StackTrace.current}');
      return {
        'waybillId': '[ERROR: $e]',
        'waybillDetails':
            'Error extracting text: $e\n\nPlease try again with better lighting and ensure the waybill is clearly visible.',
      };
    }
  }

  /// Simulates TFLite Model 2 execution to generate an embedding vector
  /// Returns a list of doubles representing the embedding
  static Future<List<double>> generateEmbedding(Uint8List imageBytes) async {
    final interpreter = await Interpreter.fromAsset(
      'model/mobilenet_v2.tflite',
    );
    // Preprocess imageBytes to match model input shape (e.g., 224x224 RGB)
    // This is a simplified example, use tflite_flutter_helper for real preprocessing
    final input = imageBytes.buffer.asUint8List();
    var output = List.filled(128, 0.0).reshape([1, 128]);
    interpreter.run(input, output);
    interpreter.close();
    return List<double>.from(output[0]);
  }

  /// Simulates live verification processing on a camera frame
  /// Returns a map containing object detection boxes, live embedding, OCR text, and locker detection
  static Future<Map<String, dynamic>> runLiveVerification(
    CameraImage frame,
  ) async {
    // Platform-specific: convert CameraImage to InputImage
    // final inputImage = convertCameraImageToInputImage(frame); // Uncomment when implemented

    // For now, skip actual object detection and return empty results
    List<Map<String, dynamic>> boundingBoxes = [];
    bool lockerDetected = false;

    // TODO: Implement object detection, embedding, and OCR using inputImage

    return {
      'boundingBoxes': boundingBoxes,
      'liveEmbedding': [], // Fill with actual embedding
      'liveWaybillDetails': '', // Fill with actual OCR result
      'lockerDetected': lockerDetected,
    };
  }

  /// Generate a placeholder parcel (waybill id, details and embedding) for bypass/testing flows
  static Future<Map<String, dynamic>> generatePlaceholderParcel() async {
    // Generate a placeholder waybill id
    final placeholderWaybillId =
        'WB_PLACEHOLDER_${DateTime.now().millisecondsSinceEpoch}';

    final waybillDetails =
        'Placeholder waybill details - ID: $placeholderWaybillId - (bypass)';

    final embedding = List<double>.generate(
      128,
      (index) => (index * 0.01) % 1.0,
    );

    return {
      'waybillId': placeholderWaybillId,
      'waybillDetails': waybillDetails,
      'embedding': embedding,
    };
  }
}
