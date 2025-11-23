import 'package:flutter/services.dart' show rootBundle;

class ModelLabels {
  static List<String>? _cache;

  /// Loads and caches labels from `assets/models/labels.txt`.
  static Future<List<String>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/models/labels.txt');
    _cache = raw
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return _cache!;
  }

  /// Returns cached labels if loaded previously (or null).
  static List<String>? get cached => _cache;
}