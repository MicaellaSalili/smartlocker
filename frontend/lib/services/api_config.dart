import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    const port = 3000;
    
    if (kIsWeb) {
      // Web: Use localhost
      return 'http://localhost:$port';
    }
    
    if (Platform.isAndroid) {
      // Android emulator: Use special alias for host machine
      // CHANGE THIS to your actual IP (e.g., 'http://192.168.1.5:$port') if using physical device
      return 'http://10.0.2.2:$port';
    }
    
    if (Platform.isIOS) {
      // iOS simulator can use localhost, physical device needs actual IP
      // CHANGE THIS to your actual IP (e.g., 'http://192.168.1.5:$port') if using physical device
      return 'http://127.0.0.1:$port';
    }
    
    // Desktop platforms (Windows/macOS/Linux)
    return 'http://127.0.0.1:$port';
  }
}
