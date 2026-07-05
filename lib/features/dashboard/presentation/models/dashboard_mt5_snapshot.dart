class DashboardMt5Snapshot {
  final double accountBalance;
  final double equity;
  final double totalClosedPnl;
  final double winRate;
  final double avgRPerTrade;
  final double bestR;
  final double worstR;
  final double profitFactor;
  final int tradeCount;
  final double expectancy;
  final double expectancyR;
  final double averageRiskReward;
  final double averageWinR;
  final double averageLossR;
  final double maxDrawdown;
  final double maxDrawdownPercent;
  final int todayTradeCount;
  final int maxTradesPerDay;
  final double todayClosedPnl;
  final double maxDailyLoss;
  final double dailyTarget;
  final int disciplineScore;
  final int performanceScore;
  final int consistencyScore;
  final int maxLossViolations;
  final int profitTargetViolations;
  final bool maxLossReached;
  final String bestSymbol;
  final String worstSymbol;

  const DashboardMt5Snapshot({
    required this.accountBalance,
    required this.equity,
    required this.totalClosedPnl,
    required this.winRate,
    required this.avgRPerTrade,
    required this.bestR,
    required this.worstR,
    required this.profitFactor,
    required this.tradeCount,
    required this.expectancy,
    required this.expectancyR,
    required this.averageRiskReward,
    required this.averageWinR,
    required this.averageLossR,
    required this.maxDrawdown,
    required this.maxDrawdownPercent,
    required this.todayTradeCount,
    required this.maxTradesPerDay,
    required this.todayClosedPnl,
    required this.maxDailyLoss,
    required this.dailyTarget,
    required this.disciplineScore,
    required this.performanceScore,
    required this.consistencyScore,
    required this.maxLossViolations,
    required this.profitTargetViolations,
    required this.maxLossReached,
    required this.bestSymbol,
    required this.worstSymbol,
  });

  factory DashboardMt5Snapshot.empty() {
    return const DashboardMt5Snapshot(
      accountBalance: 0,
      equity: 0,
      totalClosedPnl: 0,
      winRate: 0,
      avgRPerTrade: 0,
      bestR: 0,
      worstR: 0,
      profitFactor: 0,
      tradeCount: 0,
      expectancy: 0,
      expectancyR: 0,
      averageRiskReward: 0,
      averageWinR: 0,
      averageLossR: 0,
      maxDrawdown: 0,
      maxDrawdownPercent: 0,
      todayTradeCount: 0,
      maxTradesPerDay: 0,
      todayClosedPnl: 0,
      maxDailyLoss: 0,
      dailyTarget: 0,
      disciplineScore: 0,
      performanceScore: 0,
      consistencyScore: 0,
      maxLossViolations: 0,
      profitTargetViolations: 0,
      maxLossReached: false,
      bestSymbol: 'N/A',
      worstSymbol: 'N/A',
    );
  }

  factory DashboardMt5Snapshot.fromDashboardJson(Map<String, dynamic> json) {
    final analytics = _map(json['analytics']);
    final snapshot = _map(json['latest_snapshot']);
    final symbols = _list(analytics['symbols']);
    final today = _map(analytics['today']);
    final guardrailSettings = _map(json['guardrail_settings']);

    final totalClosedPnl = _double(analytics['net_pnl']);
    final todayClosedPnl = _double(today['net_pnl']);
    final todayTradeCount = _int(today['trade_count']);
    final profitFactor = _double(analytics['profit_factor']);
    final averageR = _double(analytics['average_r']);
    final averageWinR = _double(analytics['average_win_r']);
    final averageLossR = _double(analytics['average_loss_r']);
    final maxDrawdown = _double(analytics['max_drawdown']);
    final maxDrawdownPercent = _double(analytics['max_drawdown_percent']);
    final accountBalance = _double(snapshot['balance']);
    final maxDailyLoss = _double(guardrailSettings['max_daily_loss']);
    final maxTradesPerDay = _int(guardrailSettings['max_trades_per_day']);
    final dailyTarget = _double(guardrailSettings['max_daily_profit']);
    final winRate = _double(analytics['win_rate']);
    final expectancyR = _expectancyR(
      winRate: winRate,
      averageWinR: averageWinR,
      averageLossR: averageLossR,
    );

    return DashboardMt5Snapshot(
      accountBalance: accountBalance,
      equity: _double(snapshot['equity']),
      totalClosedPnl: totalClosedPnl,
      winRate: winRate,
      avgRPerTrade: averageR,
      bestR: _double(analytics['best_r']),
      worstR: _double(analytics['worst_r']),
      profitFactor: profitFactor,
      tradeCount: _int(analytics['trade_count']),
      expectancy: _double(analytics['expectancy']),
      expectancyR: expectancyR,
      averageRiskReward: _double(analytics['average_risk_reward']),
      averageWinR: averageWinR,
      averageLossR: averageLossR,
      maxDrawdown: maxDrawdown,
      maxDrawdownPercent: maxDrawdownPercent,
      todayTradeCount: todayTradeCount,
      maxTradesPerDay: maxTradesPerDay,
      todayClosedPnl: todayClosedPnl,
      maxDailyLoss: maxDailyLoss,
      dailyTarget: dailyTarget,
      disciplineScore: _disciplineScore(
        winRate: winRate,
        profitFactor: profitFactor,
        pnl: totalClosedPnl,
      ),
      performanceScore: _performanceScore(
        winRate: winRate,
        pnl: totalClosedPnl,
      ),
      consistencyScore: _ratioScore(8 - maxDrawdownPercent, 8, 20),
      maxLossViolations: maxDailyLoss > 0 && todayClosedPnl <= -maxDailyLoss
          ? 1
          : 0,
      profitTargetViolations: dailyTarget > 0 && todayClosedPnl >= dailyTarget
          ? 1
          : 0,
      maxLossReached: maxDailyLoss > 0 && todayClosedPnl <= -maxDailyLoss,
      bestSymbol: _symbolName(symbols, best: true),
      worstSymbol: _symbolName(symbols, best: false),
    );
  }

  String get riskMessage {
    if (maxLossReached) {
      return 'Max daily loss is reached - stop trading and review your journal before the next session.';
    }
    if (totalClosedPnl < 0) {
      return 'Closed PnL is negative for this period - reduce size and review weak setups, especially $worstSymbol.';
    }
    return 'Positive period so far - best performance is coming from $bestSymbol. Keep risk consistent.';
  }
}

