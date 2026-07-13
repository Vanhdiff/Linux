import '../../../../app/services/api/api_client.dart';
import '../../../../app/services/backend/backend_process_service.dart';

class GuardrailsRemoteDataSource {
  final ApiClient _apiClient;
  final BackendProcessService _backend;

  GuardrailsRemoteDataSource({
    ApiClient? apiClient,
    BackendProcessService? backend,
  }) : _apiClient = apiClient ?? ApiClient(),
       _backend = backend ?? BackendProcessService();

  Future<Map<String, dynamic>> fetchStatus({required int accountId}) async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson(
      '/api/guardrails/status',
      queryParameters: {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchBlockState({required int accountId}) async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson(
      '/api/guardrails/block-state',
      queryParameters: {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resolveBlock({required int accountId}) async {
    await _backend.ensureRunning();
    final response = await _apiClient.postJson(
      '/api/guardrails/resolve-block',
      {},
      queryParameters: {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMt5TradeBlockerStatus() async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson('/api/mt5/trade-blocker/status');
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMt5ProtectionStatus({
    int? accountId,
  }) async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson(
      '/api/mt5/protection/status',
      queryParameters: accountId == null ? null : {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMt5EaInstallStatus() async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson('/api/mt5/ea/install/status');
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMt5EaSetupReport({int? accountId}) async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson(
      '/api/mt5/ea/setup/report',
      queryParameters: accountId == null ? null : {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMt5DemoHarnessReport({
    int? accountId,
  }) async {
    await _backend.ensureRunning();
    final response = await _apiClient.getJson(
      '/api/mt5/demo-harness/report',
      queryParameters: accountId == null ? null : {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> repairMt5Ea({
    int? accountId,
    String? backendBaseUrl,
    String? terminalId,
  }) async {
    await _backend.ensureRunning();
    final payload = <String, dynamic>{'compile_after_install': true};
    if (accountId != null) payload['account_id'] = accountId;
    if (backendBaseUrl != null) payload['backend_base_url'] = backendBaseUrl;
    if (terminalId != null) payload['terminal_id'] = terminalId;

    final response = await _apiClient.postJson('/api/mt5/ea/repair', payload);
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> installMt5Ea({String? terminalId}) async {
    await _backend.ensureRunning();
    final response = await _apiClient.postJson(
      '/api/mt5/ea/install',
      {},
      queryParameters: terminalId == null
          ? {'compile_after_install': 'true'}
          : {'terminal_id': terminalId, 'compile_after_install': 'true'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> compileMt5Ea({String? terminalId}) async {
    await _backend.ensureRunning();
    final response = await _apiClient.postJson(
      '/api/mt5/ea/compile',
      {},
      queryParameters: terminalId == null ? null : {'terminal_id': terminalId},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> openMt5ExpertsFolder({
    String? terminalId,
  }) async {
    await _backend.ensureRunning();
    final response = await _apiClient.postJson(
      '/api/mt5/ea/open-experts',
      {},
      queryParameters: terminalId == null ? null : {'terminal_id': terminalId},
    );
    return response as Map<String, dynamic>;
  }

  Future<void> saveSettings({
    required int accountId,
    required int maxTradesPerDay,
    required double maxDailyLoss,
    required double maxDailyProfit,
    required double fixedRiskPercent,
    required String tradingWindowStart,
    required String tradingWindowEnd,
    required String newsBlockMode,
    required int newsWindowMinutes,
    required bool tradeBlockingEnabled,
    required bool blockMaxTrades,
    required bool blockMaxDailyLoss,
    required bool blockMaxDailyProfit,
    required bool blockHighImpactNews,
  }) async {
    await _backend.ensureRunning();
    await _apiClient.patchJson(
      '/api/guardrails/settings',
      {
        'max_trades_per_day': maxTradesPerDay,
        'max_daily_loss': maxDailyLoss,
        'block_high_impact_news': blockHighImpactNews,
        'trading_window_start': tradingWindowStart,
        'trading_window_end': tradingWindowEnd,
        'enabled': true,
        'settings': {
          'max_daily_profit': maxDailyProfit,
          'fixed_risk_percent': fixedRiskPercent,
          'trade_blocking_enabled': tradeBlockingEnabled,
          'block_max_trades_per_day': blockMaxTrades,
          'block_max_daily_loss': blockMaxDailyLoss,
          'block_max_daily_profit': blockMaxDailyProfit,
          'news_block_mode': newsBlockMode,
          'news_window_minutes_before': newsWindowMinutes,
          'news_window_minutes_after': newsWindowMinutes,
          'risk_auto_adjust': true,
          'source': 'flutter_guardrails_dialog',
        },
      },
      queryParameters: {'account_id': '$accountId'},
    );
  }

  void close() {
    _apiClient.close();
    _backend.close();
  }
}
