import 'dart:typed_data';
import 'dart:ui';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'text_recognition_service.dart';

class TFLiteProcessor {
  static Interpreter? _interpreter;
  static Interpreter? _detectionInterpreter;

  // Private constructor to prevent instantiation
  TFLiteProcessor._();

  /// Converts a CameraImage (YUV420) to an RGB img.Image
  static img.Image convertCameraImageToImage(CameraImage frame) {
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

  /// Loads the TFLite model from assets/models/model_128.tflite
  static Future<void> loadModel() async {
    if (_interpreter != null) return;
    final interpreter = await Interpreter.fromAsset('assets/models/model_128.tflite');
    interpreter.allocateTensors();
    _interpreter = interpreter;
  }

  /// Loads the YOLOv8 detection model from assets/models/yolov8_model.tflite
  static Future<void> loadYoloModel() async {
    if (_detectionInterpreter != null) return;
    final interpreter = await Interpreter.fromAsset('assets/models/yolov8_model.tflite');
    interpreter.allocateTensors();
    _detectionInterpreter = interpreter;
  }

  /// Preprocesses the image for MobileNetV2: resize to 128x128, normalize to [-1, 1], flatten to Float32List
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
      detailsBuffer.writeln('=== Scanned WAYBILL ===');

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

  /// Detects objects using YOLOv8 model
  /// Returns list of detections with class, confidence, and bounding box
  static Future<List<Map<String, dynamic>>> detectYoloObjects(img.Image image) async {
    await loadYoloModel();
    // Resize image to model input size, e.g., 640x640 for YOLOv8
    final resized = img.copyResize(image, width: 640, height: 640);
    final input = Float32List(1 * 640 * 640 * 3);
    int i = 0;
    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();
        input[i++] = r / 255.0;
        input[i++] = g / 255.0;
        input[i++] = b / 255.0;
      }
    }
    // Assume output shape [1, num_detections, 6] for [x,y,w,h,conf,class]
    // Adjust based on actual model export
    final output = List<List<double>>.filled(1, List<double>.filled(8400 * 6, 0.0)); // Example for 8400 detections
    _detectionInterpreter!.run(input.reshape([1, 640, 640, 3]), output);
    List<Map<String, dynamic>> detections = [];
    for (int i = 0; i < 8400; i++) {
      double conf = output[0][i * 6 + 4];
      if (conf > 0.5) { // Threshold
        double x = output[0][i * 6];
        double y = output[0][i * 6 + 1];
        double w = output[0][i * 6 + 2];
        double h = output[0][i * 6 + 3];
        int cls = output[0][i * 6 + 5].toInt();
        String className = cls == 0 ? 'package' : 'locker'; // Assuming 0=package, 1=locker
        detections.add({
          'class': className,
          'confidence': conf,
          'x': x,
          'y': y,
          'width': w,
          'height': h,
        });
      }
    }
    return detections;
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

    // Check for locker detection
    for (var box in boundingBoxes) {
      if (box['class'] == 'locker_frame' && (box['confidence'] as double) >= 0.85) {
        lockerDetected = true;
        break;
      }
    }
    
    // b) TFLite Model 2 (Embedding Generation) - real embedding from cropped package image
    List<double> liveEmbedding;
    try {
      final fullImage = convertCameraImageToImage(frame);
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
    
    // c) OCR - live waybill details
    final liveWaybillDetails = ''; // Will be populated by actual OCR

    return {
      'boundingBoxes': boundingBoxes,
      'liveEmbedding': liveEmbedding,
      'liveWaybillDetails': liveWaybillDetails,
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