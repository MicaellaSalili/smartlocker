import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';

class TransactionData {
  String firstName;
  String lastName;
  String phoneNumber;

  TransactionData({
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
  });

  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
    };
  }
}

class TransactionManager extends ChangeNotifier {
  // Fetch reference data from backend (embedding, waybillId, waybillDetails)
  Future<bool> getReferenceDataFromBackend(String transactionId) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/transaction/$transactionId/reference',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _embedding = (data['embedding'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList();
        _waybillId = data['waybillId'] as String?;
        _waybillDetails = data['waybillDetails'] as String?;
        notifyListeners();
        return true;
      } else {
        debugPrint(
          'Failed to fetch reference data. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error fetching reference data: $e');
      return false;
    }
  }

  // Finalize transaction by ID (marks as verified)
  Future<bool> finalizeTransactionById(String transactionId) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/transaction/$transactionId/finalize',
      );
      final response = await http.post(url);
      if (response.statusCode == 200) {
        debugPrint('Transaction finalized successfully: $transactionId');
        debugPrint('Response: ${response.body}');
        notifyListeners();
        return true;
      } else {
        debugPrint(
          'Failed to finalize transaction. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error finalizing transaction: $e');
      return false;
    }
  }

  // Delete transaction by ID
  Future<bool> deleteTransactionById(String transactionId) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/transaction/$transactionId',
      );
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        debugPrint('Transaction deleted successfully: $transactionId');
        debugPrint('Response: ${response.body}');
        // Clear local data after successful deletion
        _transactionId = null;
        _lockerId = null;
        _waybillId = null;
        _waybillDetails = null;
        _embedding = null;
        _auditData = null;
        notifyListeners();
        return true;
      } else {
        debugPrint(
          'Failed to delete transaction. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      return false;
    }
  }

  // Lock locker by ID via backend (MQTT)
  Future<bool> lockLockerById(String lockerId) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/locker/$lockerId/lock');
      final response = await http.post(url);
      if (response.statusCode == 200) {
        debugPrint('Locker lock command sent successfully: $lockerId');
        debugPrint('Response: ${response.body}');
        return true;
      } else {
        debugPrint(
          'Failed to send locker lock command. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending locker lock command: $e');
      return false;
    }
  }

  TransactionData? _auditData;
  String? _transactionId; // MongoDB _id
  String? _lockerId;
  String? _waybillId;
  String? _waybillDetails;
  List<double>? _embedding;

  TransactionData? get auditData => _auditData;
  String? get transactionId => _transactionId;
  String? get lockerId => _lockerId;
  String? get waybillId => _waybillId;
  String? get waybillDetails => _waybillDetails;
  List<double>? get embedding => _embedding;

  /// Robust text comparison utility function
  /// Returns true if liveText contains at least 70% of key tokens from referenceText
  /// This allows for minor OCR errors while maintaining verification accuracy
  static bool isTextContentMatch(String liveText, String referenceText) {
    if (referenceText.isEmpty) return true; // Skip check if no reference
    if (liveText.isEmpty) return false; // Fail if live text is empty

    // Normalize texts: lowercase, remove extra whitespace
    final liveNormalized = liveText.toLowerCase().trim();
    final referenceNormalized = referenceText.toLowerCase().trim();

    // Extract key tokens (words/numbers) from reference text
    // Filter out common words and very short tokens
    final referenceTokens = referenceNormalized
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2) // Filter out single characters
        .where((token) => !_isCommonWord(token)) // Filter out common words
        .toSet(); // Use set to get unique tokens

    if (referenceTokens.isEmpty) return true; // No meaningful tokens to compare

    // Count how many reference tokens appear in live text
    int matchCount = 0;
    for (var token in referenceTokens) {
      if (liveNormalized.contains(token)) {
        matchCount++;
      }
    }

    // Calculate match percentage
    final matchPercentage = matchCount / referenceTokens.length;

    debugPrint(
      'Text match: $matchCount/${referenceTokens.length} tokens (${(matchPercentage * 100).toStringAsFixed(1)}%)',
    );

    // Return true if at least 70% of tokens match
    return matchPercentage >= 0.70;
  }

  /// Helper function to filter out common words that don't add verification value
  static bool _isCommonWord(String word) {
    const commonWords = {
      'the',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'a',
      'an',
      'is',
      'was',
      'are',
      'were',
      'be',
      'been',
      'being',
      'this',
      'that',
      'these',
      'those',
      'from',
      'by',
      'as',
      'it',
    };
    return commonWords.contains(word);
  }

  void updateAuditData({
    required String firstName,
    required String lastName,
    required String phoneNumber,
  }) {
    _auditData = TransactionData(
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
    );
    notifyListeners();
  }

  // Set locker ID (called after QR scan)
  void setLockerId(String lockerId) {
    _lockerId = lockerId;
    notifyListeners();
  }

  // Validate all required data is present
  bool isDataComplete() {
    return _auditData != null &&
        _lockerId != null &&
        _waybillId != null &&
        _waybillDetails != null &&
        _embedding != null;
  }

  // Get summary of all collected data for confirmation
  Map<String, dynamic> getTransactionSummary() {
    return {
      'recipient_first_name': _auditData?.firstName ?? '',
      'recipient_last_name': _auditData?.lastName ?? '',
      'recipient_phone': _auditData?.phoneNumber ?? '',
      'locker_id': _lockerId ?? '',
      'waybill_id': _waybillId ?? '',
      'waybill_details': _waybillDetails ?? '',
      'embedding_length': _embedding?.length ?? 0,
      'is_complete': isDataComplete(),
    };
  }

  // Log transaction data with locker ID, waybill info and embedding
  Future<bool> logTransactionData({
      required String lockerId,
      required String waybillId,
      required String waybillDetails,
      required List<double> embedding,
      String? imagePath, // Optional image file path
    }) async {
        bool success = false;
    _lockerId = lockerId;
    _waybillId = waybillId;
    _waybillDetails = waybillDetails;
    _embedding = embedding;

    // 🔍 PRINT STORED DATA IN TRANSACTION MANAGER
    debugPrint('\n${'=' * 60}');
    debugPrint('📦 TRANSACTION MANAGER - STORED DATA AFTER TEXT SCAN:');
    debugPrint('=' * 60);
    debugPrint('✅ Recipient: ${_auditData?.firstName} ${_auditData?.lastName}');
    debugPrint('✅ Phone: ${_auditData?.phoneNumber}');
    debugPrint('✅ Locker ID: $_lockerId');
    debugPrint('✅ Waybill ID: $_waybillId');
    debugPrint('✅ Waybill Details (first 200 chars):');
    debugPrint(
      '   ${_waybillDetails?.substring(0, _waybillDetails!.length > 200 ? 200 : _waybillDetails!.length)}',
    );
    debugPrint('✅ Embedding vector length: ${_embedding?.length}');
    if (imagePath != null) {
      debugPrint('✅ Image saved at: $imagePath');
    }
    debugPrint('=' * 60 + '\n');

    // Validate all required data is present
    if (!isDataComplete()) {
      debugPrint('Error: Incomplete transaction data. Missing:');
      if (_auditData == null) debugPrint('- Audit data (recipient info)');
      if (_lockerId == null) debugPrint('- Locker ID');
      if (_waybillId == null) debugPrint('- Waybill ID');
      if (_waybillDetails == null) debugPrint('- Waybill details');
      if (_embedding == null) debugPrint('- Image embedding');
      return false;
    }

    debugPrint('📋 Transaction Data Summary:');
    debugPrint('Recipient: ${_auditData!.firstName} ${_auditData!.lastName}');
    debugPrint('Phone: ${_auditData!.phoneNumber}');
    debugPrint('Locker: $lockerId');
    debugPrint('Waybill: $waybillId');
    debugPrint('Embedding: ${embedding.length} values');

    // Construct the full JSON payload by merging audit data with reference data

    final payload = {
      // Audit data (recipient information) - match backend field names
      'recipient_first_name': _auditData!.firstName,
      'recipient_last_name': _auditData!.lastName,
      'recipient_phone': _auditData!.phoneNumber,

      // Locker ID
      'locker_id': lockerId,

      // Reference data (waybill and embedding) - match backend field names
      'waybill_id': waybillId,
      'waybill_details': waybillDetails,
      'image_embedding_vector': embedding,

      // Image path (optional)
      if (imagePath != null) 'image_path': imagePath,
    };

    try {
      // Send POST request to /api/parcel/log
      final url = Uri.parse('${ApiConfig.baseUrl}/api/parcel/log');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse response to get transaction_id
        final responseData = json.decode(response.body);
        _transactionId = responseData['transaction_id'];

        debugPrint('Transaction logged successfully: $waybillId');
        debugPrint('Transaction ID: $_transactionId');
        debugPrint('Response: ${response.body}');
        success = true;
      } else {
        debugPrint('Failed to log transaction. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        success = false;
      }
    } catch (e) {
      debugPrint('Error logging transaction: $e');
      success = false;
    }

    notifyListeners();
    return success;
  }

  // Fetch reference data from backend and update local state
  Future<bool> fetchReferenceData() async {
    if (_transactionId == null) {
      debugPrint('No transaction ID available for reference data fetch.');
      return false;
    }
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/transaction/$_transactionId/reference',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _waybillId = data['waybillId'] as String?;
        _waybillDetails = data['waybillDetails'] as String?;
        _embedding = (data['embedding'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList();
        debugPrint(
          'Reference data fetched: Waybill ID: $_waybillId, Embedding length: ${_embedding?.length ?? 0}',
        );
        notifyListeners();
        return true;
      } else {
        debugPrint(
          'Failed to fetch reference data. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error fetching reference data: $e');
      return false;
    }
  }

  // Finalize transaction (mark as claimed) using backend endpoint
  Future<bool> finalizeTransaction() async {
    if (_transactionId == null) {
      debugPrint(
        'Error: Cannot finalize transaction. No transaction ID available.',
      );
      return false;
    }
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/transaction/$_transactionId/finalize',
      );
      final response = await http.post(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Transaction finalized successfully: $_transactionId');
        debugPrint('Response: ${response.body}');
        // Optionally update local status
        notifyListeners();
        return true;
      } else {
        debugPrint(
          'Failed to finalize transaction. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error finalizing transaction: $e');
      return false;
    }
  }

  // Delete/rollback transaction using backend endpoint
  Future<bool> deleteTransaction() async {
    if (_transactionId == null) {
      debugPrint(
        'Error: Cannot delete transaction. No transaction ID available.',
      );
      return false;
    }
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/transaction/$_transactionId',
      );
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Transaction deleted successfully: $_transactionId');
        debugPrint('Response: ${response.body}');
        // Clear local data after successful deletion
        _transactionId = null;
        _lockerId = null;
        _waybillId = null;
        _waybillDetails = null;
        _embedding = null;
        _auditData = null;
        notifyListeners();
        return true;
      } else {
        debugPrint(
          'Failed to delete transaction. Status: ${response.statusCode}',
        );
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      return false;
    }
  }

  // Lock the locker door using backend endpoint
  Future<bool> lockLocker() async {
    if (_lockerId == null) {
      debugPrint('Error: Cannot lock locker. No locker ID available.');
      return false;
    }
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/locker/$_lockerId/lock');
      final response = await http.post(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Locker locked successfully: $_lockerId');
        debugPrint('Response: ${response.body}');
        return true;
      } else {
        debugPrint('Failed to lock locker. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error locking locker: $e');
      return false;
    }
  }
}
