import 'package:flutter/material.dart';
import 'home_screen.dart';

class ViewTransactionScreen extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const ViewTransactionScreen({super.key, required this.transaction});

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '2025-10-27 10:30:00';
    String year = timestamp.year.toString();
    String month = timestamp.month.toString().padLeft(2, '0');
    String day = timestamp.day.toString().padLeft(2, '0');
    String hour = timestamp.hour.toString().padLeft(2, '0');
    String minute = timestamp.minute.toString().padLeft(2, '0');
    String second = timestamp.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final String statusRaw = (transaction['status'] ?? 'Delivered').toString();
    final String statusLower = statusRaw.toLowerCase();
    Color headerColor;
    if (statusLower == 'delivered') {
      headerColor = const Color(0xFF5B9BFF); // blue
    } else if (statusLower == 'claimed') {
      headerColor = Colors.green; // claimed -> green
    } else if (statusLower == 'failed') {
      headerColor = Colors.red; // failed -> red
    } else {
      headerColor = const Color(0xFF5B9BFF);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: headerColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Navigate to home screen instead of pop since we cleared the stack
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          },
        ),
        title: const Text(
          'Transaction Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),

          // Status Badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusRaw,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Transaction and Locker Info
                  _buildInfoSection('TRANSACTION AND LOCKER INFO', [
                    'Transaction ID: ${transaction['id'] ?? 'N/A'}',
                    'Locker ID: ${transaction['locker'] ?? 'N/A'}',
                    'Status: ${transaction['status'] ?? 'N/A'}',
                    'TIMESTAMP: ${_formatTimestamp(transaction['timestamp'])}',
                  ]),
                  const SizedBox(height: 16),

                  // Recipient and Parcel Info (from Step 1)
                  _buildInfoSection('RECIPIENT INFO (Step 1: Input Details)', [
                    'Recipient: ${transaction['recipient'] ?? 'N/A'}',
                    'Contact Number: ${transaction['phone'] ?? 'N/A'}',
                    'Entry Method: Manual Input by Courier',
                  ]),
                  const SizedBox(height: 16),

                  // QR Code and Locker Assignment (from Step 2)
                  _buildInfoSection('LOCKER ASSIGNMENT (Step 2: QR Scan)', [
                    'QR Code Scanned: ${transaction['qr_scanned'] ?? 'Yes'}',
                    'Locker Unlocked: ${transaction['locker'] ?? 'N/A'}',
                    'Access Method: Token Validation',
                  ]),
                  const SizedBox(height: 16),

                  // Package Scan Info (from Step 3)
                  _buildInfoSection('PACKAGE SCAN (Step 3: Waybill Scan)', [
                    'Waybill ID: ${transaction['waybill_id'] ?? 'N/A'}',
                    'Package Details: ${transaction['package_details'] ?? 'Scanned and logged'}',
                    'Image Embedding: Generated for verification',
                  ]),
                  const SizedBox(height: 8),

                  // Waybill Info
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8, bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Additional Waybill Information',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildWaybillDetailsWidget(
                          transaction['waybill_details'] ??
                              'Waybill information extracted from scan',
                        ),
                      ],
                    ),
                  ),

                  // Live Verification (from Step 4)
                  _buildInfoSection('LIVE VERIFICATION (Step 4: Final Check)', [
                    'Live Scan: Completed',
                    'Package Match: ${transaction['verification_status'] ?? 'Verified'}',
                    'Door Status: Locked after verification',
                  ]),

                  // Divider
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE0E0E0),
                  ),
                  const SizedBox(height: 16),

                  // Timeline and History
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'TIMELINE AND HISTORY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        _buildTimelineRow(
                          'Step 1 - Recipient Details Input:',
                          _extractTime(1),
                        ),
                        const SizedBox(height: 6),
                        _buildTimelineRow(
                          'Step 2 - QR Code Scan & Door Unlock:',
                          _extractTime(2),
                        ),
                        const SizedBox(height: 6),
                        _buildTimelineRow(
                          'Step 3 - Package Waybill Scan:',
                          _extractTime(3),
                        ),
                        const SizedBox(height: 6),
                        _buildTimelineRow(
                          'Step 4 - Live Verification & Lock:',
                          _extractTime(4),
                        ),
                        const SizedBox(height: 6),
                        _buildTimelineRow(
                          'Transaction Complete:',
                          _formatTime(transaction['timestamp']),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Divider
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE0E0E0),
                  ),
                  const SizedBox(height: 16),

                  // Proof of Delivery
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'PROOF OF DELIVERY',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'JPG',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'MP4',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // Report issue functionality
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5B9BFF),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'REPORT ISSUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // Share receipt functionality
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE0E0E0),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'SHARE RECEIPT',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<String> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              letterSpacing: 0.3,
            ),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineRow(String label, String time) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(time, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }

  String _extractTime(int step) {
    // Extract time based on step number from transaction data
    // For now, return placeholder times based on current time
    final now = DateTime.now();
    final baseTime = DateTime(
      now.year,
      now.month,
      now.day,
      10,
      30 + step - 1,
      0,
    );
    return _formatTime(baseTime.millisecondsSinceEpoch);
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'Not available';

    DateTime dateTime;
    if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is String) {
      dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return 'Invalid time';
    }

    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  Widget _buildWaybillDetailsWidget(String waybillDetails) {
    // Parse the waybill details string to extract structured information
    final Map<String, String> details = _parseWaybillDetails(waybillDetails);

    if (details.isEmpty) {
      return Text(
        waybillDetails,
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SCANNED WAYBILL DETAILS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...details.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      '${entry.key}:',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
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

  Map<String, String> _parseWaybillDetails(String waybillDetails) {
    final Map<String, String> details = {};

    // Try to parse structured data (from TextRecognitionService format)
    final lines = waybillDetails.split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // Match patterns like "Order ID: 250127XXXXXX"
      if (line.contains(':')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join(':').trim();
          details[key] = value;
        }
      }
    }

    return details;
  }
}