double _expectancyR({
  required double winRate,
  required double averageWinR,
  required double averageLossR,
}) {
  final winRateRatio = (winRate / 100).clamp(0, 1);
  final lossRateRatio = 1 - winRateRatio;
  return (winRateRatio * averageWinR) - (lossRateRatio * averageLossR);
}

class DashboardChartPoint {
  final DateTime? closedAt;
  final double balance;
  final double cumulativePnl;
  final double cumulativeR;
  final double percentReturn;

  const DashboardChartPoint({
    required this.closedAt,
    required this.balance,
    required this.cumulativePnl,
    required this.cumulativeR,
    required this.percentReturn,
  });
}

class DashboardRecentTrade {
  final int id;
  final String instrument;
  final String direction;
  final double volume;
  final double pnl;
  final double? entryPrice;
  final double? exitPrice;
  final double rMultiple;
  final String outcome;
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;

  const DashboardRecentTrade({
    required this.id,
    required this.instrument,
    required this.direction,
    required this.volume,
    required this.pnl,
    required this.entryPrice,
    required this.exitPrice,
    required this.rMultiple,
    required this.outcome,
    required this.status,
    required this.openedAt,
    required this.closedAt,
  });

  factory DashboardRecentTrade.fromJson(Map<String, dynamic> json) {
    final pnl = _double(json['net_pnl']);
    return DashboardRecentTrade(
      id: _int(json['id']),
      instrument: _string(json['symbol'], fallback: 'Unknown'),
      direction: _capitalize(_string(json['direction'], fallback: 'buy')),
      volume: _double(json['volume']),
      pnl: pnl,
      entryPrice: _nullableDouble(json['entry_price'] ?? json['open_price']),
      exitPrice: _nullableDouble(json['exit_price'] ?? json['close_price']),
      rMultiple: _double(json['r_multiple']),
      outcome: pnl > 0
          ? 'Win'
          : pnl < 0
          ? 'Loss'
          : 'BE',
      status: _capitalize(_string(json['status'], fallback: 'closed')),
      openedAt: _date(json['opened_at'] ?? json['open_time']),
      closedAt: _date(json['closed_at']),
    );
  }
}

