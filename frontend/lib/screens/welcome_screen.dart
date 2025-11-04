import 'package:flutter/material.dart';
import '../widgets/top_pill_header.dart';

// navigation uses named routes

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TopPillHeader('Welcome to ----'),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Image.asset('assets/logo.png', width: 140, height: 140),
                const SizedBox(height: 8),
                const Text('Smart Locker System', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  icon: const Icon(Icons.person),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.0),
                    child: Text('Login to your account'),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    side: const BorderSide(color: Colors.grey),
                    foregroundColor: Colors.black87,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/signup_personal'),
                  icon: const Icon(Icons.person_add),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.0),
                    child: Text('Create an account'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Need help? '),
                  TextButton(onPressed: () {}, child: const Text('Contact Support', style: TextStyle(color: Colors.blue)))
                ]),
                const SizedBox(height: 8),
                Center(child: TextButton(onPressed: () {}, child: const Text('Terms and Conditions', style: TextStyle(color: Colors.grey)))),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
