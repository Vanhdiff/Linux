import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../api/api_exception.dart';
import '../api/api_config.dart';
import '../backend/backend_process_service.dart';
import 'online_license_config.dart';
import 'online_license_models.dart';

class OnlineLicenseService {
  final BackendProcessService _backend;
  final HttpClient _client;

  OnlineLicenseService({
    BackendProcessService? backend,
    HttpClient? client,
  }) : _backend = backend ?? BackendProcessService(),
       _client = client ?? HttpClient() {
    _client.connectionTimeout = ApiConfig.timeout;
  }

  Future<OnlineLicenseStatus> bootstrap() async {
    if (!OnlineLicenseConfig.enabled) {
      return const OnlineLicenseStatus(
        isLicensed: false,
        requiresSignIn: true,
        message:
            'Online license is disabled in this build. Start or build the app with SUPABASE_LICENSE_ENABLED=true.',
      );
    }
    if (!OnlineLicenseConfig.isConfigured) {
      return const OnlineLicenseStatus(
        isLicensed: false,
        requiresSignIn: true,
        message:
            'Supabase license is enabled but this build is missing SUPABASE_URL or SUPABASE_ANON_KEY.',
      );
    }

    final session = await _readSession();
    if (session == null) {
      return const OnlineLicenseStatus(
        isLicensed: false,
        requiresSignIn: true,
        message: 'Sign in and activate your online license.',
      );
    }

    try {
      final refreshed = await _refreshAuthSessionIfNeeded(session);
      final validated = await _validateLicense(refreshed);
      await _persistSession(validated);
      return _buildLicensedStatus(
        validated,
        successMessage: 'Online license verified.',
      );
    } on ApiException catch (error) {
      if (_shouldInvalidateLocalSession(error)) {
        final recovered = await _tryValidateWithoutRefresh(session);
        if (recovered != null) {
          await _persistSession(recovered);
          return _buildLicensedStatus(
            recovered,
            successMessage:
                'Online license verified. Session refresh was recovered locally.',
          );
        }
        await signOut();
        return OnlineLicenseStatus(
          isLicensed: false,
          requiresSignIn: true,
          message: _withReSignInHint(error.toString()),
        );
      }

      if (session.isLicenseStillValid) {
        return _buildLicensedStatus(
          session,
          successMessage:
              'Using cached online license session while Supabase is unreachable.',
        );
      }

      await signOut();
      return OnlineLicenseStatus(
        isLicensed: false,
        requiresSignIn: true,
        message: _withReSignInHint(error.toString()),
      );
    } catch (error) {
      if (session.isLicenseStillValid) {
        return _buildLicensedStatus(
          session,
          successMessage:
              'Using cached online license session while Supabase is unreachable.',
        );
      }

      await signOut();
      return OnlineLicenseStatus(
        isLicensed: false,
        requiresSignIn: true,
        message: _withReSignInHint(error.toString()),
      );
    }
  }

  bool _shouldInvalidateLocalSession(ApiException error) {
    return error.statusCode == 401 ||
        error.statusCode == 403 ||
        error.statusCode == 404;
  }

  Future<OnlineLicenseStatus> signInAndActivate({
    required String email,
    required String password,
    required String licenseKey,
  }) async {
    final deviceId = await _readOrCreateDeviceId();
    final authPayload = await _signIn(email: email, password: password);
    final activated = await _activateLicense(
      email: email,
      accessToken: authPayload.accessToken,
      refreshToken: authPayload.refreshToken,
      authExpiresAt: authPayload.authExpiresAt,
      deviceId: deviceId,
      licenseKey: licenseKey,
    );
    await _persistSession(activated);
    return _buildLicensedStatus(
      activated,
      successMessage: 'Online license activated successfully.',
    );
  }

  Future<OnlineLicenseStatus> _buildLicensedStatus(
    OnlineLicenseSession session, {
    required String successMessage,
  }) async {
    try {
      await _grantBackend(session);
      return OnlineLicenseStatus(
        isLicensed: true,
        requiresSignIn: false,
        message: successMessage,
        session: session,
      );
    } catch (error) {
      return OnlineLicenseStatus(
        isLicensed: true,
        requiresSignIn: false,
        message:
            '$successMessage Local backend grant will retry automatically. $error',
        session: session,
      );
    }
  }

  String _withReSignInHint(String message) {
    return '$message Please sign in again to refresh the online license session.';
  }

