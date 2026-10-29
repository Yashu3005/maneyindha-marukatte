import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthState {
  final Map<String, dynamic>? user;
  const AuthState({this.user});
  bool get isLoggedIn => user != null;
  String get name => user?['name']?.toString() ?? '';
  String get email => user?['email']?.toString() ?? '';
  String get role => user?['role']?.toString() ?? 'customer';
  bool get isEntrepreneur => role == 'entrepreneur';
  bool get isAdmin => role == 'admin' || role == 'super_admin';
  bool get profileComplete => user?['profileComplete'] == true;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _restore();
  }

  Future<void> _restore() async {
    await TokenStore.load();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('user');
    if (stored != null && TokenStore.accessToken != null) {
      state = AuthState(user: jsonDecode(stored) as Map<String, dynamic>);
    }
  }

  Future<void> _saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    if (TokenStore.remember) {
      await prefs.setString('user', jsonEncode(user));
    } else {
      await prefs.remove('user');
    }
    state = AuthState(user: user);
  }

  Future<void> _apply(Map<String, dynamic> data) async {
    await TokenStore.save(data['accessToken'] as String?,
        refresh: data['refreshToken'] as String?);
    await _saveUser(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<void> login(String identity, String password) async {
    final field = identity.contains('@') ? 'email' : 'username';
    final res = await ApiClient.dio
        .post('/auth/login', data: {field: identity.trim(), 'password': password});
    await _apply(res.data['data'] as Map<String, dynamic>);
  }

  /// The single administrator signs in with the username and password configured on the server.
  Future<void> adminLogin(String username, String password) async {
    final res = await ApiClient.dio
        .post('/auth/admin/login', data: {'username': username.trim(), 'password': password});
    await _apply(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> register(String name, String email, String password,
      {String role = 'customer'}) async {
    final res = await ApiClient.dio.post('/auth/register',
        data: {'name': name, 'email': email, 'password': password, 'role': role});
    await _apply(res.data['data'] as Map<String, dynamic>);
  }

  /// Asks the backend to email a one-time code (via Resend). Returns how many
  /// seconds the user must wait before requesting another one.
  Future<int> sendOtp(String email) async {
    final res = await ApiClient.dio.post('/auth/otp/send', data: {'email': email});
    final data = Map<String, dynamic>.from(res.data['data'] as Map);
    return (data['resendAfterSeconds'] as num?)?.toInt() ?? 60;
  }

  Future<bool> verifyOtp(String email, String otp) async {
    final res = await ApiClient.dio
        .post('/auth/otp/verify', data: {'email': email, 'otp': otp});
    final data = Map<String, dynamic>.from(res.data['data'] as Map);
    await _apply(data);
    return data['isNewUser'] == true;
  }

  /// Uploads a profile photo (JPEG/PNG/WebP, max 2 MB — enforced again by the server).
  Future<void> uploadAvatar(List<int> bytes, String filename) async {
    final form = FormData.fromMap({'avatar': MultipartFile.fromBytes(bytes, filename: filename)});
    final res = await ApiClient.dio.post('/users/me/avatar', data: form);
    await _saveUser(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<void> removeAvatar() async {
    final res = await ApiClient.dio.delete('/users/me/avatar');
    await _saveUser(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final res = await ApiClient.dio.patch('/users/me', data: fields);
    await _saveUser(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  /// Returns true when the account already has a business (so returning
  /// entrepreneurs skip onboarding).
  Future<bool> switchRole(String role) async {
    final res = await ApiClient.dio.post('/users/me/role', data: {'role': role});
    final data = Map<String, dynamic>.from(res.data['data'] as Map);
    await _apply(data);
    return data['hasBusiness'] == true;
  }

  Future<void> setCredentials(String username, String password) async {
    final res = await ApiClient.dio.post('/users/me/credentials',
        data: {'username': username, 'password': password});
    await _saveUser(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<void> setSecurityQuestions(Map<String, String> answers) async {
    await ApiClient.dio
        .post('/users/me/security-questions', data: {'answers': answers});
  }

  Future<void> logout() async {
    // Clear this device first, so the app never thinks you are still signed in while the network call runs;
    // then revoke the server-side session (best effort).
    final refresh = TokenStore.refreshToken;
    state = const AuthState(); // synchronous: screens that react to sign-out see it immediately
    await TokenStore.save(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    if (refresh != null) {
      try {
        await ApiClient.dio.post('/auth/logout', data: {'refreshToken': refresh});
      } catch (_) {}
    }
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
