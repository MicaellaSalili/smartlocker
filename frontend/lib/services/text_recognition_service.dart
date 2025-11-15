import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';

/// Service class for handling text recognition operations using Google ML Kit
class TextRecognitionService {
  late final TextRecognizer _textRecognizer;

  TextRecognitionService({
    TextRecognitionScript script = TextRecognitionScript.latin,
  }) {
    _textRecognizer = TextRecognizer(script: script);
  }

  /// Process an image file and extract text
  Future<Map<String, dynamic>> processImageFile(XFile imageFile) async {
    try {
      print('📸 Processing image: ${imageFile.path}');
      final inputImage = InputImage.fromFilePath(imageFile.path);
      print('✅ InputImage created successfully');

      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      print('✅ ML Kit processing complete');
      print('📊 Blocks found: ${recognizedText.blocks.length}');

      return _extractTextData(recognizedText);
    } catch (e) {
      print('❌ ERROR in processImageFile: $e');
      print('Stack trace: ${StackTrace.current}');
      throw Exception('Failed to process image: $e');
    }
  }

  /// Process an image from file path
  Future<Map<String, dynamic>> processImageFromPath(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      return _extractTextData(recognizedText);
    } catch (e) {
      throw Exception('Failed to process image from path: $e');
    }
  }

  /// Process an image from bytes
  Future<Map<String, dynamic>> processImageFromBytes(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      return _extractTextData(recognizedText);
    } catch (e) {
      throw Exception('Failed to process image from bytes: $e');
    }
  }

  /// Extract waybill ID from recognized text
  /// Returns ALL scanned text - no auto-generation!
  String extractWaybillId(String text) {
    print('🔎 Extracting Waybill ID from scanned text:');
    print('   Text length: ${text.length} characters');
    print('   Full text:\n$text');

    // Clean up text but preserve content
    final cleanedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    if (cleanedText.isEmpty) {
      print('❌ WARNING: No text detected by Google ML Kit!');
      print('   Possible causes: poor lighting, blurry image, no text in frame');
      return '[NO_TEXT_DETECTED]';
    }
    
    print('✅ Using scanned text as waybill ID: $cleanedText');
    return cleanedText;
  }

  /// Extract barcode/tracking numbers from text
  List<String> extractBarcodes(String text) {
    final List<String> barcodes = [];

    // Common barcode patterns
    final patterns = [
      RegExp(r'\b\d{12,14}\b'), // EAN/UPC
      RegExp(r'\b[A-Z0-9]{10,20}\b'), // Generic tracking
      RegExp(r'WB[A-Z0-9]+', caseSensitive: false), // Waybill
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        final barcode = match.group(0)!;
        if (!barcodes.contains(barcode)) {
          barcodes.add(barcode);
        }
      }
    }

    return barcodes;
  }

  /// Extract specific J&T Express waybill data
  Map<String, String> extractJTExpressData(String text) {
    final Map<String, String> data = {};
    final lines = text.split('\n');

    // Remove all spaces for better pattern matching
    final textNoSpaces = text.replaceAll(' ', '').replaceAll('-', '');

    // Extract Order ID (Waybill ID) - handle multiple courier formats
    // SPX: 251010QHR7YCKJ (6 digits + letters)
    // Flash: 250615HX5PJRSP (6 digits + letters)
    // J&T: 250601DM37R870 (6 digits + letters + numbers)

    // Pattern 1: Standard format - 6 digits (YYMMDD) + 4+ alphanumeric
    final orderIdPattern1 = RegExp(r'\d{6}[A-Z0-9]{4,}', caseSensitive: false);
    final orderIdMatch1 = orderIdPattern1.firstMatch(textNoSpaces);
    if (orderIdMatch1 != null) {
      data['orderId'] = orderIdMatch1.group(0)!.toUpperCase();
      print('✅ Found Order ID (Pattern 1): ${data['orderId']}');
    } else {
      print('❌ Pattern 1 failed (YYMMDDXXXX)');

      // Pattern 2: Look in lines for "Order ID" label
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.toUpperCase().contains('ORDER') &&
            line.toUpperCase().contains('ID')) {
          // Check same line first (e.g., "Order ID: 250615HX5PJRSP")
          final sameLine = line.replaceAll(
            RegExp(r'Order\s*ID\s*:?\s*', caseSensitive: false),
            '',
          );
          if (sameLine.length >= 10) {
            data['orderId'] = sameLine.replaceAll(' ', '').toUpperCase();
            print('✅ Found Order ID (Pattern 2a): ${data['orderId']}');
            break;
          }
          // Check next line
          if (i + 1 < lines.length) {
            final possibleId = lines[i + 1].trim().replaceAll(' ', '');
            if (possibleId.length >= 10) {
              data['orderId'] = possibleId.toUpperCase();
              print('✅ Found Order ID (Pattern 2b): ${data['orderId']}');
              break;
            }
          }
        }
      }
    }

    // Extract barcode number
    // Pattern 1: 13 digits (J&T: 789627726505)
    final barcodePattern13 = RegExp(r'\b\d{13}\b');
    final barcodeMatch13 = barcodePattern13.firstMatch(text);
    if (barcodeMatch13 != null) {
      data['barcode'] = barcodeMatch13.group(0)!;
      print('✅ Found barcode (13 digits): ${data['barcode']}');
    } else {
      // Pattern 2: PH + alphanumeric (SPX: PH251238905125S)
      final barcodePHPattern = RegExp(r'PH[A-Z0-9]{10,}', caseSensitive: false);
      final barcodePHMatch = barcodePHPattern.firstMatch(text);
      if (barcodePHMatch != null) {
        data['barcode'] = barcodePHMatch.group(0)!.toUpperCase();
        print('✅ Found barcode (PH format): ${data['barcode']}');
      } else {
        // Pattern 3: P + 13+ alphanumeric (Flash: P6118C6XD8BAY)
        final barcodePattern = RegExp(r'P[A-Z0-9]{10,}', caseSensitive: false);
        final barcodeMatch = barcodePattern.firstMatch(text);
        if (barcodeMatch != null) {
          data['barcode'] = barcodeMatch.group(0)!.toUpperCase();
          print('✅ Found barcode (P format): ${data['barcode']}');
        }
      }
    }

    // Extract tracking number
    // Pattern 1: J&T format (730-D038 00)
    final trackingPattern1 = RegExp(
      r'\b\d{3}-?[A-Z]\d{3}\s*\d{2}\b',
      caseSensitive: false,
    );
    final trackingMatch1 = trackingPattern1.firstMatch(text);
    if (trackingMatch1 != null) {
      data['trackingNumber'] = trackingMatch1.group(0)!;
      print('✅ Found tracking (J&T format): ${data['trackingNumber']}');
    } else {
      // Pattern 2: Flash format (16-1 6092-D1)
      final trackingPattern2 = RegExp(
        r'\b\d{2}-?\d\s+\d{4}-?[A-Z]?\d+\b',
        caseSensitive: false,
      );
      final trackingMatch2 = trackingPattern2.firstMatch(text);
      if (trackingMatch2 != null) {
        data['trackingNumber'] = trackingMatch2.group(0)!;
        print('✅ Found tracking (Flash format): ${data['trackingNumber']}');
      } else {
        // Pattern 3: Look for tracking code like "PRT SP", "AA2", etc.
        final codePattern = RegExp(r'\b[A-Z]{2,3}\s+[A-Z]{2}\b');
        final codeMatch = codePattern.firstMatch(text);
        if (codeMatch != null) {
          data['trackingNumber'] = codeMatch.group(0)!;
          print('✅ Found tracking code: ${data['trackingNumber']}');
        }
      }
    }

    // Extract buyer name (look for line after "BUYER" keyword or name pattern)
    bool foundBuyer = false;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Look for BUYER keyword
      if (line.toUpperCase().contains('BUYER')) {
        // Try next few lines
        for (int j = i + 1; j < lines.length && j < i + 4; j++) {
          final nextLine = lines[j].trim();
          // Look for name pattern: words starting with capital letters
          if (RegExp(r'^[A-Z][a-z]+\s+[A-Z]').hasMatch(nextLine) &&
              !nextLine.toUpperCase().contains('COMPOUND') &&
              !nextLine.toUpperCase().contains('RESIDENCES') &&
              !nextLine.toUpperCase().contains('GRAND VIEW') &&
              !nextLine.toUpperCase().contains('SAN FERNANDO') &&
              !nextLine.toUpperCase().contains('METRO MANILA') &&
              !nextLine.toUpperCase().contains('JADE') &&
              !nextLine.toUpperCase().contains('PROFESSORS') &&
              !nextLine.toUpperCase().contains('APPAREL') &&
              !nextLine.toUpperCase().contains('CITY') &&
              nextLine.length < 50) {
            data['buyerName'] = nextLine;
            print('✅ Found Buyer Name: ${data['buyerName']}');
            foundBuyer = true;
            break;
          }
        }
        if (foundBuyer) break;
      }

      // Alternative: Look for name pattern in any line (capitalized name format)
      if (!foundBuyer) {
        // Match patterns like "Z Rodriguez", "Jessica Rae Gomez", "Denette Joy Gomez"
        if (RegExp(
              r'^[A-Z]\s+[A-Z][a-z]+|^[A-Z][a-z]+\s+[A-Z][a-z]+\s+[A-Z]',
            ).hasMatch(line) &&
            !line.toUpperCase().contains('SAN FERNANDO') &&
            !line.toUpperCase().contains('METRO MANILA') &&
            !line.toUpperCase().contains('QUEZON') &&
            !line.toUpperCase().contains('BAGUIO') &&
            !line.toUpperCase().contains('CITY') &&
            !line.toUpperCase().contains('JADE') &&
            !line.toUpperCase().contains('BARANGAY') &&
            line.length >= 5 &&
            line.length < 50) {
          data['buyerName'] = line;
          print('✅ Found Buyer Name (Alternative): ${data['buyerName']}');
          foundBuyer = true;
        }
      }
    }

    // Extract weight (e.g., "7 kg")
    final weightPattern = RegExp(
      r'Weight:\s*(\d+(?:\.\d+)?)\s*kg',
      caseSensitive: false,
    );
    final weightMatch = weightPattern.firstMatch(text);
    if (weightMatch != null) {
      data['weight'] = '${weightMatch.group(1)} kg';
    }

    // Extract product quantity
    final quantityPattern = RegExp(
      r'(?:Product\s+)?Quantity:\s*(\d+)',
      caseSensitive: false,
    );
    final quantityMatch = quantityPattern.firstMatch(text);
    if (quantityMatch != null) {
      data['productQuantity'] = quantityMatch.group(1)!;
    }

    return data;
  }

  /// Extract all text data from recognized text
  Map<String, dynamic> _extractTextData(RecognizedText recognizedText) {
    print('🟢 ENTERING _extractTextData');
    print('🟢 Number of blocks from ML Kit: ${recognizedText.blocks.length}');

    final StringBuffer fullTextBuffer = StringBuffer();
    final List<Map<String, dynamic>> blocks = [];
    final List<String> lines = [];

    for (final block in recognizedText.blocks) {
      print('🟢 Processing block: ${block.text}');
      final blockData = <String, dynamic>{
        'text': block.text,
        'boundingBox': {
          'left': block.boundingBox.left,
          'top': block.boundingBox.top,
          'right': block.boundingBox.right,
          'bottom': block.boundingBox.bottom,
        },
        'lines': [],
      };

      for (final line in block.lines) {
        lines.add(line.text);
        fullTextBuffer.writeln(line.text);

        blockData['lines'].add({
          'text': line.text,
          'boundingBox': {
            'left': line.boundingBox.left,
            'top': line.boundingBox.top,
            'right': line.boundingBox.right,
            'bottom': line.boundingBox.bottom,
          },
        });
      }

      blocks.add(blockData);
    }

    final fullText = fullTextBuffer.toString().trim();

    // TESTING MODE: Just use whatever text is detected, no pattern matching
    final waybillId = extractWaybillId(fullText);
    final barcodes = extractBarcodes(fullText);

    // Extract J&T Express specific data (optional for display)
    final jtExpressData = extractJTExpressData(fullText);

    print('🧪 TESTING MODE - Using raw text as waybillId');
    print('📝 WaybillId will be: $waybillId');
    print('📝 Full text: $fullText');

    return {
      'fullText': fullText,
      'waybillId': waybillId, // USE RAW TEXT, not orderId pattern
      'barcodes': barcodes,
      'blocks': blocks,
      'lines': lines,
      'blockCount': recognizedText.blocks.length,
      // J&T Express specific fields (for waybillDetails formatting)
      'orderId': jtExpressData['orderId'] ?? '',
      'barcode': jtExpressData['barcode'] ?? '',
      'trackingNumber': jtExpressData['trackingNumber'] ?? '',
      'buyerName': jtExpressData['buyerName'] ?? '',
      'weight': jtExpressData['weight'] ?? '',
      'productQuantity': jtExpressData['productQuantity'] ?? '',
    };
  }

  /// Extract specific data based on custom patterns
  Map<String, String> extractCustomData(
    String text,
    Map<String, RegExp> patterns,
  ) {
    final Map<String, String> results = {};

    patterns.forEach((key, pattern) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        results[key] = match.group(0)!;
      }
    });

    return results;
  }

  /// Dispose of resources
  void dispose() {
    _textRecognizer.close();
  }
}
