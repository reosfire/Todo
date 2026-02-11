import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Platform-specific Google OAuth 2.0 Client IDs.
///
/// These are public identifiers and safe to commit — security is enforced
/// by redirect URIs, bundle IDs, and SHA-1 fingerprints.
class GoogleClientIds {
  static const _web =
      '589317871094-mq7oelnksh67chlu7h9bi14agp1ajdb9.apps.googleusercontent.com';
  static const _ios =
      ''; // TODO: set your iOS client ID
  static const _android =
      ''; // TODO: set your Android client ID

  /// Returns the client ID for the current platform, or `null` if not set.
  static String? get current {
    if (kIsWeb) return _web.isNotEmpty ? _web : null;
    if (Platform.isIOS || Platform.isMacOS) return _ios.isNotEmpty ? _ios : null;
    if (Platform.isAndroid) return _android.isNotEmpty ? _android : null;
    return null;
  }

  /// Server client ID — Android needs the **web** client ID as serverClientId
  /// so that `authHeaders` returns a valid token for googleapis.
  static String? get serverClientId {
    if (!kIsWeb && Platform.isAndroid) {
      return _web.isNotEmpty ? _web : null;
    }
    return null;
  }
}
