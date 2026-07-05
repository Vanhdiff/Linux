import '../../../../app/services/api/api_client.dart';
import '../../../../app/state/active_account_session.dart';
import '../../presentation/data/journal_sample_data.dart';

class JournalRemoteDataSource {
  final ApiClient _apiClient;
  final int? accountIdOverride;

  JournalRemoteDataSource({ApiClient? apiClient, this.accountIdOverride})
    : _apiClient = apiClient ?? ApiClient();

  int get accountId => accountIdOverride ?? ActiveAccountSession.accountId;

  Future<List<JournalOverviewTrade>> fetchTrades() async {
    final response = await _apiClient.getJson(
      '/trades',
      queryParameters: {'account_id': '$accountId'},
    );
    final items = response as List<dynamic>;

    return items.map((item) {
      final json = item as Map<String, dynamic>;
      final direction = _titleCase(json['direction'] as String);
      final openedAt = DateTime.parse(json['opened_at'] as String);

      return JournalOverviewTrade(
        id: json['id'] as int,
        symbol: json['symbol'] as String,
        direction: direction,
        pnl: (json['net_pnl'] as num).toDouble(),
        rMultiple: ((json['r_multiple'] ?? 0) as num).toDouble(),
        lots: (json['volume'] as num).toDouble(),
        time: _formatTime(openedAt),
        setup: json['setup'] as String? ?? '',
        status: _titleCase(json['status'] as String),
        openedAt: openedAt,
        closedAt: _dateTime(json['closed_at']),
        entryPrice: _double(json['entry_price']),
        exitPrice: _double(json['exit_price']),
        stopLoss: _double(json['stop_loss']),
        takeProfit: _double(json['take_profit']),
        commission: _double(json['commission']) ?? 0,
        swap: _double(json['swap']) ?? 0,
        session: json['session'] as String?,
        riskAmount: _double(json['risk_amount']),
        journal: JournalTradeReview.fromJson(
          json['journal'] as Map<String, dynamic>?,
        ),
      );
    }).toList();
  }

  Future<List<JournalCalendarDay>> fetchCalendar({
    required int year,
    required int month,
  }) async {
    final response = await _apiClient.getJson(
      '/journal/calendar',
      queryParameters: {
        'account_id': '$accountId',
        'month': _monthKey(year, month),
      },
    );
    final items = (response as Map<String, dynamic>)['days'] as List<dynamic>;
    final tradeDays = <int, Map<String, dynamic>>{};

    for (final item in items) {
      final json = item as Map<String, dynamic>;
      final date = DateTime.parse(json['date'] as String);
      if (date.month == month) {
        tradeDays[date.day] = json;
      }
    }

    return _buildMonthGrid(year: year, month: month, tradeDays: tradeDays);
  }

  List<JournalCalendarDay> _buildMonthGrid({
    required int year,
    required int month,
    required Map<int, Map<String, dynamic>> tradeDays,
  }) {
    final firstDay = DateTime(year, month);
    final leadingDays = firstDay.weekday - DateTime.monday;

    return List.generate(42, (index) {
      final date = DateTime(year, month, 1 - leadingDays + index);
      final isCurrentMonth = date.month == month;
      final tradeDay = isCurrentMonth ? tradeDays[date.day] : null;

      return JournalCalendarDay(
        day: date.day,
        dateKey: _dateKey(date),
        pnl: ((tradeDay?['net_pnl'] ?? tradeDay?['pnl'] ?? 0) as num)
            .toDouble(),
        tradeCount: ((tradeDay?['trade_count'] ?? 0) as num).toInt(),
        isMuted: !isCurrentMonth,
        hasReview: tradeDay?['has_review'] as bool? ?? false,
      );
    });
  }

  Future<JournalMonthSummary> fetchMonthSummary({
    required int year,
    required int month,
  }) async {
    final response =
        await _apiClient.getJson(
              '/journal/month-summary',
              queryParameters: {
                'account_id': '$accountId',
                'month': _monthKey(year, month),
              },
            )
            as Map<String, dynamic>;
    final summary = response['summary'] as Map<String, dynamic>;
    final netPnl = ((summary['net_pnl'] ?? 0) as num).toDouble();
    final mistakes = (response['mistake_frequency'] as List<dynamic>? ?? [])
        .fold<int>(0, (total, item) {
          final json = item as Map<String, dynamic>;
          return total + ((json['count'] ?? 0) as num).toInt();
        });
    final weekly = response['weekly_breakdown'] as List<dynamic>? ?? [];

    return JournalMonthSummary(
      expectancy: ((summary['average_r'] ?? summary['expectancy'] ?? 0) as num)
          .toDouble(),
      winRate: ((summary['win_rate'] ?? 0) as num).toDouble(),
      avgWin: ((summary['avg_win'] ?? 0) as num).toDouble(),
      avgLoss: ((summary['avg_loss'] ?? 0) as num).toDouble(),
      netPnl: netPnl,
      mistakes: mistakes,
      weeklyPnl: weekly.map((item) {
        final json = item as Map<String, dynamic>;
        return ((json['net_pnl'] ?? 0) as num).toDouble();
      }).toList(),
    );
  }

