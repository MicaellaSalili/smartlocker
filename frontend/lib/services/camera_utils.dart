import 'dart:typed_data';
import 'package:camera/camera.dart';

/// Convert CameraImage (YUV420) to row-major RGB888 bytes.
Uint8List convertYUV420ToRgb(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final uvRowStride = image.planes[1].bytesPerRow;
  final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

  final imageBytes = Uint8List(width * height * 3);
  int index = 0;

  final yBuffer = image.planes[0].bytes;
  final uBuffer = image.planes[1].bytes;
  final vBuffer = image.planes[2].bytes;

  for (int y = 0; y < height; y++) {
    final uvRow = (y >> 1) * uvRowStride;
    for (int x = 0; x < width; x++) {
      final yIndex = y * image.planes[0].bytesPerRow + x;
      final uvIndex = uvRow + (x >> 1) * uvPixelStride;

      final yp = yBuffer[yIndex];
      final up = uBuffer[uvIndex];
      final vp = vBuffer[uvIndex];

      final yv = yp & 0xff;
      final u = up & 0xff;
      final v = vp & 0xff;

      int r = (yv + (1.370705 * (v - 128))).toInt();
      int g = (yv - (0.337633 * (u - 128)) - (0.698001 * (v - 128))).toInt();
      int b = (yv + (1.732446 * (u - 128))).toInt();

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      imageBytes[index++] = r;
      imageBytes[index++] = g;
      imageBytes[index++] = b;
    }
  }
  return imageBytes;
}
