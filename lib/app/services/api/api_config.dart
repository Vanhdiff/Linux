abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'TRADING_DESK_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const timeout = Duration(seconds: 20);
}
