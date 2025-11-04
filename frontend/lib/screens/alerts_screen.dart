import 'package:flutter/material.dart';
import 'view_transaction_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String selectedFilter = 'All notifications';

  // All alerts/notifications data
  final List<Map<String, dynamic>> allAlerts = [
    {
      'id': 'Transaction ID: 000000',
      'recipient': 'Recipient: Kaiwen Chen',
      'locker': 'Locker: Smacker 222',
      'status': 'Failed',
      'color': Colors.red,
      'timestamp': DateTime(2025, 11, 1, 9, 45),
      'isUrgent': true,
    },
    {
      'id': 'Transaction ID: 000000',
      'recipient': 'Recipient: Ashanti Villadiego',
      'locker': 'Locker: Smacker 222',
      'status': 'Delivered',
      'color': Colors.blue,
      'timestamp': DateTime(2025, 10, 27, 10, 30),
      'isUrgent': false,
    },
    {
      'id': 'Transaction ID: 000000',
      'recipient': 'Recipient: Kimberly Isip',
      'locker': 'Locker: Smacker 222',
      'status': 'Claimed',
      'color': Colors.green,
      'timestamp': DateTime(2025, 10, 28, 14, 15),
      'isUrgent': false,
    },
  ];

  // Get filtered alerts based on selected filter
  List<Map<String, dynamic>> get filteredAlerts {
    if (selectedFilter == 'Urgent') {
      return allAlerts.where((alert) => alert['isUrgent'] == true).toList();
    }
    return allAlerts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Blue header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF5B9BFF),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: const Text(
              'Alerts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildFilterTab('Urgent'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFilterTab('All notifications'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Alerts List
          Expanded(
            child: filteredAlerts.isEmpty
                ? Center(
                    child: Text(
                      'No ${selectedFilter.toLowerCase()}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredAlerts.length,
                    itemBuilder: (context, index) {
                      final alert = filteredAlerts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildAlertCard(alert),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String text) {
    final bool isSelected = selectedFilter == text;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4285F4) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF4285F4) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert['id'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert['recipient'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert['locker'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: alert['color'],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  alert['status'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewTransactionScreen(
                      transaction: alert,
                    ),
                  ),
                );
              },
              child: const Text(
                'View Details >',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
