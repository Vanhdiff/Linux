import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_config.dart';
import 'api_exception.dart';

class ApiClient {
  final String baseUrl;
  final HttpClient _client;

  ApiClient({this.baseUrl = ApiConfig.baseUrl, HttpClient? client})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = ApiConfig.timeout;
  }

  Future<dynamic> getJson(String path, {Map<String, String>? queryParameters}) {
    return _sendJson('GET', path, queryParameters: queryParameters);
  }

  Future<dynamic> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParameters,
  }) {
    return _sendJson(
      'POST',
      path,
      queryParameters: queryParameters,
      body: body,
    );
  }

  Future<dynamic> patchJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParameters,
  }) {
    return _sendJson(
      'PATCH',
      path,
      queryParameters: queryParameters,
      body: body,
    );
  }

  Future<dynamic> putJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParameters,
  }) {
    return _sendJson('PUT', path, queryParameters: queryParameters, body: body);
  }

  Future<void> delete(String path) async {
    await _sendJson('DELETE', path);
  }

  Future<dynamic> _sendJson(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: queryParameters);

    try {
      final request = await _client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(ApiConfig.timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _extractErrorMessage(responseBody),
          statusCode: response.statusCode,
        );
      }

      if (responseBody.isEmpty) return null;
      return jsonDecode(responseBody);
    } on SocketException catch (error) {
      throw ApiException('Cannot connect to backend: ${error.message}');
    } on TimeoutException {
      throw ApiException('Backend request timed out');
    } on FormatException catch (error) {
      throw ApiException('Invalid JSON response: ${error.message}');
    }
  }

  void close() {
    _client.close(force: true);
  }

  String _extractErrorMessage(String responseBody) {
    if (responseBody.isEmpty) return 'API request failed';
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Fall back to the raw response body when it is not JSON.
    }
    return responseBody;
  }
}
