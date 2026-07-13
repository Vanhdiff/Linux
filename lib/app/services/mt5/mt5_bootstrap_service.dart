import 'dart:async';

import '../../services/api/api_client.dart';
import '../backend/backend_process_service.dart';
import '../../state/active_account_session.dart';

class Mt5BootstrapService {
  final ApiClient _apiClient;
  final BackendProcessService _backend;

  Mt5BootstrapService({ApiClient? apiClient, BackendProcessService? backend})
    : _apiClient = apiClient ?? ApiClient(),
      _backend = backend ?? BackendProcessService();

  Future<Map<String, dynamic>> bootstrap() async {
    await _backend.ensureRunning();
    final response = await _apiClient.postJson('/api/mt5/bootstrap', {
      'history_days': 90,
    });
    final json = Map<String, dynamic>.from(response as Map);
    ActiveAccountSession.useMt5Account(
      id: (json['account_id'] as num).toInt(),
      login: json['account_login'] as String?,
    );
    return json;
  }

  Future<void> syncActiveAccount() async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson('/api/accounts');
    final accounts = (response as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (accounts.isEmpty) return;
    final active =
        accounts.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['is_active'] as bool? ?? false,
          orElse: () => accounts.first,
        ) ??
        accounts.first;
    final id = active['id'];
    if (id is! num) return;
    ActiveAccountSession.useMt5Account(
      id: id.toInt(),
      login: active['login'] as String?,
    );
  }

  void close({bool shutdownBackend = false}) {
    _apiClient.close();
    if (shutdownBackend) {
      unawaited(_backend.shutdownBackend());
    } else {
      _backend.close();
    }
  }

  Future<void> shutdownBackend() async {
    _apiClient.close();
    await _backend.shutdownBackend();
  }
}