class DashboardApiView {
  final DashboardMt5Snapshot snapshot;
  final List<DashboardRecentTrade> recentTrades;
  final List<DashboardChartPoint> chartPoints;

  const DashboardApiView({
    required this.snapshot,
    required this.recentTrades,
    required this.chartPoints,
  });

  factory DashboardApiView.sample() {
    return DashboardApiView.empty();
  }

  factory DashboardApiView.empty() {
    return DashboardApiView(
      snapshot: DashboardMt5Snapshot.empty(),
      recentTrades: const [],
      chartPoints: const [],
    );
  }

  factory DashboardApiView.fromJson(Map<String, dynamic> json) {
    final snapshot = DashboardMt5Snapshot.fromDashboardJson(json);
    final recentTrades = _list(
      json['recent_trades'],
    ).map((item) => DashboardRecentTrade.fromJson(_map(item))).toList();
    return DashboardApiView(
      snapshot: snapshot,
      recentTrades: recentTrades,
      chartPoints: _buildChartPoints(json, snapshot),
    );
  }
}

class DashboardGuardrailStatus {
  final bool enabled;
  final String status;
  final int triggeredCount;
  final int criticalCount;
  final int warningCount;
  final int maxTradesPerDay;
  final double maxDailyLoss;
  final double dailyTarget;
  final double maxRiskPerTrade;
  final double effectiveMaxRiskPerTrade;
  final double fixedRiskPercent;
  final String? tradingWindowStart;
  final String? tradingWindowEnd;
  final List<DashboardGuardrailCheck> checks;
  final DashboardGuardrailScorecard scorecard;

  const DashboardGuardrailStatus({
    required this.enabled,
    required this.status,
    required this.triggeredCount,
    required this.criticalCount,
    required this.warningCount,
    required this.maxTradesPerDay,
    required this.maxDailyLoss,
    required this.dailyTarget,
    required this.maxRiskPerTrade,
    required this.effectiveMaxRiskPerTrade,
    required this.fixedRiskPercent,
    required this.tradingWindowStart,
    required this.tradingWindowEnd,
    required this.checks,
    required this.scorecard,
  });

  factory DashboardGuardrailStatus.fromJson(Map<String, dynamic> json) {
    final summary = _map(json['summary']);
    final settings = _map(json['settings']);
    final nested = _map(settings['settings']);

    return DashboardGuardrailStatus(
      enabled: json['enabled'] as bool? ?? false,
      status: _string(json['status'], fallback: 'unknown'),
      triggeredCount: _int(summary['triggered_count']),
      criticalCount: _int(summary['critical_count']),
      warningCount: _int(summary['warning_count']),
      maxTradesPerDay: _int(settings['max_trades_per_day']),
      maxDailyLoss: _double(settings['max_daily_loss']),
      dailyTarget: _double(nested['max_daily_profit']),
      maxRiskPerTrade: _double(settings['max_risk_per_trade']),
      effectiveMaxRiskPerTrade: _double(
        settings['effective_max_risk_per_trade'],
      ),
      fixedRiskPercent: _double(nested['fixed_risk_percent']),
      tradingWindowStart: _nullableString(settings['trading_window_start']),
      tradingWindowEnd: _nullableString(settings['trading_window_end']),
      checks: _list(
        json['checks'],
      ).map((item) => DashboardGuardrailCheck.fromJson(_map(item))).toList(),
      scorecard: DashboardGuardrailScorecard.fromJson(_map(json['scorecard'])),
    );
  }

  bool get hasTriggeredBreaks => triggeredCount > 0;

  DashboardGuardrailCheck? get firstTriggeredCheck {
    for (final check in checks) {
      if (check.triggered) return check;
    }
    return null;
  }

  bool isRuleTriggered(String ruleCode) {
    for (final check in checks) {
      if (check.ruleCode == ruleCode) return check.triggered;
    }
    return false;
  }

  String get tradingWindowLabel {
    final start = _parseWindow(tradingWindowStart);
    final end = _parseWindow(tradingWindowEnd);
    if (start == null || end == null) return 'Trading Window not set';
    return 'Trading Window ${start.time}-${end.time} (${start.zone})';
  }