  Future<OnlineLicenseSession?> _tryValidateWithoutRefresh(
    OnlineLicenseSession session,
  ) async {
    try {
      return await _validateLicense(session);
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _clearBackendGrant();
    } catch (_) {
      // If the backend is not running we can still consider the local sign-out complete.
    }
    try {
      await _backend.shutdownBackend();
    } catch (_) {
      // Best effort; the session file is still removed below.
    }
    await _deleteSession();
  }

  Future<OnlineLicenseSession> _refreshAuthSessionIfNeeded(
    OnlineLicenseSession session,
  ) async {
    final now = DateTime.now().toUtc();
    if (session.authExpiresAt.isAfter(now.add(const Duration(minutes: 2)))) {
      return session;
    }

    final uri = Uri.parse(
      '${OnlineLicenseConfig.supabaseUrl}/auth/v1/token',
    ).replace(queryParameters: const {'grant_type': 'refresh_token'});
    final payload = await _sendJson(
      method: 'POST',
      uri: uri,
      headers: _supabaseHeaders(),
      body: {'refresh_token': session.refreshToken},
    );
    return session.copyWith(
      accessToken: payload['access_token'] as String? ?? session.accessToken,
      refreshToken: payload['refresh_token'] as String? ?? session.refreshToken,
      authExpiresAt: _parseAuthExpiry(payload),
    );
  }

