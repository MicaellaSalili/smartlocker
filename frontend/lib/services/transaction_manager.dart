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
  TransactionData? _auditData;
  String? _transactionId; // MongoDB _id
  String? _waybillId;
  String? _waybillDetails;
  List<double>? _embedding;

  TransactionData? get auditData => _auditData;
  String? get transactionId => _transactionId;
  String? get waybillId => _waybillId;
  String? get waybillDetails => _waybillDetails;
  List<double>? get embedding => _embedding;

  /// Robust text comparison utility function
  /// Returns true if liveText contains at least 70% of key tokens from storedText
  /// This allows for minor OCR errors while maintaining verification accuracy
  static bool isTextContentMatch(String liveText, String storedText) {
    if (storedText.isEmpty) return true; // Skip check if no reference
    if (liveText.isEmpty) return false; // Fail if live text is empty
    
    // Normalize texts: lowercase, remove extra whitespace
    final liveNormalized = liveText.toLowerCase().trim();
    final storedNormalized = storedText.toLowerCase().trim();
    
    // Extract key tokens (words/numbers) from stored text
    // Filter out common words and very short tokens
    final storedTokens = storedNormalized
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2) // Filter out single characters
        .where((token) => !_isCommonWord(token)) // Filter out common words
        .toSet(); // Use set to get unique tokens
    
    if (storedTokens.isEmpty) return true; // No meaningful tokens to compare
    
    // Count how many stored tokens appear in live text
    int matchCount = 0;
    for (var token in storedTokens) {
      if (liveNormalized.contains(token)) {
        matchCount++;
      }
    }
    
    // Calculate match percentage
    final matchPercentage = matchCount / storedTokens.length;
    
    debugPrint('Text match: $matchCount/${storedTokens.length} tokens (${(matchPercentage * 100).toStringAsFixed(1)}%)');
    
    // Return true if at least 70% of tokens match
    return matchPercentage >= 0.70;
  }
  
  /// Helper function to filter out common words that don't add verification value
  static bool _isCommonWord(String word) {
    const commonWords = {
      'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with',
      'a', 'an', 'is', 'was', 'are', 'were', 'be', 'been', 'being',
      'this', 'that', 'these', 'those', 'from', 'by', 'as', 'it',
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

  // Log transaction data with waybill info and embedding
  Future<void> logTransactionData({
    required String waybillId,
    required String waybillDetails,
    required List<double> embedding,
  }) async {
    _waybillId = waybillId;
    _waybillDetails = waybillDetails;
    _embedding = embedding;
    
    // Construct the full JSON payload by merging audit data with reference data
    if (_auditData == null) {
      debugPrint('Error: Audit data not set. Please call updateAuditData first.');
      return;
    }

    final payload = {
      // Audit data (recipient information) - match backend field names
      'recipient_first_name': _auditData!.firstName,
      'recipient_last_name': _auditData!.lastName,
      'recipient_phone': _auditData!.phoneNumber,
      
      // Reference data (waybill and embedding) - match backend field names
      'waybill_id': waybillId,
      'waybill_details': waybillDetails,
      'image_embedding_vector': embedding,
    };

    try {
      // Send POST request to /api/parcel/log
      final url = Uri.parse('${ApiConfig.baseUrl}/api/parcel/log');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse response to get transaction_id
        final responseData = json.decode(response.body);
        _transactionId = responseData['transaction_id'];
        
        debugPrint('Transaction logged successfully: $waybillId');
        debugPrint('Transaction ID: $_transactionId');
        debugPrint('Response: ${response.body}');
      } else {
        debugPrint('Failed to log transaction. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error logging transaction: $e');
    }
    
    notifyListeners();
  }

  // Fetch reference data (returns the stored embedding and waybill info)
  Future<bool> fetchReferenceData() async {
    // Check if we have stored reference data
    if (_embedding != null && _waybillId != null) {
      debugPrint('Reference data fetched: Waybill ID: $_waybillId, Embedding length: ${_embedding!.length}');
      return true;
    } else {
      debugPrint('No reference data available. Please scan package first.');
      return false;
    }
  }

  // Finalize transaction after successful verification
  // Sends PUT request to /api/parcel/success/:id
  Future<bool> finalizeTransaction() async {
    if (_transactionId == null) {
      debugPrint('Error: Cannot finalize transaction. No transaction ID available.');
      return false;
    }

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/parcel/success/$_transactionId');
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('Transaction finalized successfully: $_transactionId');
        debugPrint('Response: ${response.body}');
        notifyListeners();
        return true;
      } else {
        debugPrint('Failed to finalize transaction. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error finalizing transaction: $e');
      return false;
    }
  }

  // Delete/rollback transaction on failure
  // Sends DELETE request to /api/parcel/:id
  Future<bool> deleteTransaction() async {
    if (_transactionId == null) {
      debugPrint('Error: Cannot delete transaction. No transaction ID available.');
      return false;
    }

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/parcel/$_transactionId');
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('Transaction deleted successfully: $_transactionId');
        debugPrint('Response: ${response.body}');
        
        // Clear local data after successful deletion
        _transactionId = null;
        _waybillId = null;
        _waybillDetails = null;
        _embedding = null;
        _auditData = null;
        
        notifyListeners();
        return true;
      } else {
        debugPrint('Failed to delete transaction. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      return false;
    }
  }
}
