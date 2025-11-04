import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AuthService {
  static Future<({bool ok, String? error, Map<String, dynamic>? user})> signup({
    required String firstName,
    required String lastName,
    required String username,
    required String phone,
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/signup');
    try {
      final res = await http
          .post(
            uri,
            headers: { 'Content-Type': 'application/json' },
            body: jsonEncode({
              'firstName': firstName,
              'lastName': lastName,
              'username': username,
              'phone': phone,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 201) {
        return (ok: true, error: null, user: jsonDecode(res.body) as Map<String, dynamic>);
      }

      final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
      final error = body['error']?.toString() ?? 'Signup failed (HTTP ${res.statusCode})';
      return (ok: false, error: error, user: null);
    } catch (e) {
      return (ok: false, error: e.toString(), user: null);
    }
  }

  static Future<({bool ok, String? error, Map<String, dynamic>? user})> login({
    required String identifier,
    required String password,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/login');
    try {
      final res = await http
          .post(
            uri,
            headers: { 'Content-Type': 'application/json' },
            body: jsonEncode({
              'identifier': identifier,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        return (ok: true, error: null, user: jsonDecode(res.body) as Map<String, dynamic>);
      }

      final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
      final error = body['error']?.toString() ?? 'Login failed (HTTP ${res.statusCode})';
      return (ok: false, error: error, user: null);
    } catch (e) {
      return (ok: false, error: e.toString(), user: null);
    }
  }

  static Future<({bool ok, String? error})> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/change-password');
    try {
      final res = await http
          .post(
            uri,
            headers: { 'Content-Type': 'application/json' },
            body: jsonEncode({
              'id': userId,
              'oldPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        return (ok: true, error: null);
      }

      final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
      final error = body['error']?.toString() ?? 'Change password failed (HTTP ${res.statusCode})';
      return (ok: false, error: error);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  static Future<({bool ok, String? error, Map<String, dynamic>? user})> updateProfile({
    required String userId,
    required String username,
    required String email,
    required String phone,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/update-profile');
    try {
      final res = await http
          .post(
            uri,
            headers: { 'Content-Type': 'application/json' },
            body: jsonEncode({
              'id': userId,
              'username': username,
              'email': email,
              'phone': phone,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (ok: true, error: null, user: body);
      }

      final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
      final error = body['error']?.toString() ?? 'Update profile failed (HTTP ${res.statusCode})';
      return (ok: false, error: error, user: null);
    } catch (e) {
      return (ok: false, error: e.toString(), user: null);
    }
  }
}
