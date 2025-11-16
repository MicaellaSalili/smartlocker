# Quick Start: Text Recognition Integration

## ✅ What Was Added

### 1. New Files Created
- `lib/screens/text_recognition_screen.dart` - Standalone text recognition screen
- `lib/services/text_recognition_service.dart` - Reusable text recognition service
- `lib/widgets/text_recognition_button.dart` - UI component for navigation
- `TEXT_RECOGNITION_GUIDE.md` - Complete documentation

### 2. Files Updated
- `lib/services/tflite_processor.dart` - Improved ML Kit integration
- `lib/main.dart` - Added `/text_recognition` route

## 🚀 How to Use

### Option 1: Use the Standalone Screen
Navigate to the text recognition screen from anywhere in your app:

```dart
Navigator.pushNamed(context, '/text_recognition');
```

### Option 2: Use the Service Directly
Use the text recognition service in your own screens:

```dart
import 'package:smacker/services/text_recognition_service.dart';

final service = TextRecognitionService();
final result = await service.processImageFile(imageFile);

String text = result['fullText'];
String waybillId = result['waybillId'];
List<String> barcodes = result['barcodes'];

service.dispose();
```

### Option 3: Already Integrated in ScanScreen
Your existing `scan_screen.dart` already uses the improved text recognition:

```dart
// This now uses the enhanced service
final ocrResult = await TFLiteProcessor.extractBarcodeIdAndOcr(image);
```

## 📱 Testing the Integration

### Test the Standalone Screen:

1. **Run your Flutter app:**
   ```bash
   cd frontend
   flutter run
   ```

2. **Add a test button** to your home screen or settings:
   ```dart
   ElevatedButton(
     onPressed: () {
       Navigator.pushNamed(context, '/text_recognition');
     },
     child: const Text('Test Text Recognition'),
   )
   ```

3. **Or use the provided widget:**
   ```dart
   import 'package:smacker/widgets/text_recognition_button.dart';
   
   // Add to your screen
   TextRecognitionButton()
   ```

### Test with Sample Images:

**Good test scenarios:**
- Printed waybill labels
- Shipping labels with barcodes
- Text documents
- Product labels

**Tips for best results:**
- Ensure good lighting
- Hold camera steady
- Keep text in focus
- Try different angles if text isn't detected

## 🔍 What Gets Detected

The system automatically extracts:

1. **Waybill IDs**: Patterns like `WB123456789`
2. **Tracking Numbers**: `AB123456789` format
3. **Barcodes**: EAN, UPC, and custom formats
4. **All Text**: Complete text from the image
5. **Text Blocks**: Organized text with positions

## 🎯 Example Output

When you scan a parcel label, you'll get:

```json
{
  "fullText": "WAYBILL\nWB987654321\nRecipient: John Doe\nAddress: 123 Main St\nTracking: XY1234567890",
  "waybillId": "WB987654321",
  "barcodes": ["WB987654321", "XY1234567890"],
  "lines": [
    "WAYBILL",
    "WB987654321",
    "Recipient: John Doe",
    ...
  ],
  "blockCount": 3
}
```

## 🎨 UI Features

The text recognition screen includes:
- ✅ Live camera preview
- ✅ Capture button with loading state
- ✅ Recognized text display
- ✅ Copy to clipboard
- ✅ Scrollable results
- ✅ Error handling
- ✅ Clean, professional UI

## 🔧 Customization

### Change Detection Patterns
Edit `lib/services/text_recognition_service.dart`:

```dart
String extractWaybillId(String text) {
  // Add your custom pattern
  final customPattern = RegExp(r'YOUR_PATTERN_HERE');
  final match = customPattern.firstMatch(text);
  return match?.group(0) ?? 'NOT_FOUND';
}
```

### Add Custom Data Extraction
```dart
final customPatterns = {
  'recipientName': RegExp(r'Recipient:\s*(.+)'),
  'address': RegExp(r'Address:\s*(.+)'),
  'phoneNumber': RegExp(r'\d{3}-\d{3}-\d{4}'),
};

final extracted = service.extractCustomData(
  result['fullText'],
  customPatterns,
);
```

### Modify UI Colors
Edit `lib/screens/text_recognition_screen.dart`:

```dart
backgroundColor: const Color(0xFF4285F4), // Change to your brand color
```

## 📊 Performance Optimization

For better performance:

1. **Use lower resolution if needed:**
   ```dart
   ResolutionPreset.medium // Instead of .high
   ```

2. **Add debouncing for real-time:**
   ```dart
   Timer? _debounce;
   // Debounce processing to avoid overload
   ```

3. **Dispose resources properly:**
   ```dart
   @override
   void dispose() {
     service.dispose();
     super.dispose();
   }
   ```

## 🐛 Troubleshooting

### Camera Not Working
- Check permissions in `AndroidManifest.xml`
- Verify iOS permissions in `Info.plist`
- Test on real device (emulator camera may not work)

### Text Not Detected
- Improve lighting conditions
- Hold camera closer/farther
- Ensure text is in focus
- Try with clearer text samples

### Slow Performance
- Lower camera resolution
- Test on physical device
- Reduce processing frequency

## 📚 Next Steps

1. ✅ Test the text recognition screen
2. ✅ Integrate button in your UI
3. ✅ Test with real parcel labels
4. ✅ Customize patterns if needed
5. ✅ Add error handling for edge cases
6. ✅ Consider adding real-time detection

## 🎉 You're Ready!

The Google ML Kit text recognition is now fully integrated with your camera system. You can:
- Use the standalone screen for testing
- Use the service in your existing flows
- Customize patterns for your needs
- Extend functionality as needed

For detailed documentation, see `TEXT_RECOGNITION_GUIDE.md`.

---

**Need Help?**
- Check the comprehensive guide: `TEXT_RECOGNITION_GUIDE.md`
- Review example code in `text_recognition_screen.dart`
- Test with the provided widget: `text_recognition_button.dart`
