import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';

class CalendarDayData {
  final int day;
  final String? dateKey;
  final int lowImpact;
  final int mediumImpact;
  final int highImpact;
  final List<CalendarEventPreview> eventPreviews;
  final bool isToday;
  final bool isMuted;
  final bool isBlocked;
  final bool isSelected;

  const CalendarDayData({
    required this.day,
    this.dateKey,
    this.lowImpact = 0,
    this.mediumImpact = 0,
    this.highImpact = 0,
    this.eventPreviews = const [],
    this.isToday = false,
    this.isMuted = false,
    this.isBlocked = false,
    this.isSelected = false,
  });

  CalendarDayData copyWith({bool? isSelected}) {
    return CalendarDayData(
      day: day,
      dateKey: dateKey,
      lowImpact: lowImpact,
      mediumImpact: mediumImpact,
      highImpact: highImpact,
      eventPreviews: eventPreviews,
      isToday: isToday,
      isMuted: isMuted,
      isBlocked: isBlocked,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class CalendarEventPreview {
  final String title;
  final String impact;

  const CalendarEventPreview({required this.title, required this.impact});
}

class NewsEventData {
  final String id;
  final String time;
  final String currency;
  final String impact;
  final Color impactColor;
  final String event;
  final String actual;
  final String forecast;
  final String previous;

  const NewsEventData({
    this.id = '',
    required this.time,
    required this.currency,
    this.impact = 'unknown',
    required this.impactColor,
    required this.event,
    required this.actual,
    required this.forecast,
    required this.previous,
  });
}

abstract final class NewsFallbackData {
  static const watchlist = ['USD', 'EUR', 'GBP', 'JPY'];

  static const calendarDays = [
    CalendarDayData(
      day: 29,
      isMuted: true,
      highImpact: 3,
      mediumImpact: 5,
      lowImpact: 20,
    ),
    CalendarDayData(day: 30, isMuted: true, highImpact: 3, lowImpact: 20),
    CalendarDayData(
      day: 31,
      isMuted: true,
      highImpact: 3,
      mediumImpact: 5,
      lowImpact: 20,
    ),
    CalendarDayData(day: 1, highImpact: 3, mediumImpact: 2, lowImpact: 31),
    CalendarDayData(day: 2, highImpact: 2, mediumImpact: 10, lowImpact: 12),
    CalendarDayData(day: 3, lowImpact: 1),
    CalendarDayData(day: 4, lowImpact: 3),
    CalendarDayData(day: 5, mediumImpact: 1, lowImpact: 1),
    CalendarDayData(day: 6, lowImpact: 173),
    CalendarDayData(day: 7, highImpact: 3, mediumImpact: 5, lowImpact: 20),
    CalendarDayData(day: 8, isToday: true, isBlocked: true),
    CalendarDayData(day: 9, lowImpact: 20),
    CalendarDayData(day: 10, lowImpact: 2),
    CalendarDayData(day: 11),
    CalendarDayData(day: 12),
    CalendarDayData(day: 13, mediumImpact: 1, lowImpact: 20),
    CalendarDayData(day: 14),
    CalendarDayData(day: 15, isBlocked: true),
    CalendarDayData(day: 16, highImpact: 3, mediumImpact: 2, lowImpact: 32),
    CalendarDayData(day: 17, lowImpact: 3),
    CalendarDayData(day: 18, lowImpact: 20),
    CalendarDayData(day: 19),
    CalendarDayData(day: 20, mediumImpact: 5, lowImpact: 12),
    CalendarDayData(day: 21, lowImpact: 2),
    CalendarDayData(day: 22, highImpact: 1, mediumImpact: 50, lowImpact: 50),
    CalendarDayData(day: 23),
    CalendarDayData(day: 24, lowImpact: 2),
    CalendarDayData(day: 25),
    CalendarDayData(day: 26),
    CalendarDayData(day: 27, mediumImpact: 5, lowImpact: 20),
    CalendarDayData(day: 28),
    CalendarDayData(day: 29, highImpact: 1, mediumImpact: 5, lowImpact: 20),
    CalendarDayData(day: 30, mediumImpact: 5, lowImpact: 20),
    CalendarDayData(day: 31, lowImpact: 20),
    CalendarDayData(day: 1, isMuted: true, lowImpact: 2),
  ];

  static List<NewsEventData> get todayEvents => [
    NewsEventData(
      time: '+ 08:30',
      currency: 'USD',
      impactColor: AppColors.danger,
      event: 'Non-Farm Payrolls (NFP)',
      actual: '180K',
      forecast: '170K',
      previous: '165K',
    ),
    NewsEventData(
      time: '+ 10:00',
      currency: 'USD',
      impactColor: AppColors.warning,
      event: 'ISM Services PMI',
      actual: '52.4',
      forecast: '51.0',
      previous: '50.5',
    ),
    NewsEventData(
      time: '+ 12:30',
      currency: 'USD',
      impactColor: AppColors.danger,
      event: 'CPI (YoY)',
      actual: '2.5%',
      forecast: '2.6%',
      previous: '2.8%',
    ),
    NewsEventData(
      time: '+ 14:00',
      currency: 'USD',
      impactColor: AppColors.warning,
      event: 'JOLTS Job Openings',
      actual: '8.50M',
      forecast: '8.35M',
      previous: '8.20M',
    ),
    NewsEventData(
      time: '+ 16:30',
      currency: 'USD',
      impactColor: AppColors.textSecondary,
      event: 'Crude Oil Inventories (EIA)',
      actual: '-2.5M',
      forecast: '-1.0M',
      previous: '1.2M',
    ),
  ];

  static List<NewsEventData> get upcomingEvents => [
    NewsEventData(
      time: '+ 09:00',
      currency: 'INR',
      impactColor: AppColors.warning,
      event: 'CPI (YoY) (Dec)',
      actual: '',
      forecast: '',
      previous: '',
    ),
    NewsEventData(
      time: '+ 09:30',
      currency: 'EUR',
      impactColor: AppColors.textSecondary,
      event: 'German 12-Month Bubill Auction',
      actual: '',
      forecast: '',
      previous: '',
    ),
    NewsEventData(
      time: '+ 10:00',
      currency: 'USD',
      impactColor: AppColors.textSecondary,
      event: 'SECO Consumer Climate',
      actual: '',
      forecast: '-33',
      previous: '-34',
    ),
  ];
}
