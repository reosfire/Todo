import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// On web, reads the `code` query parameter from the current URL.
/// Returns null if no code is present.
String? getAuthCodeFromUrl() {
  final uri = Uri.parse(web.window.location.href);
  return uri.queryParameters['code'];
}

/// Removes the `code` query param from the browser URL bar
/// without reloading the page.
void clearUrlAuthCode() {
  final uri = Uri.parse(web.window.location.href);
  final cleanParams = Map<String, String>.from(uri.queryParameters)
    ..remove('code');
  final cleanUri = uri.replace(
    queryParameters: cleanParams.isEmpty ? null : cleanParams,
  );
  final cleanUrl = cleanUri.toString();
  web.window.history.replaceState(''.toJSBox, '', cleanUrl);
}

/// Returns the origin of the current page (e.g. http://localhost:8080).
String getAppRedirectUri() {
  return web.window.location.origin;
}
