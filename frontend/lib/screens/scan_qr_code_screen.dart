import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/api_config.dart';
import '../services/transaction_manager.dart';
import 'scan_screen.dart';

/// Scan QR Code screen that validates token and locker ID.
/// Expected QR format: LOCKER_ID:TOKEN_xxx:EXP_timestamp
class ScanQrCodeScreen extends StatefulWidget {
  final String? expectedLockerId;
  final String? expectedToken;

  const ScanQrCodeScreen({
    super.key,
    this.expectedLockerId,
    this.expectedToken,
  });

  @override
  State<ScanQrCodeScreen> createState() => _ScanQrCodeScreenState();
}

class _ScanQrCodeScreenState extends State<ScanQrCodeScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Remove auto-return placeholder - now we actually scan QR codes
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  /// Parse QR content and validate token
  /// Expected format: LOCKER_ID:TOKEN_xxx:EXP_timestamp
  Future<Map<String, dynamic>> _parseAndValidateQR(String raw) async {
    final s = raw.trim();

    // Debug: Print what we received
    debugPrint('🔍 Raw QR Content: "$s"');
    debugPrint('🔍 Length: ${s.length}');
    debugPrint('🔍 Characters: ${s.codeUnits}');

    // Split by colon
    final parts = s.split(':');
    debugPrint('🔍 Parts count: ${parts.length}');
    debugPrint('🔍 Parts: $parts');

    if (parts.length < 3) {
      return {
        'valid': false,
        'error':
            'Invalid QR format. Expected: LOCKER_ID:TOKEN_xxx:EXP_timestamp\nReceived: $s',
      };
    }

    final lockerId = parts[0].trim();
    final tokenPart = parts[1].trim(); // Should be "TOKEN_xxx"
    final expPart = parts[2].trim(); // Should be "EXP_timestamp"

    debugPrint('🔍 Locker ID: "$lockerId"');
    debugPrint('🔍 Token Part: "$tokenPart"');
    debugPrint('🔍 Exp Part: "$expPart"');

    // Extract token (remove "TOKEN_" prefix)
    if (!tokenPart.startsWith('TOKEN_')) {
      return {
        'valid': false,
        'error':
            'Invalid token format. Expected: TOKEN_xxx\nReceived: $tokenPart',
      };
    }
    final token = tokenPart.substring(6);

    // Extract expiration (remove "EXP_" prefix)
    if (!expPart.startsWith('EXP_')) {
      return {
        'valid': false,
        'error':
            'Invalid expiration format. Expected: EXP_timestamp\nReceived: $expPart',
      };
    }
    final expTimestamp = int.tryParse(expPart.substring(4));
    if (expTimestamp == null) {
      return {
        'valid': false,
        'error': 'Invalid expiration timestamp: ${expPart.substring(4)}',
      };
    }

    debugPrint('🔍 Parsed Token: "$token"');
    debugPrint('🔍 Parsed Timestamp: $expTimestamp');
    debugPrint('🔍 Expected Locker: ${widget.expectedLockerId}');
    debugPrint('🔍 Expected Token: ${widget.expectedToken}');

    // Check if token expired
    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint('🔍 Now: $now, Expires: $expTimestamp');
    if (now > expTimestamp) {
      return {'valid': false, 'error': 'QR code has expired'};
    }

    // Validate locker ID matches expected (if provided)
    if (widget.expectedLockerId != null &&
        lockerId != widget.expectedLockerId) {
      return {
        'valid': false,
        'error':
            'Locker ID mismatch\nExpected: ${widget.expectedLockerId}\nReceived: $lockerId',
      };
    }

    // Validate token matches expected (if provided)
    if (widget.expectedToken != null && token != widget.expectedToken) {
      return {
        'valid': false,
        'error':
            'Invalid token\nExpected: ${widget.expectedToken}\nReceived: $token',
      };
    }

    debugPrint('✅ QR validation passed!');

    return {'valid': true, 'lockerId': lockerId, 'token': token};
  }

  /// Send unlock command with token to backend
  Future<bool> _sendUnlockCommand(String lockerId, String token) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/locker/$lockerId/unlock');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'token': token}),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Unlock command sent successfully');
        return true;
      } else {
        final errorData = json.decode(response.body);
        debugPrint('⚠️ Unlock failed: ${errorData['error']}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sending unlock command: $e');
      return false;
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      // Parse and validate QR code
      final validation = await _parseAndValidateQR(raw);

      if (validation['valid'] == true) {
        final lockerId = validation['lockerId'];
        final token = validation['token'];

        // Stop scanner
        try {
          await _cameraController.stop();
        } catch (_) {}

        // Send unlock command
        final unlocked = await _sendUnlockCommand(lockerId, token);

        if (unlocked && mounted) {
          // Show success and navigate to scan screen
          await _showSuccessDialog(lockerId);
        } else if (mounted) {
          // Show error and allow retry
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to unlock locker. Please try again.'),
            ),
          );
          setState(() => _isProcessing = false);
        }
      } else {
        // Show validation error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(validation['error'] ?? 'Invalid QR code')),
          );
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      debugPrint('Error processing QR: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _showSuccessDialog(String lockerId) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, size: 64, color: Colors.green),
                  const SizedBox(height: 12),
                  const Text(
                    'Locker Unlocked Successfully',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Locker ID: $lockerId',
                    style: TextStyle(color: Colors.green.shade700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Door is now unlocked. Place package inside.',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();

                // Store locker ID in TransactionManager for later use
                final transactionManager = Provider.of<TransactionManager>(
                  context,
                  listen: false,
                );
                transactionManager.setLockerId(lockerId);
                debugPrint('🔒 Stored locker ID: $lockerId');

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanScreen(lockerId: lockerId),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                child: Text('Proceed to Package Scanning'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white),
        ),
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
              decoration: const BoxDecoration(color: Colors.white),
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
