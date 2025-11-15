# Google ML Kit Text Recognition Integration Guide

## Overview
This guide explains how to integrate Google ML Kit's text recognition with camera functionality in your Flutter Smart Locker project.

## ✅ Prerequisites (Already Installed)
- `google_mlkit_text_recognition: ^0.11.0`
- `camera: ^0.10.5+9`
- `image_picker: ^1.0.4`

## 📁 Project Structure

```
lib/
├── screens/
│   ├── text_recognition_screen.dart    # NEW: Standalone text recognition screen
│   ├── scan_screen.dart                # Updated: Uses text recognition
│   └── ...
├── services/
│   ├── text_recognition_service.dart   # NEW: Reusable text recognition service
│   ├── tflite_processor.dart           # Updated: Improved ML Kit integration
│   └── ...
└── main.dart                           # Updated: Added new route
```

## 🚀 Features Implemented

### 1. **TextRecognitionScreen** (Standalone)
A dedicated screen for text recognition with:
- Live camera preview
- Capture and recognize text functionality
- Display recognized text in a scrollable view
- Copy-to-clipboard functionality
- User-friendly UI with loading states

**Usage:**
```dart
// Navigate to text recognition screen
Navigator.pushNamed(context, '/text_recognition');

// Or with direct navigation
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const TextRecognitionScreen(),
  ),
);
```

### 2. **TextRecognitionService** (Reusable Service)
A service class that handles all text recognition operations:

**Features:**
- Process images from various sources (file, path, bytes)
- Extract waybill IDs automatically (WB pattern)
- Extract barcodes and tracking numbers
- Get detailed text blocks with bounding boxes
- Custom pattern extraction

**Usage:**
```dart
// Initialize service
final textRecognitionService = TextRecognitionService();

// Process an image file
final XFile imageFile = await camera.takePicture();
final result = await textRecognitionService.processImageFile(imageFile);

// Access results
String fullText = result['fullText'];
String waybillId = result['waybillId'];
List<String> barcodes = result['barcodes'];
List<Map<String, dynamic>> blocks = result['blocks'];

// Dispose when done
textRecognitionService.dispose();
```

### 3. **TFLiteProcessor Updates**
Enhanced with better ML Kit integration:

**Improvements:**
- Uses `TextRecognitionService` for cleaner code
- Better error handling
- Proper CameraImage to InputImage conversion
- Real-time processing support

## 📱 Integration Examples

### Example 1: Basic Text Recognition
```dart
import 'package:smacker/services/text_recognition_service.dart';

final service = TextRecognitionService();
final result = await service.processImageFromPath('/path/to/image.jpg');

print('Detected Text: ${result['fullText']}');
print('Waybill ID: ${result['waybillId']}');
print('Barcodes: ${result['barcodes']}');

service.dispose();
```

### Example 2: Custom Pattern Extraction
```dart
final service = TextRecognitionService();
final result = await service.processImageFile(imageFile);

// Define custom patterns
final patterns = {
  'phone': RegExp(r'\d{3}-\d{3}-\d{4}'),
  'email': RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w{2,4}\b'),
  'date': RegExp(r'\d{2}/\d{2}/\d{4}'),
};

final customData = service.extractCustomData(
  result['fullText'],
  patterns,
);

print('Phone: ${customData['phone']}');
print('Email: ${customData['email']}');
print('Date: ${customData['date']}');
```

### Example 3: Real-time Text Detection (Advanced)
```dart
// In your camera screen
CameraController? _cameraController;
TextRecognitionService? _textRecognitionService;

@override
void initState() {
  super.initState();
  _textRecognitionService = TextRecognitionService();
  _initializeCamera();
}

Future<void> _startImageStream() async {
  await _cameraController!.startImageStream((CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    
    try {
      // Convert CameraImage to InputImage
      final inputImage = TFLiteProcessor.convertCameraImageToInputImage(
        image,
        _cameras![0],
        0, // sensor orientation
      );
      
      // Process with ML Kit (implement in service)
      // final result = await _textRecognitionService.processInputImage(inputImage);
      
    } catch (e) {
      print('Error: $e');
    } finally {
      _isProcessing = false;
    }
  });
}
```

