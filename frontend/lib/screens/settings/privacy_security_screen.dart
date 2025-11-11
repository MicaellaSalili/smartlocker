import 'package:flutter/material.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Privacy and Security',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Privacy and Security',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4285F4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'All user data is protected with industry-standard encryption protocols, both during transmission and while stored on our servers.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'We enforce strict access controls. Locker and parcel information is accessible only to verified couriers and designated recipients for the express purpose of service fulfillment.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your personal information is confidential. We do not sell, rent, or trade your data with any third parties for marketing or advertising purposes.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'All system activities, including transactions and access logs, are actively monitored to detect and prevent unauthorized access and ensure platform integrity.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'For any inquiries regarding your data privacy or to exercise your data rights, please contact our support team via the "Help & Support" center.',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
