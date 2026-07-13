import 'guardrails_defaults.dart';

class GuardrailsFormValues {
  final String maxTradesPerDay;
  final String maxDailyLoss;
  final String maxDailyProfit;
  final String fixedRiskPercent;
  final String tradingWindowStart;
  final String tradingWindowEnd;
  final String newsWindowMinutes;
  final String newsBlockMode;
  final bool tradeBlockingEnabled;
  final bool blockHighImpactNews;

  const GuardrailsFormValues({
    required this.maxTradesPerDay,
    required this.maxDailyLoss,
    required this.maxDailyProfit,
    required this.fixedRiskPercent,
    required this.tradingWindowStart,
    required this.tradingWindowEnd,
    required this.newsWindowMinutes,
    required this.newsBlockMode,
    required this.tradeBlockingEnabled,
    required this.blockHighImpactNews,
  });

  factory GuardrailsFormValues.defaults({
    bool tradeBlockingEnabled = false,
    bool blockHighImpactNews = true,
  }) {
    return GuardrailsFormValues(
      maxTradesPerDay: '${GuardrailsDefaults.maxTradesPerDay}',
      maxDailyLoss: '${GuardrailsDefaults.maxDailyLoss}',
      maxDailyProfit: '${GuardrailsDefaults.maxDailyProfit}',
      fixedRiskPercent: '${GuardrailsDefaults.fixedRiskPercent}',
      tradingWindowStart: GuardrailsDefaults.tradingWindowStart,
      tradingWindowEnd: GuardrailsDefaults.tradingWindowEnd,
      newsWindowMinutes: '${GuardrailsDefaults.newsWindowMinutes}',
      newsBlockMode: GuardrailsDefaults.newsBlockMode,
      tradeBlockingEnabled: tradeBlockingEnabled,
      blockHighImpactNews: blockHighImpactNews,
    );
  }

  factory GuardrailsFormValues.fromSettings(
    Map<String, dynamic>? settings, {
    bool includePendingUpdates = false,
    bool tradeBlockingEnabled = false,
    bool blockHighImpactNews = true,
  }) {
    final root = settings ?? const <String, dynamic>{};
    final nested = _mapOf(root['settings']);
    final pending = includePendingUpdates
        ? _mapOf(nested['pending_update'])
        : const <String, dynamic>{};
    final pendingChanges = includePendingUpdates
        ? _mapOf(pending['changes'])
        : const <String, dynamic>{};
    final pendingNested = includePendingUpdates
        ? _mapOf(pendingChanges['settings'])
        : const <String, dynamic>{};

    Object? rootValue(String key) => pendingChanges[key] ?? root[key];
    Object? nestedValue(String key) => pendingNested[key] ?? nested[key];

    return GuardrailsFormValues(
      maxTradesPerDay:
          '${(rootValue('max_trades_per_day') as num?)?.toInt() ?? GuardrailsDefaults.maxTradesPerDay}',
      maxDailyLoss: formatMoney(
        (rootValue('max_daily_loss') as num?)?.toDouble() ??
            GuardrailsDefaults.maxDailyLoss.toDouble(),
      ),
      maxDailyProfit: formatMoney(
        (nestedValue('max_daily_profit') as num?)?.toDouble() ??
            GuardrailsDefaults.maxDailyProfit.toDouble(),
      ),
      fixedRiskPercent: formatNumber(
        (nestedValue('fixed_risk_percent') as num?)?.toDouble() ??
            GuardrailsDefaults.fixedRiskPercent,
      ),
      tradingWindowStart: extractWindowTime(
        rootValue('trading_window_start'),
        GuardrailsDefaults.tradingWindowStart,
      ),
      tradingWindowEnd: extractWindowTime(
        rootValue('trading_window_end'),
        GuardrailsDefaults.tradingWindowEnd,
      ),
      newsWindowMinutes:
          '${(nestedValue('news_window_minutes_before') as num?)?.toInt() ?? GuardrailsDefaults.newsWindowMinutes}',
      newsBlockMode:
          nestedValue('news_block_mode') as String? ??
          GuardrailsDefaults.newsBlockMode,
      tradeBlockingEnabled:
          nestedValue('trade_blocking_enabled') as bool? ??
          tradeBlockingEnabled,
      blockHighImpactNews:
          rootValue('block_high_impact_news') as bool? ?? blockHighImpactNews,
    );
  }

  static String formatMoney(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  static String formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String extractWindowTime(Object? value, String fallback) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return fallback;
    final parts = text.split(RegExp(r'\s+'));
    return parts.isEmpty ? fallback : parts.last;
  }

  static Map<String, dynamic> _mapOf(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}

class GuardrailsParsedInput {
  final int maxTradesPerDay;
  final double maxDailyLoss;
  final double maxDailyProfit;
  final double fixedRiskPercent;
  final String tradingWindowStart;
  final String tradingWindowEnd;
  final String newsBlockMode;
  final int newsWindowMinutes;
  final bool tradeBlockingEnabled;
  final bool blockHighImpactNews;

  const GuardrailsParsedInput({
    required this.maxTradesPerDay,
    required this.maxDailyLoss,
    required this.maxDailyProfit,
    required this.fixedRiskPercent,
    required this.tradingWindowStart,
    required this.tradingWindowEnd,
    required this.newsBlockMode,
    required this.newsWindowMinutes,
    required this.tradeBlockingEnabled,
    required this.blockHighImpactNews,
  });

  static GuardrailsParsedInput? tryParse({
    required String maxTradesPerDay,
    required String maxDailyLoss,
    required String maxDailyProfit,
    required String fixedRiskPercent,
    required String tradingWindowStart,
    required String tradingWindowEnd,
    required String newsBlockMode,
    required String newsWindowMinutes,
    required bool tradeBlockingEnabled,
    required bool blockHighImpactNews,
  }) {
    final parsedMaxTrades = int.tryParse(maxTradesPerDay.trim());
    final parsedMaxLoss = double.tryParse(maxDailyLoss.trim());
    final parsedMaxProfit = double.tryParse(maxDailyProfit.trim());
    final parsedFixedRisk = double.tryParse(fixedRiskPercent.trim());
    final parsedNewsMinutes = int.tryParse(newsWindowMinutes.trim());

    if (parsedMaxTrades == null ||
        parsedMaxLoss == null ||
        parsedMaxProfit == null ||
        parsedFixedRisk == null ||
        parsedNewsMinutes == null) {
      return null;
    }

    final normalizedWindowStart = _normalizedClockTime(
      tradingWindowStart,
      GuardrailsDefaults.tradingWindowStart,
    );
    final normalizedWindowEnd = _normalizedClockTime(
      tradingWindowEnd,
      GuardrailsDefaults.tradingWindowEnd,
    );

    return GuardrailsParsedInput(
      maxTradesPerDay: parsedMaxTrades,
      maxDailyLoss: parsedMaxLoss,
      maxDailyProfit: parsedMaxProfit,
      fixedRiskPercent: parsedFixedRisk,
      tradingWindowStart: GuardrailsDefaults.tradingWindowValue(
        normalizedWindowStart,
      ),
      tradingWindowEnd: GuardrailsDefaults.tradingWindowValue(
        normalizedWindowEnd,
      ),
      newsBlockMode: newsBlockMode,
      newsWindowMinutes: parsedNewsMinutes,
      tradeBlockingEnabled: tradeBlockingEnabled,
      blockHighImpactNews: blockHighImpactNews,
    );
  }

  static String _normalizedClockTime(String value, String fallback) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }
}
