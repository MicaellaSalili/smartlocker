import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
// ...existing code...
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../utils/app_constants.dart';

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
  /// Private helper for retrying API calls with exponential backoff and jitter
  Future<http.Response> _retryWrapper(Future<http.Response> Function() apiCall) async {
    int maxAttempts = 3;
    int attempt = 0;
    final random = Random();
    while (attempt < maxAttempts) {
      try {
        final response = await apiCall();
        return response;
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        // Exponential backoff: 1s, 2s, 4s + jitter (0-500ms)
        int baseDelay = pow(2, attempt - 1).toInt() * 1000;
        int jitter = random.nextInt(500);
        await Future.delayed(Duration(milliseconds: baseDelay + jitter));
      }
    }
    throw Exception('Max retry attempts reached');
  }

  /// POST scan data to /api/parcels/scan with retry logic
  Future<String> postScanData(Map<String, dynamic> scanData) async {
    final url = Uri.parse('${AppConstants.BASE_API_URL}/parcels/scan');
    try {
      final response = await _retryWrapper(() => http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(scanData),
      ));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['transaction_id']?.toString() ?? '';
      } else {
        throw Exception('Failed to post scan data: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error posting scan data: $e');
      rethrow;
    }
  }

  /// Send lock command via MQTT to smartlocker/control/lock
  void sendLockCommand(String lockerId) async {
    final client = MqttServerClient(AppConstants.MQTT_BROKER_HOST, 'smartlocker_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onDisconnected = () => debugPrint('MQTT disconnected');
    client.onConnected = () => debugPrint('MQTT connected');
    client.onSubscribed = (topic) => debugPrint('Subscribed to $topic');

    try {
      await client.connect();
      final builder = MqttClientPayloadBuilder();
      builder.addString(json.encode({
        'lockerId': lockerId,
        'command': 'LOCK',
      }));
      client.publishMessage(
        AppConstants.MQTT_LOCK_TOPIC,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );
      debugPrint('LOCK command sent for locker $lockerId');
      await Future.delayed(const Duration(seconds: 2));
      client.disconnect();
    } catch (e) {
      debugPrint('MQTT error: $e');
      client.disconnect();
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

    debugPrint(
      'Text match: $matchCount/${storedTokens.length} tokens (${(matchPercentage * 100).toStringAsFixed(1)}%)',
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
  Future<void> logTransactionData({
    required String lockerId,
    required String waybillId,
    required String waybillDetails,
    required List<double> embedding,
  }) async {
    _lockerId = lockerId;
    _waybillId = waybillId;
    _waybillDetails = waybillDetails;
    _embedding = embedding;

    // Validate all required data is present
    if (!isDataComplete()) {
      debugPrint('Error: Incomplete transaction data. Missing:');
      if (_auditData == null) debugPrint('- Audit data (recipient info)');
      if (_lockerId == null) debugPrint('- Locker ID');
      if (_waybillId == null) debugPrint('- Waybill ID');
      if (_waybillDetails == null) debugPrint('- Waybill details');
      if (_embedding == null) debugPrint('- Image embedding');
      return;
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
    };

    try {
      // Send POST request to /api/parcel/log
      final url = Uri.parse('${AppConstants.BASE_API_URL}/parcel/log');
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
    try {
      // Use lockerId as identifier (customize if needed)
      if (_lockerId == null) {
        debugPrint('fetchReferenceData: No lockerId available');
        return false;
      }
      final url = Uri.parse('${AppConstants.BASE_API_URL}/parcels/fetch?lockerId=$_lockerId');
      final response = await _retryWrapper(() => http.get(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Update internal state variables
        _embedding = (data['embedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList();
        _waybillId = data['waybill_id']?.toString();
        _waybillDetails = data['waybill_details']?.toString();
        if (_embedding != null && _waybillId != null && _waybillDetails != null) {
          debugPrint('Reference data fetched: Waybill ID: $_waybillId, Embedding length: ${_embedding!.length}');
          notifyListeners();
          return true;
        } else {
          debugPrint('fetchReferenceData: Missing fields in response');
          return false;
        }
      } else {
        debugPrint('fetchReferenceData: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('fetchReferenceData error: $e');
      return false;
    }
  }

  // Finalize transaction after successful verification
  // Sends PUT request to /api/parcel/success/:id
  Future<bool> finalizeTransaction() async {
    if (_transactionId == null) {
      debugPrint(
        'Error: Cannot finalize transaction. No transaction ID available.',
      );
      return false;
    }

    try {
      final url = Uri.parse(
        '${AppConstants.BASE_API_URL}/parcel/success/$_transactionId',
      );
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('Transaction finalized successfully: $_transactionId');
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

  // Delete/rollback transaction on failure
  // Sends DELETE request to /api/parcels/rollback?waybillId=...
  Future<bool> deleteTransaction() async {
    if (_waybillId == null) {
      debugPrint('Error: Cannot delete transaction. No waybill ID available.');
      return false;
    }
    try {
      final url = Uri.parse('${AppConstants.BASE_API_URL}/parcels/rollback?waybillId=$_waybillId');
      final response = await _retryWrapper(() => http.delete(url));
      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('Transaction rollback (delete) successful for waybillId: $_waybillId');
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
        debugPrint('Failed to rollback transaction. Status: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error rolling back transaction: $e');
      return false;
    }
  }

  // Lock the locker door (called after courier closes door)
  // Sends PUT request to /api/locker/:lockerId/lock
  Future<bool> lockLocker() async {
    if (_lockerId == null) {
      debugPrint('Error: Cannot lock locker. No locker ID available.');
      return false;
    }

    try {
      final url = Uri.parse('${AppConstants.BASE_API_URL}/locker/$_lockerId/lock');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
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