  Future<_AuthPayload> _signIn({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse(
      '${OnlineLicenseConfig.supabaseUrl}/auth/v1/token',
    ).replace(queryParameters: const {'grant_type': 'password'});
    final payload = await _sendJson(
      method: 'POST',
      uri: uri,
      headers: _supabaseHeaders(),
      body: {
        'email': email,
        'password': password,
      },
    );
    return _AuthPayload(
      accessToken: payload['access_token'] as String? ?? '',
      refreshToken: payload['refresh_token'] as String? ?? '',
      authExpiresAt: _parseAuthExpiry(payload),
    );
  }

  Future<OnlineLicenseSession> _activateLicense({
    required String email,
    required String accessToken,
    required String refreshToken,
    required DateTime authExpiresAt,
    required String deviceId,
    required String licenseKey,
  }) async {
    final payload = await _invokeFunction(
      functionName: OnlineLicenseConfig.activateFunction,
      accessToken: accessToken,
      body: {
        'license_key': licenseKey,
        'device_id': deviceId,
        'device_name': _deviceName(),
        'app_version': '1.0.0',
      },
    );
    return _sessionFromFunctionPayload(
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      authExpiresAt: authExpiresAt,
      deviceId: deviceId,
      fallbackLicenseKey: licenseKey,
      payload: payload,
    );
  }

  Future<OnlineLicenseSession> _validateLicense(
    OnlineLicenseSession session,
  ) async {
    final payload = await _invokeFunction(
      functionName: OnlineLicenseConfig.validateFunction,
      accessToken: session.accessToken,
      body: {
        'license_key': session.licenseKey,
        'device_id': session.deviceId,
        'device_name': _deviceName(),
        'app_version': '1.0.0',
      },
    );
    return _sessionFromFunctionPayload(
      email: session.email,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      authExpiresAt: session.authExpiresAt,
      deviceId: session.deviceId,
      fallbackLicenseKey: session.licenseKey,
      payload: payload,
    );
  }

  Future<Map<String, dynamic>> _invokeFunction({
    required String functionName,
    required String accessToken,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(
      '${OnlineLicenseConfig.supabaseUrl}/functions/v1/$functionName',
    );
    return _sendJson(
      method: 'POST',
      uri: uri,
      headers: _supabaseHeaders(accessToken: accessToken),
      body: body,
    );
  }

  Future<Map<String, dynamic>> _sendJson({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(
        ApiConfig.timeout,
      );
      headers.forEach(request.headers.set);
      if (body != null) {
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(ApiConfig.timeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(ApiConfig.timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _extractErrorMessage(responseBody);
        throw ApiException(
          _friendlyHttpError(message, response.statusCode),
          statusCode: response.statusCode,
        );
      }
      if (responseBody.isEmpty) return <String, dynamic>{};
      return Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
    } on SocketException catch (error) {
      throw ApiException('Cannot connect to Supabase: ${error.message}');
    } on TimeoutException {
      throw const ApiException('License request timed out');
    } on FormatException catch (error) {
      throw ApiException('Invalid Supabase response: ${error.message}');
    }
  }

  Future<void> _grantBackend(OnlineLicenseSession session) async {
    await _backend.ensureRunning();
    final uri = Uri.parse('http://127.0.0.1:8000/api/license/session');
    await _sendJson(
      method: 'POST',
      uri: uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: {
        'license_key': session.licenseKey,
        'owner_email': session.ownerEmail ?? session.email,
        'device_id': session.deviceId,
        'provider': 'supabase',
        'expires_at': session.licenseExpiresAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _clearBackendGrant() async {
    await _backend.ensureRunning();
    final uri = Uri.parse('http://127.0.0.1:8000/api/license/session');
    await _sendJson(
      method: 'DELETE',
      uri: uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
  }

  OnlineLicenseSession _sessionFromFunctionPayload({
    required String email,
    required String accessToken,
    required String refreshToken,
    required DateTime authExpiresAt,
    required String deviceId,
    required String fallbackLicenseKey,
    required Map<String, dynamic> payload,
  }) {
    final licensed =
        payload['licensed'] as bool? ?? payload['valid'] as bool? ?? false;
    if (!licensed) {
      throw ApiException(
        payload['message'] as String? ?? 'License is not active.',
      );
    }

    final expiresAtValue =
        payload['expires_at'] as String? ?? payload['license_expires_at'] as String?;
    if (expiresAtValue == null || expiresAtValue.isEmpty) {
      throw const ApiException('Supabase function did not return expires_at.');
    }

    return OnlineLicenseSession(
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      authExpiresAt: authExpiresAt,
      deviceId: deviceId,
      licenseKey: payload['license_key'] as String? ?? fallbackLicenseKey,
      licenseExpiresAt: DateTime.parse(expiresAtValue).toUtc(),
      ownerEmail: payload['email'] as String? ?? payload['owner_email'] as String?,
      plan: payload['plan'] as String?,
      status: payload['status'] as String?,
    );
  }

  Map<String, String> _supabaseHeaders({String? accessToken}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'apikey': OnlineLicenseConfig.anonKey,
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    return headers;
  }

  String _extractErrorMessage(String responseBody) {
    if (responseBody.isEmpty) return 'Request failed';
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
        final error = decoded['error_description'] ?? decoded['error'];
        if (error is String && error.isNotEmpty) return error;
      }
    } catch (_) {
      // Use the raw body when the response is not JSON.
    }
    return responseBody;
  }

  String _friendlyHttpError(String message, int statusCode) {
    final normalized = message.toLowerCase();
    if (statusCode == 401 && normalized.contains('invalid api key')) {
      return 'Supabase anon public key is invalid. Rebuild the app with the current anon public key from Supabase API Keys.';
    }
    if (statusCode == 404 && normalized.contains('not found')) {
      return 'Supabase license function was not found. Deploy activate-license and validate-license again.';
    }
    return '$message ($statusCode)';
  }

  DateTime _parseAuthExpiry(Map<String, dynamic> payload) {
    final expiresIn = payload['expires_in'];
    final seconds = expiresIn is num ? expiresIn.toInt() : 3600;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }

  Future<OnlineLicenseSession?> _readSession() async {
    final file = await _sessionFile();
    if (!file.existsSync()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    return OnlineLicenseSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> _persistSession(OnlineLicenseSession session) async {
    final file = await _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  Future<void> _deleteSession() async {
    final file = await _sessionFile();
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<String> _readOrCreateDeviceId() async {
    final file = await _deviceFile();
    if (file.existsSync()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }
    await file.parent.create(recursive: true);
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final value = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await file.writeAsString(value);
    return value;
  }

  String _deviceName() {
    final user = Platform.environment['USERNAME'];
    final host = Platform.localHostname;
    if (user == null || user.isEmpty) return host;
    return '$host/$user';
  }

  Future<File> _sessionFile() async {
    return File('${_licenseDirectoryPath()}${Platform.pathSeparator}online_session.json');
  }

  Future<File> _deviceFile() async {
    return File('${_licenseDirectoryPath()}${Platform.pathSeparator}device_id.txt');
  }

  String _licenseDirectoryPath() {
    final appData =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    return '$appData${Platform.pathSeparator}TradingDesk${Platform.pathSeparator}license';
  }

  void close() {
    _client.close(force: true);
    _backend.close();
  }
}

class _AuthPayload {
  final String accessToken;
  final String refreshToken;
  final DateTime authExpiresAt;

  const _AuthPayload({
    required this.accessToken,
    required this.refreshToken,
    required this.authExpiresAt,
  });
}
