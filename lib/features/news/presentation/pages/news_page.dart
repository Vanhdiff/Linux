import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../data/datasources/news_remote_datasource.dart';
import '../../data/defaults/news_fallback_data.dart';
import '../widgets/news_calendar_panel.dart';
import '../widgets/news_events_panel.dart';
import '../widgets/news_header.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  bool _showListNotice = false;
  late DateTime _visibleMonth;
  late List<CalendarDayData> _calendarDays;
  List<NewsEventData> _upcomingEvents = const [];
  List<NewsEventData> _selectedDayEvents = const [];
  String _selectedDayTitle = 'Today';
  String? _selectedDateKey;
  String? _errorMessage;
  bool _triedExternalImport = false;

  final NewsRemoteDataSource _remoteDataSource = NewsRemoteDataSource();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _calendarDays = _buildCalendarGrid(_visibleMonth);
    _selectedDateKey = _dateKey(now);
    _selectedDayTitle = _dayTitle(now);
    _loadNews();
  }

  @override
  void dispose() {
    _remoteDataSource.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 22.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final targetWidth = contentWidth * 0.9;
        final pageWidth = targetWidth < 1120 ? 1120.0 : targetWidth;
        final scrollWidth = pageWidth > contentWidth ? pageWidth : contentWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            18,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: scrollWidth,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: pageWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NewsHeader(
                        selectedMode: _showListNotice
                            ? NewsViewMode.list
                            : NewsViewMode.calendar,
                        onRefresh: () => _loadNews(forceImport: true),
                        onModeChanged: (mode) {
                          setState(() {
                            if (mode == NewsViewMode.list) {
                              _showListNotice = !_showListNotice;
                            } else {
                              _showListNotice = false;
                            }
                          });
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          strings.text(_errorMessage!),
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              NewsCalendarPanel(
                                visibleMonth: _visibleMonth,
                                days: _calendarDays
                                    .map(
                                      (day) => day.copyWith(
                                        isSelected:
                                            day.dateKey == _selectedDateKey,
                                      ),
                                    )
                                    .toList(growable: false),
                                onDaySelected: _selectDay,
                                onPreviousMonth: () => _changeMonth(-1),
                                onNextMonth: () => _changeMonth(1),
                              ),
                              SizedBox(height: 14),
                              UpcomingEventsPanel(events: _upcomingEvents),
                            ],
                          ),
                          if (_showListNotice)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: SizedBox(
                                width: 560,
                                child: NewsEventsPanel(
                                  title: _selectedDateKey == null
                                      ? strings.text(_selectedDayTitle)
                                      : _dayTitle(
                                          DateTime.parse(_selectedDateKey!),
                                          vietnamese: strings.isVietnamese,
                                        ),
                                  events: _selectedDayEvents,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadNews({bool forceImport = false}) async {
    final today = DateTime.now();
    final todayKey = _dateKey(today);
    final windowEndKey = _dateKey(today.add(const Duration(days: 5)));
    final selectedDateKey = _selectedDateKey ?? todayKey;
    try {
      if (forceImport || !_triedExternalImport) {
        _triedExternalImport = true;
        try {
          await _remoteDataSource.importTradingView(
            startDate: todayKey,
            endDate: windowEndKey,
          );
        } catch (_) {
          // Keep rendering the cached calendar if the external provider is unavailable.
          try {
            await _remoteDataSource.importForexFactory();
          } catch (_) {}
        }
      }

      final results = await Future.wait([
        _remoteDataSource.fetchCalendarWindow(
          year: _visibleMonth.year,
          month: _visibleMonth.month,
          startDate: todayKey,
          endDate: windowEndKey,
        ),
        _remoteDataSource.fetchTodayEvents(dateKey: todayKey),
        _remoteDataSource.fetchDayEvents(dateKey: selectedDateKey),
      ]);

      if (!mounted) return;
      if (_selectedDateKey != null && _selectedDateKey != selectedDateKey) {
        return;
      }
      setState(() {
        _calendarDays = results[0] as List<CalendarDayData>;
        _upcomingEvents = results[1] as List<NewsEventData>;
        _selectedDayEvents = results[2] as List<NewsEventData>;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _calendarDays = _buildCalendarGrid(_visibleMonth);
        _upcomingEvents = const [];
        _selectedDayEvents = const [];
        _errorMessage = 'News backend offline - showing empty calendar';
      });
    }
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );

    setState(() {
      _visibleMonth = nextMonth;
      _calendarDays = _buildCalendarGrid(nextMonth);
      _showListNotice = false;
      _selectedDateKey = null;
      _selectedDayTitle = _monthTitle(nextMonth);
      _selectedDayEvents = const [];
    });

    _loadNews();
  }

  Future<void> _selectDay(CalendarDayData day) async {
    final dateKey = day.dateKey;
    if (dateKey == null) return;

    setState(() {
      _showListNotice = true;
      _selectedDateKey = dateKey;
      _selectedDayTitle = _dayTitle(DateTime.parse(dateKey));
    });

    try {
      final events = await _remoteDataSource.fetchDayEvents(dateKey: dateKey);
      if (!mounted) return;
      setState(() => _selectedDayEvents = events);
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedDayEvents = const []);
    }
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _dayTitle(DateTime value, {bool vietnamese = false}) {
    const enWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const viWeekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    const enMonths = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const viMonths = [
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12',
    ];
    final weekday = vietnamese
        ? viWeekdays[value.weekday - 1]
        : enWeekdays[value.weekday - 1];
    final month = vietnamese
        ? viMonths[value.month - 1]
        : enMonths[value.month - 1];
    return '$weekday, $month ${value.day}';
  }

  String _monthTitle(DateTime value) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[value.month - 1]} ${value.year}';
  }

  List<CalendarDayData> _buildCalendarGrid(DateTime visibleMonth) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final leadingDays = firstDay.weekday - DateTime.monday;
    final todayKey = _dateKey(DateTime.now());

    return List.generate(42, (index) {
      final date = DateTime(
        visibleMonth.year,
        visibleMonth.month,
        1 - leadingDays + index,
      );
      final dateKey = _dateKey(date);

      return CalendarDayData(
        day: date.day,
        dateKey: dateKey,
        isToday: dateKey == todayKey,
        isMuted: date.month != visibleMonth.month,
      );
    });
  }
}
