class UserData {
  // Basic identity
  static String userId = '';
  static String firstName = '';
  static String lastName = '';
  static String username = '';

  // Contact
  static String email = '';
  static String phoneNumber = '';

  // Note: No address or password stored here; backend does not expose them.

  static String get fullName {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return username.isNotEmpty ? username : 'User';
    if (f.isEmpty) return l;
    if (l.isEmpty) return f;
    return '$f $l';
  }

  // Populate fields from backend response
  static void updateFromJson(Map<String, dynamic> json) {
    userId = (json['id'] ?? json['_id'] ?? '').toString();
    firstName = (json['firstName'] ?? '').toString();
    lastName = (json['lastName'] ?? '').toString();
    username = (json['username'] ?? '').toString();
    email = (json['email'] ?? '').toString();
    phoneNumber = (json['phone'] ?? '').toString();
  }
}
