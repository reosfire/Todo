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

/// Returns the base URL of the app (origin + base path).
/// For example: https://reosfire.github.io/Todo/ or http://localhost:8080/
String getAppRedirectUri() {
  // Get the base element's href which includes the base path
  final baseElement = web.document.querySelector('base');
  if (baseElement != null) {
    final baseHref = baseElement.getAttribute('href');
    if (baseHref != null && baseHref.isNotEmpty && baseHref != r'$FLUTTER_BASE_HREF') {
      // base href is absolute or relative - combine with origin
      final uri = Uri.parse(web.window.location.href);
      final base = Uri.parse(baseHref);
      if (base.hasScheme) {
        // Absolute base href
        return base.toString();
      } else {
        // Relative base href - combine with origin
        return '${uri.origin}$baseHref';
      }
    }
  }
  // Fallback to origin if no base href found
  return web.window.location.origin;
}