## 🔧 Configuration

### Android Configuration
Already configured in your `android/app/build.gradle.kts`:
```kotlin
minSdk = 21  // ML Kit requires API level 21+
```

### iOS Configuration
Ensure camera permissions in `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to scan parcels</string>
```

## 🎯 Waybill ID Detection Patterns

The service automatically detects:

1. **Waybill Pattern**: `WB` followed by 6+ alphanumeric characters
   - Examples: `WB123456789`, `WBTEST001`

2. **Tracking Numbers**: 2 letters + 9+ digits
   - Examples: `AB123456789`, `XY987654321`

3. **Generic Barcodes**: 
   - EAN/UPC: 12-14 digits
   - Custom: 10-20 alphanumeric characters

## 📊 Response Structure

```dart
{
  'fullText': 'Complete recognized text...',
  'waybillId': 'WB123456789',
  'barcodes': ['WB123456789', '1234567890123'],
  'blocks': [
    {
      'text': 'Block text',
      'boundingBox': {'left': 10.0, 'top': 20.0, 'right': 100.0, 'bottom': 50.0},
      'lines': [
        {
          'text': 'Line text',
          'boundingBox': {...}
        }
      ]
    }
  ],
  'lines': ['Line 1', 'Line 2', 'Line 3'],
  'blockCount': 3
}
```

## 🎨 UI Components

### Camera Preview with Overlay
```dart
Stack(
  children: [
    // Camera preview
    CameraPreview(_cameraController!),
    
    // Scanning frame overlay
    CustomPaint(
      painter: ScanFramePainter(),
    ),
    
    // Results display
    Positioned(
      bottom: 0,
      child: ResultsPanel(recognizedText: _recognizedText),
    ),
  ],
)
```

## 🐛 Troubleshooting

### Issue: Camera not initializing
**Solution:** Check permissions in AndroidManifest.xml and Info.plist

### Issue: Text not recognized
**Solutions:**
- Ensure good lighting
- Hold camera steady
- Keep text in focus
- Use high resolution preset

### Issue: Slow processing
**Solutions:**
- Lower camera resolution
- Add debouncing for real-time detection
- Process fewer frames per second

## 📈 Performance Tips

1. **Dispose resources properly:**
   ```dart
   @override
   void dispose() {
     _textRecognitionService?.dispose();
     _cameraController?.dispose();
     super.dispose();
   }
   ```

2. **Use appropriate resolution:**
   ```dart
   CameraController(
     camera,
     ResolutionPreset.medium, // Lower = faster
   );
   ```

3. **Debounce real-time processing:**
   ```dart
   Timer? _debounce;
   
   void _onImageStream(CameraImage image) {
     if (_debounce?.isActive ?? false) _debounce!.cancel();
     _debounce = Timer(Duration(milliseconds: 500), () {
       // Process image
     });
   }
   ```

## 🔗 Navigation

Add buttons to access text recognition:

```dart
// In your home screen or settings
ElevatedButton(
  onPressed: () {
    Navigator.pushNamed(context, '/text_recognition');
  },
  child: Text('Scan Text/Barcode'),
)
```

## 📚 Additional Resources

- [Google ML Kit Docs](https://developers.google.com/ml-kit/vision/text-recognition)
- [Camera Plugin Docs](https://pub.dev/packages/camera)
- [Flutter Image Picker](https://pub.dev/packages/image_picker)

## ✨ Next Steps

1. Test the text recognition screen
2. Integrate with your existing scan workflow
3. Add custom patterns for your specific waybill format
4. Implement real-time detection if needed
5. Add more robust error handling
6. Consider adding barcode scanning alongside text recognition

## 🎯 Current Implementation in ScanScreen

Your `scan_screen.dart` already uses text recognition:

```dart
// In _captureAndLog method
final ocrResult = await TFLiteProcessor.extractBarcodeIdAndOcr(image);
final waybillId = ocrResult['waybillId'] ?? '';
final waybillDetails = ocrResult['waybillDetails'] ?? '';
```

This is now powered by the improved `TextRecognitionService`!
