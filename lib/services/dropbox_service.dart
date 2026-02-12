import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_data.dart';
import 'web_auth.dart' as web_auth;

/// Dropbox OAuth2 + Files API service using PKCE (no client secret needed).
///
/// Setup instructions:
/// 1. Go to https://www.dropbox.com/developers/apps and create a new app.
/// 2. Choose "Scoped access" → "App folder".
/// 3. In the Permissions tab enable `files.content.write` and
///    `files.content.read`, then click Submit.
/// 4. In the Settings tab:
///    • Copy the **App key** and paste it into [_appKey] below.
///    • Add redirect URIs:
///      – For web: your app's URL (e.g. `http://localhost:8080`)
///      – For mobile: `todoapp://auth`
/// 5. Run the app and tap "Connect to Dropbox".
class DropboxService {
  // ── Replace with your own Dropbox App key ──
  static const String _appKey = 'h977trn71rfdiim';

  // ── Token storage keys ──
  static const _keyAccessToken = 'dbx_access_token';
  static const _keyRefreshToken = 'dbx_refresh_token';
  static const _keyExpiresAt = 'dbx_expires_at';
  static const _keyCodeVerifier = 'dbx_code_verifier';

  // ── Remote file path inside the app folder ──
  static const _remotePath = '/todo_data.json';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  bool get isSignedIn => _accessToken != null;

  // ───── Initialise ─────

  /// Loads saved tokens and, on web, finishes any pending OAuth redirect.
  Future<void> init() async {
    await _loadTokens();

    // On web, check if Dropbox just redirected us back with a code.
    final code = web_auth.getAuthCodeFromUrl();
    if (code != null) {
      web_auth.clearUrlAuthCode();
      final verifier = await _loadCodeVerifier();
      if (verifier != null) {
        await _exchangeCode(code, verifier);
      }
    }
  }

  // ───── Sign-in / out ─────

  /// Opens the Dropbox OAuth page in the browser.
  Future<void> signIn() async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);
    await _saveCodeVerifier(verifier);

    final redirectUri = _redirectUri;
    final uri = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': _appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'redirect_uri': redirectUri,
      'token_access_type': 'offline',
    });

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Called on mobile when the app receives the redirect with the auth code.
  Future<bool> handleRedirectCode(String code) async {
    final verifier = await _loadCodeVerifier();
    if (verifier == null) return false;
    return _exchangeCode(code, verifier);
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyExpiresAt);
    await prefs.remove(_keyCodeVerifier);
  }

  // ───── Upload / Download ─────

  Future<void> upload(AppData data) async {
    await _ensureValidToken();
    final json = jsonEncode(data.toJson());

    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({
          'path': _remotePath,
          'mode': 'overwrite',
          'autorename': false,
          'mute': true,
        }),
      },
      body: utf8.encode(json),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox upload failed (${response.statusCode}): '
        '${response.body}',
      );
    }
  }

  Future<AppData?> download() async {
    await _ensureValidToken();

    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/download'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Dropbox-API-Arg': jsonEncode({'path': _remotePath}),
      },
    );

    if (response.statusCode == 409) {
      // File not found — first sync.
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox download failed (${response.statusCode}): '
        '${response.body}',
      );
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return AppData.fromJson(map);
  }

  // ───── PKCE helpers ─────

  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List.generate(128, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ───── Token management ─────

  String get _redirectUri {
    if (kIsWeb) {
      final webUri = web_auth.getAppRedirectUri();
      return webUri.isNotEmpty ? webUri : 'http://localhost:8080';
    }
    return 'todoapp://auth';
  }

  Future<bool> _exchangeCode(String code, String codeVerifier) async {
    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'grant_type': 'authorization_code',
        'client_id': _appKey,
        'redirect_uri': _redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode != 200) {
      debugPrint('Dropbox token exchange failed: ${response.body}');
      return false;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String?;
    final expiresIn = data['expires_in'] as int? ?? 14400;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    await _saveTokens();
    return true;
  }

  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) return;

    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': _appKey,
      },
    );

    if (response.statusCode != 200) {
      debugPrint('Dropbox token refresh failed: ${response.body}');
      // Token may be revoked — sign out.
      await signOut();
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresIn = data['expires_in'] as int? ?? 14400;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    await _saveTokens();
  }

  Future<void> _ensureValidToken() async {
    if (_accessToken == null) throw Exception('Not signed in to Dropbox');
    if (_expiresAt != null &&
        DateTime.now().isAfter(
          _expiresAt!.subtract(const Duration(minutes: 5)),
        )) {
      await _refreshAccessToken();
    }
  }

  // ───── Persistence ─────

  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null)
      await prefs.setString(_keyAccessToken, _accessToken!);
    if (_refreshToken != null)
      await prefs.setString(_keyRefreshToken, _refreshToken!);
    if (_expiresAt != null) {
      await prefs.setString(_keyExpiresAt, _expiresAt!.toIso8601String());
    }
  }

  Future<void> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_keyAccessToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    final exp = prefs.getString(_keyExpiresAt);
    if (exp != null) _expiresAt = DateTime.parse(exp);
  }

  Future<void> _saveCodeVerifier(String verifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCodeVerifier, verifier);
  }

  Future<String?> _loadCodeVerifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCodeVerifier);
  }
}