  bool? get isTradingWindowOpen {
    final start = _parseWindow(tradingWindowStart);
    final end = _parseWindow(tradingWindowEnd);
    if (start == null || end == null) return null;
    final zoneNow = DateTime.now().toUtc().add(
      Duration(minutes: start.utcOffsetMinutes),
    );
    final nowMinutes = zoneNow.hour * 60 + zoneNow.minute;
    final startMinutes = start.minutesOfDay;
    final endMinutes = end.minutesOfDay;
    if (startMinutes <= endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
    }
    return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
  }
}

class DashboardGuardrailScorecard {
  final double totalPoints;
  final double maxPoints;
  final bool tradeBlockingEnabled;
  final List<DashboardGuardrailScoreCategory> categories;

  const DashboardGuardrailScorecard({
    required this.totalPoints,
    required this.maxPoints,
    required this.tradeBlockingEnabled,
    required this.categories,
  });

  factory DashboardGuardrailScorecard.empty() {
    return const DashboardGuardrailScorecard(
      totalPoints: 0,
      maxPoints: 100,
      tradeBlockingEnabled: false,
      categories: [],
    );
  }

  factory DashboardGuardrailScorecard.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return DashboardGuardrailScorecard.empty();
    return DashboardGuardrailScorecard(
      totalPoints: _double(json['total_points']),
      maxPoints: _double(json['max_points']) == 0
          ? 100
          : _double(json['max_points']),
      tradeBlockingEnabled: json['trade_blocking_enabled'] as bool? ?? false,
      categories: _list(json['categories'])
          .map((item) => DashboardGuardrailScoreCategory.fromJson(_map(item)))
          .toList(growable: false),
    );
  }

  DashboardGuardrailScoreCategory? categoryByCode(String code) {
    for (final category in categories) {
      if (category.code == code) return category;
    }
    return null;
  }
}

class DashboardGuardrailScoreCategory {
  final String code;
  final String label;
  final double earnedPoints;
  final double maxPoints;
  final bool forcedZero;
  final String? reason;
  final List<DashboardGuardrailScoreRow> rows;

  const DashboardGuardrailScoreCategory({
    required this.code,
    required this.label,
    required this.earnedPoints,
    required this.maxPoints,
    required this.forcedZero,
    required this.reason,
    required this.rows,
  });

  factory DashboardGuardrailScoreCategory.fromJson(Map<String, dynamic> json) {
    return DashboardGuardrailScoreCategory(
      code: _string(json['code'], fallback: 'category'),
      label: _string(json['label'], fallback: 'Category'),
      earnedPoints: _double(json['earned_points']),
      maxPoints: _double(json['max_points']),
      forcedZero: json['forced_zero'] as bool? ?? false,
      reason: _nullableString(json['reason']),
      rows: _list(json['rows'])
          .map((item) => DashboardGuardrailScoreRow.fromJson(_map(item)))
          .toList(growable: false),
    );
  }

  DashboardGuardrailScoreRow? rowByCode(String code) {
    for (final row in rows) {
      if (row.code == code) return row;
    }
    return null;
  }
}

class DashboardGuardrailScoreRow {
  final String code;
  final String label;
  final bool passed;
  final Object? value;
  final Object? target;
  final String? unit;
  final double earnedPoints;
  final double maxPoints;

  const DashboardGuardrailScoreRow({
    required this.code,
    required this.label,
    required this.passed,
    required this.value,
    required this.target,
    required this.unit,
    required this.earnedPoints,
    required this.maxPoints,
  });

  factory DashboardGuardrailScoreRow.fromJson(Map<String, dynamic> json) {
    return DashboardGuardrailScoreRow(
      code: _string(json['code'], fallback: 'row'),
      label: _string(json['label'], fallback: 'Rule'),
      passed: json['passed'] as bool? ?? false,
      value: json['value'],
      target: json['target'],
      unit: _nullableString(json['unit']),
      earnedPoints: _double(json['earned_points']),
      maxPoints: _double(json['max_points']),
    );
  }
}

class DashboardGuardrailCheck {
  final String ruleCode;
  final bool triggered;
  final String severity;
  final String message;

  const DashboardGuardrailCheck({
    required this.ruleCode,
    required this.triggered,
    required this.severity,
    required this.message,
  });

