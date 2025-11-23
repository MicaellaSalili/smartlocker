// NOTE: The original `yolo_detector.dart` prototype required `tflite_flutter_helper`.
// That package caused dependency conflicts in the workspace. To keep analysis and
// builds stable while you decide which inference path to use, this file provides
// a small disabled placeholder implementation with the same public symbols.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
// Camera import not required by the disabled placeholder implementation.

/// Minimal detection result placeholder
class DetectionResult {
  final double x1, y1, x2, y2;
  final String label;
  final double score;
  DetectionResult(this.x1, this.y1, this.x2, this.y2, this.label, this.score);
  Map<String, dynamic> toMap() => {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'label': label, 'score': score};
}

/// Message passed to the isolate (placeholder)
class DetectorIsolateMessage {
  final Uint8List rgbBytes;
  final int width;
  final int height;
  final SendPort replyTo;
  DetectorIsolateMessage(this.rgbBytes, this.width, this.height, this.replyTo);
}

/// Placeholder YoloFlutter implementation that throws if used. This keeps the
/// file present for reference while avoiding analyzer errors until you choose
/// to re-enable the full implementation with matching package versions.
class YoloFlutter {
  Future<void> loadModel({required String modelPath, required String labelsPath}) async {
    throw UnimplementedError('YoloFlutter is disabled. Re-enable the full implementation when ready.');
  }

  Uint8List preprocessFromRgb(Uint8List rgbBytes, int width, int height) {
    throw UnimplementedError('YoloFlutter is disabled.');
  }

  List<DetectionResult> runInference(dynamic input) {
    throw UnimplementedError('YoloFlutter is disabled.');
  }
}

void yoloIsolateEntry(SendPort initialReplyTo) async {
  // This isolate entry intentionally does nothing. It exists so other parts
  // of the app that reference `yoloIsolateEntry` continue to compile.
  final port = ReceivePort();
  initialReplyTo.send(port.sendPort);
  await for (final _ in port) {
    // ignore messages
  }
}

// convertYUV420ToRgb moved to `camera_utils.dart` to avoid duplicate definitions.
