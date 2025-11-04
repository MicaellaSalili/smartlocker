import 'package:flutter/material.dart';
import 'live_screen.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF4285F4),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: const Text(
                'Scan Package',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 40),
            
            // Scanning frame
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    // Corner brackets
                    Positioned(
                      top: 60,
                      left: 60,
                      child: _buildCorner(top: true, left: true),
                    ),
                    Positioned(
                      top: 60,
                      right: 60,
                      child: _buildCorner(top: true, left: false),
                    ),
                    Positioned(
                      bottom: 60,
                      left: 60,
                      child: _buildCorner(top: false, left: true),
                    ),
                    Positioned(
                      bottom: 60,
                      right: 60,
                      child: _buildCorner(top: false, left: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Instruction text
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Position the barcode or QR code within the frame to scan the package',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(),
            
            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Simulate scan success and show a pop-up (dialog)
                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  border: Border.all(color: Colors.green),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: const [
                                    Icon(Icons.check_circle, size: 64, color: Colors.green),
                                    SizedBox(height: 8),
                                    Text('Package Scanned Successfully', style: TextStyle(fontWeight: FontWeight.bold)),
                                    SizedBox(height: 8),
                                    Text('Package scanned and verified. You may capture a photo for placement evidence.', textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop(); // close dialog
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const LiveScreen()),
                                  );
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                                  child: Text('Proceed to Live Detection'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Start Scanning',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorner({required bool top, required bool left}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: Colors.grey, width: 3) : BorderSide.none,
          bottom: !top ? const BorderSide(color: Colors.grey, width: 3) : BorderSide.none,
          left: left ? const BorderSide(color: Colors.grey, width: 3) : BorderSide.none,
          right: !left ? const BorderSide(color: Colors.grey, width: 3) : BorderSide.none,
        ),
      ),
    );
  }
}