  factory DashboardGuardrailCheck.fromJson(Map<String, dynamic> json) {
    return DashboardGuardrailCheck(
      ruleCode: _string(json['rule_code'], fallback: 'rule'),
      triggered: json['triggered'] as bool? ?? false,
      severity: _string(json['severity'], fallback: 'info'),
      message: _string(json['message'], fallback: ''),
    );
  }
}

String dashboardMoney(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(2)}';
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<dynamic> _list(dynamic value) {
  if (value is List) return value;
  return const [];
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _string(dynamic value, {String fallback = ''}) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return fallback;
  return text;
}

String? _nullableString(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime? _date(dynamic value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}

_TradingWindowValue? _parseWindow(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final time = parts.last;
  final timeParts = time.split(':');
  if (timeParts.length != 2) return null;
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (hour == null || minute == null) return null;
  return _TradingWindowValue(
    zone: parts.first,
    time: time,
    minutesOfDay: hour * 60 + minute,
    utcOffsetMinutes: _zoneOffsetMinutes(parts.first),
  );
}

int _zoneOffsetMinutes(String zone) {
  final normalized = zone.toUpperCase();
  if (normalized == 'SGT') return 8 * 60;
  final match = RegExp(r'^(UTC|GMT)([+-]\d{1,2})$').firstMatch(normalized);
  if (match == null) return 0;
  return (int.tryParse(match.group(2) ?? '0') ?? 0) * 60;
}

class _TradingWindowValue {
  final String zone;
  final String time;
  final int minutesOfDay;
  final int utcOffsetMinutes;

  const _TradingWindowValue({
    required this.zone,
    required this.time,
    required this.minutesOfDay,
    required this.utcOffsetMinutes,
  });
}

String _symbolName(List<dynamic> symbols, {required bool best}) {
  if (symbols.isEmpty) return 'N/A';
  final sorted = symbols.map(_map).toList()
    ..sort((a, b) => _double(a['net_pnl']).compareTo(_double(b['net_pnl'])));
  final row = best ? sorted.last : sorted.first;
  return _string(row['symbol'], fallback: 'N/A');
}

int _performanceScore({required double winRate, required double pnl}) {
  final winScore = (winRate / 100 * 24).round();
  final pnlScore = pnl >= 0 ? 16 : (16 + pnl / 500).clamp(0, 16).round();
  return (winScore + pnlScore).clamp(0, 40);
}

int _disciplineScore({
  required double winRate,
  required double profitFactor,
  required double pnl,
}) {
  final score = 45 + (winRate / 2) + (profitFactor * 8) + (pnl >= 0 ? 10 : -8);
  return score.round().clamp(0, 100);
}

int _ratioScore(double value, double target, int maxScore) {
  if (target <= 0) return 0;
  return (value / target * maxScore).round().clamp(0, maxScore).toInt();
}

List<DashboardChartPoint> _buildChartPoints(
  Map<String, dynamic> json,
  DashboardMt5Snapshot snapshot,
) {
  final curve = _list(_map(json['drawdown'])['curve']);
  if (curve.isEmpty) return const [];

  final startingBalance = snapshot.accountBalance - snapshot.totalClosedPnl;
  var cumulativeR = 0.0;
  final points = <DashboardChartPoint>[];
  final firstClosedAt = _date(_map(curve.first)['closed_at']);

  points.add(
    DashboardChartPoint(
      closedAt: firstClosedAt,
      balance: startingBalance,
      cumulativePnl: 0,
      cumulativeR: 0,
      percentReturn: 0,
    ),
  );

  for (final item in curve) {
    final row = _map(item);
    final cumulativePnl = _double(row['equity']);
    final riskAmount = _double(row['risk_amount']);
    final rMultiple = row['r_multiple'] == null
        ? _double(row['net_pnl']) / (riskAmount == 0 ? 1000 : riskAmount)
        : _double(row['r_multiple']);
    cumulativeR += rMultiple;
    points.add(
      DashboardChartPoint(
        closedAt: _date(row['closed_at']),
        balance: startingBalance + cumulativePnl,
        cumulativePnl: cumulativePnl,
        cumulativeR: cumulativeR,
        percentReturn: startingBalance == 0
            ? 0
            : cumulativePnl / startingBalance * 100,
      ),
    );
  }

  return points;
}
