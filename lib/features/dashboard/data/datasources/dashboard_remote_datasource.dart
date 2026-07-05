import '../../../../app/services/api/api_client.dart';
import '../../../../app/state/active_account_session.dart';
import '../../domain/entities/dashboard_period.dart';
import '../../presentation/models/dashboard_mt5_snapshot.dart';

class DashboardRemoteDataSource {
  final ApiClient _apiClient;
  final int? accountIdOverride;

  DashboardRemoteDataSource({ApiClient? apiClient, this.accountIdOverride})
    : _apiClient = apiClient ?? ApiClient();

  int get accountId => accountIdOverride ?? ActiveAccountSession.accountId;

  Future<DashboardApiView> getDashboard({
    DashboardPeriod period = DashboardPeriod.day,
  }) async {
    final response = await _apiClient.getJson(
      '/api/dashboard',
      queryParameters: {
        'account_id': accountId.toString(),
        'refresh_mt5': 'true',
        'history_days': period.historyDays.toString(),
        'period': period.apiValue,
      },
    );
    return DashboardApiView.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<List<DashboardRecentTrade>> getAllTrades() async {
    final response = await _apiClient.getJson(
      '/api/trades',
      queryParameters: {'account_id': accountId.toString()},
    );
    final trades = (response as List<dynamic>)
        .map(
          (item) => DashboardRecentTrade.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((trade) => trade.status != 'Open')
        .toList();
    trades.sort((a, b) {
      final left =
          a.closedAt ?? a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          b.closedAt ?? b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return trades;
  }

  Future<DashboardGuardrailStatus> getGuardrailStatus() async {
    final response = await _apiClient.getJson(
      '/api/guardrails/status',
      queryParameters: {'account_id': accountId.toString()},
    );
    return DashboardGuardrailStatus.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  void close() {
    _apiClient.close();
  }
}
