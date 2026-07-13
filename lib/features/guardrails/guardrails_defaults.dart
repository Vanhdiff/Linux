abstract final class GuardrailsDefaults {
  static const List<String> newsBlockModes = [
    'Before and After',
    'Before only',
    'After only',
  ];
  static const int maxTradesPerDay = 5;
  static const int maxDailyLoss = 3000;
  static const int maxDailyProfit = 5000;
  static const double fixedRiskPercent = 0.5;
  static const String tradingWindowStart = '07:00';
  static const String tradingWindowEnd = '10:00';
  static const int newsWindowMinutes = 30;
  static const String newsBlockMode = 'Before and After';
  static const String tradingWindowTimeZone = 'UTC+7';

  static String tradingWindowValue(String time) {
    return '$tradingWindowTimeZone $time';
  }
}
