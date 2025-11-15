import 'package:flutter/material.dart';

/// Example widget showing how to add Text Recognition button to your screens
class TextRecognitionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;

  const TextRecognitionButton({
    super.key,
    this.onPressed,
    this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onPressed ?? () {
          Navigator.pushNamed(context, '/text_recognition');
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(
                icon ?? Icons.text_fields,
                size: 32,
                color: const Color(0xFF4285F4),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? 'Text Recognition',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Scan text from parcel labels',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Example: Add this to your settings or home screen
/// 
/// Usage:
/// ```dart
/// TextRecognitionButton(
///   label: 'Scan Waybill',
///   icon: Icons.qr_code_scanner,
///   onPressed: () {
///     Navigator.pushNamed(context, '/text_recognition');
///   },
/// )
/// ```