  Future<List<JournalWeekSummary>> fetchWeekSummary({
    required int year,
    required int month,
  }) async {
    final response =
        await _apiClient.getJson(
              '/journal/month-summary',
              queryParameters: {
                'account_id': '$accountId',
                'month': _monthKey(year, month),
              },
            )
            as Map<String, dynamic>;
    final items = response['weekly_breakdown'] as List<dynamic>? ?? [];

    return items.map((item) {
      final json = item as Map<String, dynamic>;
      final period = json['period'] as String? ?? 'W0';
      return JournalWeekSummary(
        week: int.tryParse(period.split('W').last) ?? 0,
        pnl: ((json['net_pnl'] ?? 0) as num).toDouble(),
        tradeCount: ((json['trade_count'] ?? 0) as num).toInt(),
        winRate: ((json['win_rate'] ?? 0) as num).toDouble(),
      );
    }).toList();
  }

  Future<JournalDaySummary> fetchDaySummary({required String dateKey}) async {
    final response =
        await _apiClient.getJson(
              '/journal/day',
              queryParameters: {'account_id': '$accountId', 'date': dateKey},
            )
            as Map<String, dynamic>;
    final summary = response['summary'] as Map<String, dynamic>;

    final trades = (response['trades'] as List<dynamic>).map((item) {
      final json = item as Map<String, dynamic>;
      final direction = _titleCase(json['direction'] as String);
      final openedAt = DateTime.parse(json['opened_at'] as String);

      return JournalOverviewTrade(
        id: json['id'] as int,
        symbol: json['symbol'] as String,
        direction: direction,
        pnl: (json['net_pnl'] as num).toDouble(),
        rMultiple: ((json['r_multiple'] ?? 0) as num).toDouble(),
        lots: (json['volume'] as num).toDouble(),
        time: _formatTime(openedAt),
        setup: json['setup'] as String? ?? '',
        status: _titleCase(json['status'] as String),
        openedAt: openedAt,
        closedAt: _dateTime(json['closed_at']),
        entryPrice: _double(json['entry_price']),
        exitPrice: _double(json['exit_price']),
        stopLoss: _double(json['stop_loss']),
        takeProfit: _double(json['take_profit']),
        commission: _double(json['commission']) ?? 0,
        swap: _double(json['swap']) ?? 0,
        session: json['session'] as String?,
        riskAmount: _double(json['risk_amount']),
        journal: JournalTradeReview.fromJson(
          json['journal'] as Map<String, dynamic>?,
        ),
      );
    }).toList();

    return JournalDaySummary(
      dateKey: response['date'] as String,
      netPnl: ((summary['net_pnl'] ?? 0) as num).toDouble(),
      returnPercent: ((summary['return_percent'] ?? 0) as num).toDouble(),
      dayStartBalance: ((summary['day_start_balance'] ?? 0) as num).toDouble(),
      expectancy: ((summary['average_r'] ?? summary['expectancy'] ?? 0) as num)
          .toDouble(),
      tradeCount: ((summary['trade_count'] ?? 0) as num).toInt(),
      ruleBreakCount: ((summary['rule_break_count'] ?? 0) as num).toInt(),
      maxDailyLossUsed: ((summary['max_daily_loss_used'] ?? 0) as num)
          .toDouble(),
      disciplineScore: ((summary['discipline_score'] ?? 0) as num).toDouble(),
      trades: trades,
    );
  }

  Future<JournalTradeReview> saveTradeJournal({
    required int tradeId,
    required String? setup,
    required List<String> mistakes,
    required String? emotionBefore,
    required String? emotionAfter,
    required bool followedPlan,
    required String notes,
    required List<String> screenshotRefs,
  }) async {
    final response = await _apiClient.putJson('/api/journals/trades/$tradeId', {
      'setup': setup,
      'mistakes': mistakes,
      'emotion_before': emotionBefore,
      'emotion_after': emotionAfter,
      'followed_plan': followedPlan,
      'notes': notes,
      'screenshot_refs': screenshotRefs,
      'review_status': 'reviewed',
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    });
    return JournalTradeReview.fromJson(response as Map<String, dynamic>);
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }

  static double? _double(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _monthKey(int year, int month) {
    return '$year-${month.toString().padLeft(2, '0')}';
  }
}
