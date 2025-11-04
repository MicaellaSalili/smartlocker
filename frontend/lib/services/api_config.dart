import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    const port = 3000;
    if (kIsWeb) {
      return 'http://localhost:$port';
    }
    if (Platform.isAndroid) {
      // Android emulator can't access 127.0.0.1 on host; use special alias
      return 'http://10.0.2.2:$port';
    }
    // iOS simulator, Windows/macOS/Linux desktop, physical devices on same LAN may need host IP
    return 'http://127.0.0.1:$port';
  }
}
