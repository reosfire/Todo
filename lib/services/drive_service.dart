import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/app_data.dart';

const _fileName = 'todo_app_data.json';

/// Authenticated HTTP client that injects the Google Sign‑In access token.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class DriveService {
  GoogleSignInAccount? _account;
  drive.DriveApi? _driveApi;

  bool get isSignedIn => _account != null;
  String? get userEmail => _account?.email;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  /// Try silent sign-in on launch.
  Future<bool> trySilentSignIn() async {
    try {
      _account = await _googleSignIn.signInSilently();
      if (_account != null) {
        await _initDriveApi();
        return true;
      }
    } catch (e) {
      debugPrint('Silent sign-in failed: $e');
    }
    return false;
  }

  Future<bool> signIn() async {
    try {
      _account = await _googleSignIn.signIn();
      if (_account != null) {
        await _initDriveApi();
        return true;
      }
    } catch (e) {
      debugPrint('Sign-in failed: $e');
    }
    return false;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _account = null;
    _driveApi = null;
  }

  Future<void> _initDriveApi() async {
    final headers = await _account!.authHeaders;
    final client = _GoogleAuthClient(headers);
    _driveApi = drive.DriveApi(client);
  }

  /// Upload the current app data to Google Drive appData folder.
  Future<void> upload(AppData data) async {
    if (_driveApi == null) return;

    final jsonString = jsonEncode(data.toJson());
    final bytes = utf8.encode(jsonString);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );

    // Check if file already exists.
    final existingId = await _findFileId();
    if (existingId != null) {
      await _driveApi!.files.update(
        drive.File()..name = _fileName,
        existingId,
        uploadMedia: media,
      );
    } else {
      final driveFile = drive.File()
        ..name = _fileName
        ..parents = ['appDataFolder'];
      await _driveApi!.files.create(driveFile, uploadMedia: media);
    }
  }

  /// Download app data from Google Drive.
  Future<AppData?> download() async {
    if (_driveApi == null) return null;

    final fileId = await _findFileId();
    if (fileId == null) return null;

    final response = await _driveApi!.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    final jsonString = utf8.decode(bytes);
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return AppData.fromJson(json);
  }

  Future<String?> _findFileId() async {
    if (_driveApi == null) return null;
    final result = await _driveApi!.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName'",
      $fields: 'files(id, name)',
    );
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id;
    }
    return null;
  }
}
