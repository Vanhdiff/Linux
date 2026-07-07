import '../../../../app/services/api/api_client.dart';

class GuardrailsRemoteDataSource {
  final ApiClient _apiClient;

  GuardrailsRemoteDataSource({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> fetchStatus({required int accountId}) async {
    final response = await _apiClient.getJson(
      '/api/guardrails/status',
      queryParameters: {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchBlockState({required int accountId}) async {
    final response = await _apiClient.getJson(
      '/api/guardrails/block-state',
      queryParameters: {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resolveBlock({required int accountId}) async {
    final response = await _apiClient.postJson(
      '/api/guardrails/resolve-block',
      {},
      queryParameters: {'account_id': '$accountId'},
    );
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMt5TradeBlockerStatus() async {
    final response = await _apiClient.getJson('/api/mt5/trade-blocker/status');
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
}
