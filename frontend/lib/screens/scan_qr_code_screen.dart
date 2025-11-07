import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scan QR Code screen that returns the parsed locker ID when a QR is detected.
/// Expected QR format: starts with the locker id (e.g. "LOCKER123"), optionally followed
/// by additional text. This screen extracts the leading token and returns it.
class ScanQrCodeScreen extends StatefulWidget {
  const ScanQrCodeScreen({super.key});

  @override
  State<ScanQrCodeScreen> createState() => _ScanQrCodeScreenState();
}

class _ScanQrCodeScreenState extends State<ScanQrCodeScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // TEMPORARY: Auto-return placeholder locker ID after a short delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop('LOCKER_${DateTime.now().millisecondsSinceEpoch}');
      }
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  /// Parse the raw QR content to extract the locker id.
  /// Strategy:
  /// 1. Trim the raw string.
  /// 2. Try to grab a leading token matching common id characters.
  /// 3. Fallback: split on whitespace/parenthesis/newline and take first token.
  String _parseLockerId(String raw) {
    final s = raw.trim();

    // Try a conservative regex that matches a leading alphanumeric/underscore/hyphen token
    final match = RegExp(r'^[A-Za-z0-9_\-]+').firstMatch(s);
    if (match != null) return match.group(0)!;

    // Fallback: split by whitespace and punctuation often used after an ID
    final parts = s.split(RegExp(r'[\s\n(),;:]+'));
    return parts.isNotEmpty ? parts.first : s;
  }

  void _onDetect(BarcodeCapture capture) async {
    // Prevent re-entrancy while handling a detection
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final lockerId = _parseLockerId(raw);

      if (lockerId.isNotEmpty) {
        // Stop scanner to avoid duplicate detections
        try {
          await _cameraController.stop();
        } catch (_) {
          // ignore controller errors
        }

        // Return the parsed locker id to the caller
        if (mounted) Navigator.of(context).pop(lockerId);
        return;
      }
    } catch (e) {
      debugPrint('Error parsing QR: $e');
    }

    // allow scanning again if parsing failed
    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Scan QR Code', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF5B9BFF),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Camera preview area
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // MobileScanner provides camera preview and detection
                MobileScanner(
                  controller: _cameraController,
                  onDetect: _onDetect,
                ),

                // Scanning frame overlay
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                // Processing indicator
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom section with instructions and buttons
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isProcessing
                        ? 'Processing...'
                        : 'Position the camera to the QR code displayed in the\nLCD Touch Screen to unlock the Locker Door',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Start Scanning button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing
                          ? null
                          : () {
                              // Optionally restart camera or provide feedback
                              setState(() {});
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B9BFF),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      child: const Text(
                        'Start Scanning',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await _cameraController.stop();
                        } catch (_) {}
                        if (mounted) Navigator.of(context).pop(null);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
