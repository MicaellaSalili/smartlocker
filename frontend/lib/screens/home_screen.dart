import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'input_details_screen.dart';
import 'scan_qr_code_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'alerts_screen.dart';
import '../models/user_data.dart';
import '../services/api_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Carousel data for the smart locker guide steps.
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _steps = [
    {
      'image': 'assets/steps/step1.jpg',
      'title': '1. Input User Info',
      'subtitle': 'Courier will input user information for verification',
    },
    {
      'image': 'assets/steps/step2.jpg',
      'title': '2. Scan Parcel',
      'subtitle': 'Scan the parcel barcode to register it in the system',
    },
    {
      'image': 'assets/steps/step3.jpg',
      'title': '3. Proceed Verification',
      'subtitle': 'Process verification and assign locker',
    },
    {
      'image': 'assets/steps/step4.jpg',
      'title': '4. Capture detection',
      'subtitle': 'Device captures image for security purposes',
    },
  ];

  Widget _getCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return const ProfileScreen();
      case 2:
        return const AlertsScreen();
      case 3:
        return const SettingsScreen();
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Smart Locker Guide title
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            'Smart Locker Guide',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_steps.length, (index) {
            final bool active = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF5B9BFF)
                    : const Color(0xFFBDBDBD),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
        const SizedBox(height: 16),

        // Carousel
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6E9FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            // Image section - takes most of the space
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFD6E9FF),
                                    ),
                                    child: Image.asset(
                                      step['image']!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (c, e, s) => Container(
                                        color: Colors.white,
                                        child: const Center(
                                          child: Icon(
                                            Icons.image,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Bottom white card - compact
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      step['title']!,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2C3E50),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      height: 1,
                                      width: double.infinity,
                                      color: const Color(0xFFE0E0E0),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      step['subtitle']!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Step counter
              Padding(
                padding: const EdgeInsets.only(
                  bottom: 80.0,
                ), // Add padding to avoid FAB overlap
                child: Text(
                  'Step ${_currentPage + 1}/${_steps.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onScanPressed() async {
    // Navigate to QR scanner screen
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanQrCodeScreen()),
    );

    // If a locker ID was scanned, send unlock command and show success dialog
    if (result != null && result is String) {
      final lockerId = result;
      
      // 🔓 Send unlock command to ESP32 via backend
      await _sendUnlockCommand(lockerId);
      
      // Show success dialog then proceed to input details
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
                    const Text('Locker Unlocked Successfully', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                    const SizedBox(height: 12),
                    Text('Locker ID: $lockerId', style: TextStyle(color: Colors.green.shade700)),
                    const SizedBox(height: 8),
                    Text('Door will unlock for 5 seconds', style: TextStyle(color: Colors.green.shade600, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => InputDetailsScreen(lockerId: lockerId)),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                  child: Text('Proceed to Input Recipient Details'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Send unlock command to backend after QR scan
  Future<void> _sendUnlockCommand(String lockerId) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/locker/$lockerId/unlock');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Unlock command sent successfully to $lockerId');
      } else {
        debugPrint('⚠️ Failed to send unlock command. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error sending unlock command: $e');
    }
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final bool isActive = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive ? const Color(0xFF5B9BFF) : const Color(0xFF9CA3AF),
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF5B9BFF)
                  : const Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Make the top area mimic the rounded blue header from the design
      // Hide the AppBar when on Profile (index 1), Alerts (index 2), or Settings (index 3) tabs since they have their own headers
      appBar: _currentIndex == 1 || _currentIndex == 2 || _currentIndex == 3
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(150),
              child: AppBar(
                automaticallyImplyLeading: false,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF5B9BFF),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 20.0,
                        ),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(fontSize: 26, height: 1.3),
                            children: [
                              const TextSpan(
                                text: 'Welcome back,\n',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              TextSpan(
                                text: UserData.firstName.isEmpty
                                    ? 'User!'
                                    : '${UserData.firstName}!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
            ),
      body: _getCurrentPage(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomAppBar(
          elevation: 0,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: SizedBox(
            height: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Home
                _buildNavItem(Icons.home, 'Home', 0),
                // Profile
                _buildNavItem(Icons.person_outline, 'Profile', 1),
                const SizedBox(width: 48), // space for the FAB
                // Alerts
                _buildNavItem(Icons.notifications_outlined, 'Alerts', 2),
                // Settings
                _buildNavItem(Icons.settings_outlined, 'Settings', 3),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF3D5A80),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _onScanPressed,
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: const Icon(
              Icons.qr_code_scanner,
              size: 28,
              color: Colors.white,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
