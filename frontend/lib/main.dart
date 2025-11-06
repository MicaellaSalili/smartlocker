import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/input_details_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/live_screen.dart';
import 'screens/signup/registration_screen.dart';
import 'services/transaction_manager.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => TransactionManager(),
      child: MaterialApp(
        title: 'Smart Locker System',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
        ),
        initialRoute: '/welcome',
        routes: {
          '/welcome': (context) => const WelcomeScreen(),
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
          '/input_details': (context) => const InputDetailsScreen(),
          '/scan': (context) => const ScanScreen(),
          '/live': (context) => const LiveScreen(),
          '/signup_personal': (context) => const RegistrationScreen(),
        },
      ),
    );
  }
}
