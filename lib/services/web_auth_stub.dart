// Stub for non-web platforms.

/// Returns null — no auth code from URL on mobile.
String? getAuthCodeFromUrl() => null;

/// No-op on non-web platforms.
void clearUrlAuthCode() {}

/// Returns the current origin (e.g. http://localhost:8080).
/// On non-web, returns an empty string (not used).
String getAppRedirectUri() => '';
