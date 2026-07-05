import '../../../../app/services/api/api_client.dart';
import '../../../../app/theme/app_colors.dart';
import '../../presentation/data/news_sample_data.dart';

class NewsRemoteDataSource {
  static const _watchlistCurrencies = [
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'AUD',
    'CAD',
    'CHF',
    'NZD',
  ];

  final ApiClient _apiClient;

  NewsRemoteDataSource({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  Future<void> importForexFactory() async {
    await _apiClient.postJson('/ingest/news/forexfactory', {
      'weeks': ['this'],
    });
  }

  Future<void> importTradingView({
    required String startDate,
    required String endDate,
  }) async {
    await _apiClient.postJson('/ingest/news/tradingview', {
      'start': startDate,
      'end': endDate,
    });
  }

  Future<List<CalendarDayData>> fetchCalendarWindow({
    required int year,
    required int month,
    required String startDate,
    required String endDate,
  }) async {
    final response =
        await _apiClient.getJson(
              '/news/range',
              queryParameters: {
                'start': startDate,
                'end': endDate,
                'currencies': _watchlistCurrencies.join(','),
                'impacts': 'high,medium',
              },
            )
            as Map<String, dynamic>;
    final eventDays = <String, Map<String, dynamic>>{};

    for (final item in response['days'] as List<dynamic>? ?? const []) {
      final json = item as Map<String, dynamic>;
      eventDays[json['date'] as String] = json;
    }

    return _buildMonthGrid(year: year, month: month, eventDays: eventDays);
  }

  Future<List<CalendarDayData>> fetchCalendar({
    required int year,
    required int month,
  }) async {
    final monthKey = '$year-${month.toString().padLeft(2, '0')}';
    final response =
        await _apiClient.getJson(
              '/news/calendar',
              queryParameters: {'month': monthKey},
            )
            as Map<String, dynamic>;
    final eventDays = <String, Map<String, dynamic>>{};

    for (final item in response['days'] as List<dynamic>? ?? const []) {
      final json = item as Map<String, dynamic>;
      eventDays[json['date'] as String] = json;
    }

    return _buildMonthGrid(year: year, month: month, eventDays: eventDays);
  }

  Future<List<NewsEventData>> fetchTodayEvents({required String dateKey}) {
    return fetchDayEvents(dateKey: dateKey);
  }

  Future<List<NewsEventData>> fetchDayEvents({required String dateKey}) async {
    final response =
        await _apiClient.getJson(
              '/news/day',
              queryParameters: {
                'date': dateKey,
                'currencies': _watchlistCurrencies.join(','),
                'impacts': 'high,medium',
              },
            )
            as Map<String, dynamic>;
    return (response['events'] as List<dynamic>? ?? const [])
        .map((item) => _eventFromJson(item as Map<String, dynamic>))
        .toList();
  }

  List<CalendarDayData> _buildMonthGrid({
    required int year,
    required int month,
    required Map<String, Map<String, dynamic>> eventDays,
  }) {
    final firstDay = DateTime(year, month);
    final leadingDays = firstDay.weekday - DateTime.monday;
    final todayKey = _dateKey(DateTime.now());

    return List.generate(42, (index) {
      final date = DateTime(year, month, 1 - leadingDays + index);
      final isCurrentMonth = date.month == month;
      final dateKey = _dateKey(date);
      final eventDay = eventDays[dateKey];
      final counts = eventDay?['counts'] as Map<String, dynamic>? ?? const {};
      final highCount = ((counts['high'] ?? 0) as num).toInt();
      final previews = eventDay == null
          ? const <CalendarEventPreview>[]
          : _eventPreviews(eventDay);

      return CalendarDayData(
        day: date.day,
        dateKey: dateKey,
        lowImpact:
            ((counts['low'] ?? 0) as num).toInt() +
            ((counts['holiday'] ?? 0) as num).toInt() +
            ((counts['unknown'] ?? 0) as num).toInt(),
        mediumImpact: ((counts['medium'] ?? 0) as num).toInt(),
        highImpact: highCount,
        eventPreviews: previews,
        isToday: dateKey == todayKey,
        isMuted: !isCurrentMonth,
        isBlocked: highCount > 0,
      );
    });
  }

  List<CalendarEventPreview> _eventPreviews(Map<String, dynamic> eventDay) {
    final events = (eventDay['events'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final important = events
        .where(
          (event) => event['impact'] == 'high' || event['impact'] == 'medium',
        )
        .toList(growable: false);
    final displayEvents = important.isEmpty ? events : important;

    return displayEvents
        .take(2)
        .map(
          (event) => CalendarEventPreview(
            title: event['title'] as String? ?? '-',
            impact: event['impact'] as String? ?? 'unknown',
          ),
        )
        .toList(growable: false);
  }

  NewsEventData _eventFromJson(Map<String, dynamic> json) {
    final time = DateTime.parse(json['event_time'] as String).toLocal();
    final impact = json['impact'] as String? ?? 'unknown';
    return NewsEventData(
      id: '${json['id'] ?? ''}',
      time:
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      currency: json['currency'] as String? ?? '-',
      impact: impact,
      impactColor: switch (impact) {
        'high' => AppColors.danger,
        'medium' => AppColors.warning,
        _ => AppColors.textSecondary,
      },
      event: json['title'] as String? ?? '-',
      actual: _valueOrDash(json['actual'] as String?),
      forecast: _valueOrDash(json['forecast'] as String?),
      previous: _valueOrDash(json['previous'] as String?),
    );
  }

  String _valueOrDash(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? '-' : normalized;
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
