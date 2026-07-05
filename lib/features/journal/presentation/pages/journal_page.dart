import 'package:fluent_ui/fluent_ui.dart';
import 'dart:convert';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../../data/datasources/journal_remote_datasource.dart';
import '../data/journal_sample_data.dart';
import '../widgets/journal_charts_panel.dart';
import '../widgets/journal_header.dart';
import '../widgets/journal_review_panel.dart';
import '../widgets/journal_trade_details_panel.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  final TextEditingController _reflectionController = TextEditingController(
    text: JournalSampleData.initialReflection,
  );

  String _entryConfluence = JournalSampleData.confluences.first;
  String _entryPlan = JournalSampleData.plans.first;
  String _entryEmotion = JournalSampleData.emotions.first;
  String _exitEmotion = 'Disappointed';
  List<String> _planOptionsState = List<String>.from(JournalSampleData.plans);
  List<String> _confluenceOptionsState = List<String>.from(
    JournalSampleData.confluences,
  );
  List<String> _emotionOptionsState = List<String>.from(
    JournalSampleData.emotions,
  );
  List<String> _managementOptionsState = const ['Partials 1R/2R', 'SL to BE'];
  List<String> _selectedManagementTags = const [];
  List<String> _mistakeOptionsState = const [
    'Added to Position',
    'FOMO',
    'Moved Stop Loss',
  ];
  List<String> _selectedMistakes = const [];
  bool _followedPlan = true;
  bool _savingReview = false;
  String? _reviewNotice;
  bool _showTradeDetail = false;
  int? _selectedCalendarDayIndex;
  int? _selectedTradeIndex;
  List<JournalChartRef> _chartRefs = const [];
  late DateTime _visibleMonth;
  List<JournalCalendarDay> _calendarDays = const [];
  List<JournalOverviewTrade> _overviewTrades = const [];
  JournalMonthSummary _monthSummary = JournalMonthSummary.empty();
  List<JournalWeekSummary> _weekSummary = const [];
  JournalDaySummary _daySummary = JournalDaySummary.empty();
  bool _isLoadingOverview = true;
  String? _overviewError;

  final JournalRemoteDataSource _journalRemoteDataSource =
      JournalRemoteDataSource();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _calendarDays = _buildJournalCalendarGrid(_visibleMonth);
    _selectedCalendarDayIndex = _defaultSelectedDayIndex(_calendarDays);
    _daySummary = _emptyDaySummary(_dateKey(now));
    _loadJournalOverview();
  }

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 28.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final targetWidth = contentWidth * 0.9;
        final pageWidth = targetWidth < 1120 ? 1120.0 : targetWidth;
        final scrollWidth = pageWidth > contentWidth ? pageWidth : contentWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
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
                  child: _showTradeDetail
                      ? _buildTradeDetail()
                      : _JournalOverview(
                          selectedCalendarDayIndex: _selectedCalendarDayIndex,
                          visibleMonth: _visibleMonth,
                          calendarDays: _calendarDays,
                          monthSummary: _monthSummary,
                          weekSummary: _weekSummary,
                          daySummary: _daySummary,
                          trades: _overviewTrades,
                          isLoading: _isLoadingOverview,
                          errorMessage: _overviewError,
                          onCalendarDaySelected: (index) {
                            _selectCalendarDay(index);
                          },
                          onPreviousMonth: () => _changeVisibleMonth(-1),
                          onNextMonth: () => _changeVisibleMonth(1),
                          selectedTradeIndex: _selectedTradeIndex,
                          onTradeClicked: (index) {
                            setState(() => _selectedTradeIndex = index);
                          },
                          onTradeSelected: (index) {
                            final trade = _overviewTrades[index];
                            setState(() {
                              _selectedTradeIndex = index;
                              _loadTradeReviewState(trade);
                              _showTradeDetail = true;
                            });
                          },
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTradeDetail() {
    final trade = _selectedTrade;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JournalHeader(
          title: _detailTitle(trade),
          onBack: () => setState(() => _showTradeDetail = false),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: JournalTradeDetailsPanel(
                trade: trade,
                dayStartBalance: _daySummary.dayStartBalance,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JournalChartsPanel(
                    refs: _chartRefs,
                    onRefsChanged: (refs) {
                      setState(() => _chartRefs = refs);
                      _saveTradeReview();
                    },
                  ),
                  const SizedBox(height: 18),
                  JournalReviewPanel(
                    reflectionController: _reflectionController,
                    followedPlan: _followedPlan,
                    onFollowedPlanChanged: _setFollowedPlan,
                    entryPlan: _entryPlan,
                    plans: _planOptions(trade),
                    onEntryPlanChanged: (value) {
                      setState(() => _entryPlan = value);
                    },
                    onAddPlan: _addPlanOption,
                    entryConfluence: _entryConfluence,
                    confluences: _confluenceOptionsState,
                    onEntryConfluenceChanged: (value) {
                      setState(() => _entryConfluence = value);
                    },
                    onAddConfluence: _addConfluenceOption,
                    entryEmotion: _entryEmotion,
                    exitEmotion: _exitEmotion,
                    emotions: _emotionOptionsState,
                    onEntryEmotionChanged: (value) {
                      setState(() => _entryEmotion = value);
                    },
                    onExitEmotionChanged: (value) {
                      setState(() => _exitEmotion = value);
                    },
                    onAddEmotion: _addEmotionOption,
                    managementTags: _managementOptionsState,
                    selectedManagementTags: _selectedManagementTags,
                    onToggleManagementTag: _toggleManagementTag,
                    onAddManagementTag: _addManagementOption,
                    mistakeTags: _mistakeOptionsState,
                    selectedMistakes: _selectedMistakes,
                    onToggleMistake: _toggleMistake,
                    onAddMistake: _addMistakeOption,
                    saving: _savingReview,
                    notice: _reviewNotice,
                    onSave: _saveTradeReview,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setFollowedPlan(bool value) {
    setState(() => _followedPlan = value);
  }

  JournalOverviewTrade? get _selectedTrade {
    final index = _selectedTradeIndex;
    if (index == null || index < 0 || index >= _overviewTrades.length) {
      return null;
    }
    return _overviewTrades[index];
  }

  String _detailTitle(JournalOverviewTrade? trade) {
    if (trade == null) return JournalSampleData.title;
    final parts = [
      trade.symbol,
      _directionLabel(trade.direction),
      trade.setup.trim(),
    ].where((part) => part.isNotEmpty && part != '-');
    return parts.join(' - ');
  }

  String _directionLabel(String direction) {
    return _tradeDirectionText(direction);
  }

  void _loadTradeReviewState(JournalOverviewTrade trade) {
    final review = trade.journal;
    _entryPlan = _safeChoice(review?.setup ?? trade.setup, _planOptions(trade));
    _entryConfluence = _safeChoice(null, _confluenceOptionsState);
    _entryEmotion = _safeChoice(review?.emotionBefore, _emotionOptionsState);
    _exitEmotion = _safeChoice(review?.emotionAfter, _emotionOptionsState);
    _followedPlan = review?.followedPlan ?? true;
    _selectedMistakes = _mergeKnownSelections(
      review?.mistakes ?? const [],
      _mistakeOptionsState,
      _setMistakeOptions,
    );
    _selectedManagementTags = const [];
    _reflectionController.text = review?.notes ?? '';
    _chartRefs = _decodeChartRefs(review?.screenshotRefs ?? const []);
    _reviewNotice = null;
  }

  String _safeChoice(String? value, List<String> options) {
    if (value != null && value.isNotEmpty && options.contains(value)) {
      return value;
    }
    return options.first;
  }

  List<String> _planOptions(JournalOverviewTrade? trade) {
    final values = <String>[
      ..._planOptionsState,
      if (trade?.setup.isNotEmpty == true) trade!.setup,
      if (trade?.journal?.setup?.isNotEmpty == true) trade!.journal!.setup!,
    ];
    return values.toSet().toList(growable: false);
  }

  List<JournalChartRef> _decodeChartRefs(List<String> refs) {
    final decoded = <JournalChartRef>[];
    for (final ref in refs) {
      try {
        final json = jsonDecode(ref);
        if (json is Map<String, dynamic>) {
          decoded.add(JournalChartRef.fromJson(json));
          continue;
        }
      } catch (_) {
        // Older data may be a plain path. Keep it visible.
      }
      decoded.add(JournalChartRef(timeframe: 'MTF', path: ref));
    }
    return decoded;
  }

  List<String> _encodeChartRefs(List<JournalChartRef> refs) {
    return refs
        .map(
          (ref) => jsonEncode({
            'timeframe': ref.timeframe,
            'path': ref.path,
            'note': ref.note,
          }),
        )
        .toList(growable: false);
  }

  Future<void> _saveTradeReview() async {
    final trade = _selectedTrade;
    final tradeId = trade?.id;
    if (tradeId == null) return;
    setState(() {
      _savingReview = true;
      _reviewNotice = null;
    });
    try {
      await _journalRemoteDataSource.saveTradeJournal(
        tradeId: tradeId,
        setup: _entryPlan,
        mistakes: _selectedMistakes,
        emotionBefore: _entryEmotion,
        emotionAfter: _exitEmotion,
        followedPlan: _followedPlan,
        notes: _reflectionController.text.trim(),
        screenshotRefs: _encodeChartRefs(_chartRefs),
      );
      if (!mounted) return;
      setState(() {
        _savingReview = false;
        _reviewNotice = 'Review saved';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingReview = false;
        _reviewNotice = 'Could not save review: $error';
      });
    }
  }

  void _addPlanOption(String value) {
    setState(() {
      _planOptionsState = _appendUnique(_planOptionsState, value);
      _entryPlan = value;
    });
  }

  void _addConfluenceOption(String value) {
    setState(() {
      _confluenceOptionsState = _appendUnique(_confluenceOptionsState, value);
      _entryConfluence = value;
    });
  }

  void _addEmotionOption(String value) {
    setState(() {
      _emotionOptionsState = _appendUnique(_emotionOptionsState, value);
      _entryEmotion = value;
    });
  }

  void _addManagementOption(String value) {
    setState(() {
      _managementOptionsState = _appendUnique(_managementOptionsState, value);
      _selectedManagementTags = _appendUnique(_selectedManagementTags, value);
    });
  }

  void _addMistakeOption(String value) {
    setState(() {
      _mistakeOptionsState = _appendUnique(_mistakeOptionsState, value);
      _selectedMistakes = _appendUnique(_selectedMistakes, value);
    });
  }

  void _toggleManagementTag(String value) {
    setState(() {
      _selectedManagementTags = _toggleValue(_selectedManagementTags, value);
    });
  }

  void _toggleMistake(String value) {
    setState(() {
      _selectedMistakes = _toggleValue(_selectedMistakes, value);
    });
  }

  void _setMistakeOptions(List<String> options) {
    _mistakeOptionsState = options;
  }

  List<String> _mergeKnownSelections(
    List<String> selected,
    List<String> options,
    ValueChanged<List<String>> setOptions,
  ) {
    final nextOptions = List<String>.from(options);
    for (final value in selected) {
      if (value.trim().isNotEmpty && !nextOptions.contains(value)) {
        nextOptions.add(value);
      }
    }
    setOptions(nextOptions);
    return selected;
  }

  List<String> _appendUnique(List<String> values, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || values.contains(normalized)) {
      return values;
    }
    return [...values, normalized];
  }

  List<String> _toggleValue(List<String> values, String value) {
    if (values.contains(value)) {
      return values.where((item) => item != value).toList(growable: false);
    }
    return [...values, value];
  }

  Future<void> _loadJournalOverview() async {
    setState(() {
      _isLoadingOverview = true;
      _overviewError = null;
    });

    try {
      final results = await Future.wait([
        _journalRemoteDataSource.fetchCalendar(
          year: _visibleMonth.year,
          month: _visibleMonth.month,
        ),
        _journalRemoteDataSource.fetchMonthSummary(
          year: _visibleMonth.year,
          month: _visibleMonth.month,
        ),
        _journalRemoteDataSource.fetchWeekSummary(
          year: _visibleMonth.year,
          month: _visibleMonth.month,
        ),
      ]);

      if (!mounted) return;
      final days = results[0] as List<JournalCalendarDay>;
      final selectedIndex = _defaultSelectedDayIndex(days);
      final selectedDateKey = selectedIndex == null
          ? _dateKey(DateTime(_visibleMonth.year, _visibleMonth.month))
          : days[selectedIndex].dateKey!;
      final daySummary = await _journalRemoteDataSource.fetchDaySummary(
        dateKey: selectedDateKey,
      );

      if (!mounted) return;
      setState(() {
        _calendarDays = days;
        _monthSummary = results[1] as JournalMonthSummary;
        _weekSummary = results[2] as List<JournalWeekSummary>;
        _daySummary = daySummary;
        _overviewTrades = daySummary.trades;
        _selectedCalendarDayIndex = selectedIndex;
        _selectedTradeIndex = null;
        _isLoadingOverview = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _calendarDays = _buildJournalCalendarGrid(_visibleMonth);
        _selectedCalendarDayIndex = _defaultSelectedDayIndex(_calendarDays);
        _daySummary = _emptyDaySummary(
          _selectedCalendarDayIndex == null
              ? _dateKey(DateTime(_visibleMonth.year, _visibleMonth.month))
              : _calendarDays[_selectedCalendarDayIndex!].dateKey!,
        );
        _overviewTrades = const [];
        _isLoadingOverview = false;
        _overviewError = 'Backend offline - no journal data loaded';
      });
    }
  }

  void _changeVisibleMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final days = _buildJournalCalendarGrid(nextMonth);
    final selectedIndex = _defaultSelectedDayIndex(days);
    final selectedDateKey = selectedIndex == null
        ? _dateKey(DateTime(nextMonth.year, nextMonth.month))
        : days[selectedIndex].dateKey!;

    setState(() {
      _visibleMonth = nextMonth;
      _calendarDays = days;
      _selectedCalendarDayIndex = selectedIndex;
      _selectedTradeIndex = null;
      _showTradeDetail = false;
      _daySummary = _emptyDaySummary(selectedDateKey);
      _overviewTrades = const [];
    });

    _loadJournalOverview();
  }

  Future<void> _selectCalendarDay(int index) async {
    setState(() {
      _selectedCalendarDayIndex = index;
      _selectedTradeIndex = null;
    });

    final dateKey = _calendarDays[index].dateKey;
    if (dateKey == null) return;

    try {
      final daySummary = await _journalRemoteDataSource.fetchDaySummary(
        dateKey: dateKey,
      );
      if (!mounted) return;
      setState(() {
        _daySummary = daySummary;
        _overviewTrades = daySummary.trades;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _daySummary = _emptyDaySummary(dateKey);
        _overviewTrades = const [];
      });
    }
  }

  int? _defaultSelectedDayIndex(List<JournalCalendarDay> days) {
    final todayKey = _dateKey(DateTime.now());
    final todayIndex = days.indexWhere((day) => day.dateKey == todayKey);
    if (todayIndex != -1) return todayIndex;
    final tradeIndex = days.indexWhere(
      (day) => !day.isMuted && day.tradeCount > 0,
    );
    return tradeIndex == -1 ? null : tradeIndex;
  }

  List<JournalCalendarDay> _buildJournalCalendarGrid(DateTime visibleMonth) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final leadingDays = firstDay.weekday - DateTime.monday;

    return List.generate(42, (index) {
      final date = DateTime(
        visibleMonth.year,
        visibleMonth.month,
        1 - leadingDays + index,
      );

      return JournalCalendarDay(
        day: date.day,
        dateKey: _dateKey(date),
        isMuted: date.month != visibleMonth.month,
      );
    });
  }

  JournalDaySummary _emptyDaySummary(String dateKey) {
    return JournalDaySummary(
      dateKey: dateKey,
      netPnl: 0,
      returnPercent: 0,
      dayStartBalance: 0,
      expectancy: 0,
      tradeCount: 0,
      ruleBreakCount: 0,
      maxDailyLossUsed: 0,
      disciplineScore: 0,
      trades: const [],
    );
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _JournalOverview extends StatelessWidget {
  final int? selectedCalendarDayIndex;
  final DateTime visibleMonth;
  final List<JournalCalendarDay> calendarDays;
  final JournalMonthSummary monthSummary;
  final List<JournalWeekSummary> weekSummary;
  final JournalDaySummary daySummary;
  final List<JournalOverviewTrade> trades;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<int> onCalendarDaySelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final int? selectedTradeIndex;
  final ValueChanged<int> onTradeClicked;
  final ValueChanged<int> onTradeSelected;

  const _JournalOverview({
    required this.selectedCalendarDayIndex,
    required this.visibleMonth,
    required this.calendarDays,
    required this.monthSummary,
    required this.weekSummary,
    required this.daySummary,
    required this.trades,
    required this.isLoading,
    required this.errorMessage,
    required this.onCalendarDaySelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.selectedTradeIndex,
    required this.onTradeClicked,
    required this.onTradeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverviewHeader(isLoading: isLoading, errorMessage: errorMessage),
              SizedBox(height: 14),
              _JournalCalendarPanel(
                visibleMonth: visibleMonth,
                days: calendarDays,
                selectedDayIndex: selectedCalendarDayIndex,
                onDaySelected: onCalendarDaySelected,
                onPreviousMonth: onPreviousMonth,
                onNextMonth: onNextMonth,
              ),
              SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MonthlySummaryPanel(
                      summary: monthSummary,
                      weeks: weekSummary,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(child: _WeeklyBreakdownPanel(weeks: weekSummary)),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: 18),
        SizedBox(
          width: 340,
          child: _DayTradePanel(
            trades: trades,
            selectedTradeIndex: selectedTradeIndex,
            summary: daySummary,
            onTradeClicked: onTradeClicked,
            onTradeSelected: onTradeSelected,
          ),
        ),
      ],
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;

  const _OverviewHeader({required this.isLoading, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final subtitle = strings.text(_subtitle);
    final subtitleColor = errorMessage == null
        ? AppColors.textSecondary
        : AppColors.warning;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          strings.text('Journal'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: subtitleColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _ToolbarButton(
          icon: FluentIcons.calendar,
          label: strings.text('Calendar'),
          selected: true,
        ),
        SizedBox(width: 8),
        _IconSquare(FluentIcons.refresh),
      ],
    );
  }

  String get _subtitle {
    if (isLoading) {
      return 'Loading journal, calendar, and MT5 trade reviews...';
    }
    if (errorMessage != null) return errorMessage!;
    return 'Trade journal connected - notes, reviews, and calendar are synced from broker data.';
  }
}

class _JournalCalendarPanel extends StatelessWidget {
  final DateTime visibleMonth;
  final List<JournalCalendarDay> days;
  final int? selectedDayIndex;
  final ValueChanged<int> onDaySelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  const _JournalCalendarPanel({
    required this.visibleMonth,
    required this.days,
    required this.selectedDayIndex,
    required this.onDaySelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return AppPanel(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _NavButton(FluentIcons.chevron_left, onPressed: onPreviousMonth),
              SizedBox(width: 6),
              _NavButton(FluentIcons.chevron_right, onPressed: onNextMonth),
              SizedBox(width: 12),
              Text(
                _monthTitle(visibleMonth),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(width: 10),
              Text(
                strings.text('Syncing trades from MT5'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              _LegendDot(AppColors.success, strings.text('Profit')),
              SizedBox(width: 12),
              _LegendDot(AppColors.danger, strings.text('Loss')),
              SizedBox(width: 12),
              _LegendDot(AppColors.warning, strings.text('Reviewed')),
            ],
          ),
          SizedBox(height: 16),
          _WeekdayHeader(),
          SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.24,
            ),
            itemBuilder: (context, index) {
              return _CalendarTradeDay(
                day: days[index],
                selected: selectedDayIndex == index,
                onPressed: () => onDaySelected(index),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarTradeDay extends StatelessWidget {
  final JournalCalendarDay day;
  final bool selected;
  final VoidCallback onPressed;

  const _CalendarTradeDay({
    required this.day,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrades = day.tradeCount > 0;
    final pnlColor = day.pnl >= 0 ? AppColors.success : AppColors.danger;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySoft
              : day.isMuted
              ? AppColors.surfaceAlt
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: day.isMuted
                      ? AppColors.textSecondary.withValues(alpha: 0.55)
                      : AppColors.textPrimary,
                ),
              ),
            ),
            if (day.hasReview)
              Align(
                alignment: Alignment.topLeft,
                child: Icon(
                  FluentIcons.edit_note,
                  size: 13,
                  color: AppColors.warning,
                ),
              ),
            if (hasTrades)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 96,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: pnlColor.withValues(alpha: 0.42)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _money(day.pnl),
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '${day.tradeCount} trade${day.tradeCount == 1 ? '' : 's'}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayTradePanel extends StatefulWidget {
  final List<JournalOverviewTrade> trades;
  final JournalDaySummary summary;
  final int? selectedTradeIndex;
  final ValueChanged<int> onTradeClicked;
  final ValueChanged<int> onTradeSelected;

  const _DayTradePanel({
    required this.trades,
    required this.summary,
    required this.selectedTradeIndex,
    required this.onTradeClicked,
    required this.onTradeSelected,
  });

  @override
  State<_DayTradePanel> createState() => _DayTradePanelState();
}

class _DayTradePanelState extends State<_DayTradePanel> {
  _JournalTradeFilter _filter = _JournalTradeFilter.all;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final visibleTrades = _filteredEntries;

    return AppPanel(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayTitle(widget.summary.dateKey),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            '${widget.summary.tradeCount} ${strings.text('Trades').toLowerCase()} imported from MT5',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          SizedBox(height: 18),
          Text(
            _money(widget.summary.netPnl),
            style: TextStyle(
              color: widget.summary.netPnl >= 0
                  ? AppColors.success
                  : AppColors.danger,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            strings.text('Net PnL').toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DayMetric(
                  '${widget.summary.returnPercent.toStringAsFixed(2)}%',
                  strings.text('Return'),
                ),
              ),
              Expanded(
                child: _DayMetric(
                  _r(widget.summary.expectancy),
                  strings.text('Expectancy'),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DayMetric(
                  '${widget.summary.tradeCount}',
                  strings.text('Trades'),
                ),
              ),
              Expanded(
                child: _DayMetric(
                  '${widget.summary.ruleBreakCount}',
                  strings.text('Rule break'),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          _RiskLine(
            label: strings.text('Max daily loss'),
            value: widget.summary.maxDailyLossUsed,
            highIsGood: false,
          ),
          SizedBox(height: 10),
          _RiskLine(
            label: strings.text('Discipline'),
            value: widget.summary.disciplineScore,
          ),
          SizedBox(height: 18),
          _TradeTabs(
            selected: _filter,
            onChanged: (filter) {
              setState(() {
                _filter = filter;
              });
            },
          ),
          SizedBox(height: 12),
          if (visibleTrades.isEmpty)
            _EmptyTradesNotice()
          else
            ...visibleTrades.map((entry) {
              return _TradeListItem(
                trade: entry.value,
                selected: widget.selectedTradeIndex == entry.key,
                onPressed: () => widget.onTradeClicked(entry.key),
                onDoublePressed: () => widget.onTradeSelected(entry.key),
              );
            }),
        ],
      ),
    );
  }

  List<MapEntry<int, JournalOverviewTrade>> get _filteredEntries {
    return widget.trades
        .asMap()
        .entries
        .where((entry) {
          return switch (_filter) {
            _JournalTradeFilter.all => true,
            _JournalTradeFilter.wins => entry.value.pnl > 0,
            _JournalTradeFilter.losses => entry.value.pnl < 0,
          };
        })
        .toList(growable: false);
  }
}

class _EmptyTradesNotice extends StatelessWidget {
  const _EmptyTradesNotice();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        strings.text('No trades synced for this day.'),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MonthlySummaryPanel extends StatelessWidget {
  final JournalMonthSummary summary;
  final List<JournalWeekSummary> weeks;

  const _MonthlySummaryPanel({required this.summary, required this.weeks});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return AppPanel(
      height: 270,
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('Monthly Summary'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 18),
                Expanded(
                  child: _weekBars.isEmpty
                      ? Center(
                          child: Text(
                            strings.text('No weekly PnL synced yet'),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: _bars(_weekBars),
                        ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 138,
            child: Column(
              children: [
                _SummaryRow(strings.text('Expectancy'), _r(summary.expectancy)),
                _SummaryRow(
                  strings.text('Win rate'),
                  '${summary.winRate.toStringAsFixed(0)}%',
                ),
                _SummaryRow(strings.text('Avg win'), _money(summary.avgWin)),
                _SummaryRow(strings.text('Avg loss'), _money(summary.avgLoss)),
                _SummaryRow(strings.text('Net PnL'), _money(summary.netPnl)),
                _SummaryRow(strings.text('Mistakes'), '${summary.mistakes}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_WeekBarData> get _weekBars {
    if (weeks.isNotEmpty) {
      return weeks
          .where((week) => week.tradeCount > 0 || week.pnl != 0)
          .map(
            (week) => _WeekBarData(
              label: 'W${week.week}',
              pnl: week.pnl,
              tradeCount: week.tradeCount,
              winRate: week.winRate,
            ),
          )
          .toList();
    }

    return [
      for (final entry in summary.weeklyPnl.asMap().entries)
        if (entry.value != 0)
          _WeekBarData(
            label: 'W${entry.key + 1}',
            pnl: entry.value,
            tradeCount: 0,
            winRate: 0,
          ),
    ];
  }

  List<Widget> _bars(List<_WeekBarData> bars) {
    final visibleBars = bars.take(6).toList();
    final maxAbs = visibleBars
        .map((bar) => bar.pnl.abs())
        .fold<double>(1, (max, value) => value > max ? value : max);

    return [
      for (var index = 0; index < visibleBars.length; index++) ...[
        _Bar(
          height: 40 + (visibleBars[index].pnl.abs() / maxAbs) * 112,
          label: visibleBars[index].label,
          color: visibleBars[index].pnl >= 0
              ? AppColors.success
              : AppColors.danger,
        ),
        if (index != visibleBars.length - 1) SizedBox(width: 10),
      ],
    ];
  }
}

class _WeekBarData {
  final String label;
  final double pnl;
  final int tradeCount;
  final double winRate;

  const _WeekBarData({
    required this.label,
    required this.pnl,
    required this.tradeCount,
    required this.winRate,
  });
}

class _WeeklyBreakdownPanel extends StatelessWidget {
  final List<JournalWeekSummary> weeks;

  const _WeeklyBreakdownPanel({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final activeWeeks = weeks
        .where((week) => week.tradeCount > 0 || week.pnl != 0)
        .toList();
    final insight = _insightText(activeWeeks);

    return AppPanel(
      height: 270,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('Weekly Breakdown'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 14),
          if (activeWeeks.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  strings.text('No weekly trade data for this month yet.'),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 104,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final week in activeWeeks.take(6))
                    Expanded(
                      child: _WeekColumn(
                        label: 'Week ${week.week}',
                        value: (week.pnl.abs() / _maxWeekPnl)
                            .clamp(0.08, 1.0)
                            .toDouble(),
                        pnl: _money(week.pnl),
                        tradeCount: week.tradeCount,
                        winRate: week.winRate,
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(FluentIcons.lightbulb, size: 16, color: AppColors.warning),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    insight,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.25,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double get _maxWeekPnl {
    final activeWeeks = weeks.where(
      (week) => week.tradeCount > 0 || week.pnl != 0,
    );
    if (activeWeeks.isEmpty) return 1;
    return activeWeeks
        .map((week) => week.pnl.abs())
        .fold<double>(1, (max, value) => value > max ? value : max);
  }

  String _insightText(List<JournalWeekSummary> activeWeeks) {
    if (activeWeeks.isEmpty) {
      return 'No weekly trade data for this month yet.';
    }

    final ranked = List<JournalWeekSummary>.from(activeWeeks)
      ..sort((a, b) => b.pnl.compareTo(a.pnl));
    final best = ranked.first;
    final worst = ranked.last;
    final totalTrades = activeWeeks.fold<int>(
      0,
      (sum, week) => sum + week.tradeCount,
    );
    final netPnl = activeWeeks.fold<double>(0, (sum, week) => sum + week.pnl);
    final weightedWinRate = totalTrades == 0
        ? 0.0
        : activeWeeks.fold<double>(
                0,
                (sum, week) => sum + week.winRate * week.tradeCount,
              ) /
              totalTrades;
    final negativeWeeks = activeWeeks.where((week) => week.pnl < 0).length;

    if (best.pnl <= 0) {
      return 'All active weeks are negative. Worst week ${worst.week} closed at ${_money(worst.pnl)} across ${worst.tradeCount} trades. Month win rate is ${weightedWinRate.toStringAsFixed(0)}%.';
    }
    if (worst.pnl < 0) {
      return '$negativeWeeks/${activeWeeks.length} active weeks are negative. Net month PnL is ${_money(netPnl)} across $totalTrades trades. Best week ${best.week}: ${_money(best.pnl)}.';
    }
    return 'All active weeks are profitable. Best week ${best.week} made ${_money(best.pnl)} with ${best.winRate.toStringAsFixed(0)}% win rate across ${best.tradeCount} trades.';
  }
}

class _TradeListItem extends StatelessWidget {
  final JournalOverviewTrade trade;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onDoublePressed;

  const _TradeListItem({
    required this.trade,
    required this.selected,
    required this.onPressed,
    required this.onDoublePressed,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = _isBuyDirection(trade.direction);
    final directionText = _tradeDirectionText(trade.direction);
    final pnlColor = trade.pnl >= 0 ? AppColors.success : AppColors.danger;

    return GestureDetector(
      onTap: onPressed,
      onDoubleTap: onDoublePressed,
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            _PairDot(),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        trade.symbol,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        isBuy ? FluentIcons.up : FluentIcons.down,
                        size: 10,
                        color: isBuy ? AppColors.success : AppColors.danger,
                      ),
                      SizedBox(width: 3),
                      Text(
                        directionText,
                        style: TextStyle(
                          color: isBuy ? AppColors.success : AppColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 5),
                  Text(
                    _tradeMetaLine(trade),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money(trade.pnl),
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '${trade.rMultiple > 0 ? '+' : ''}${trade.rMultiple.toStringAsFixed(2)}R',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayMetric extends StatelessWidget {
  final String value;
  final String label;

  const _DayMetric(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RiskLine extends StatelessWidget {
  final String label;
  final double value;
  final bool highIsGood;

  const _RiskLine({
    required this.label,
    required this.value,
    this.highIsGood = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = value > 1 ? value / 100 : value;
    final progress = normalizedValue.clamp(0.0, 1.0);
    final percentLabel = value > 1 ? value.round() : (value * 100).round();
    final color = _barColor(progress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
            Text(
              '$percentLabel%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: progress),
              builder: (context, progress, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Color _barColor(double value) {
    if (highIsGood) {
      return value >= 0.65 ? AppColors.success : AppColors.warning;
    }
    if (value >= 0.85) return AppColors.danger;
    if (value >= 0.5) return AppColors.warning;
    return AppColors.success;
  }
}

bool _isBuyDirection(String direction) {
  return direction.toLowerCase().contains('buy');
}

String _tradeDirectionText(String direction) {
  final lower = direction.toLowerCase();
  if (lower.contains('buy')) return 'Buy';
  if (lower.contains('sell')) return 'Sell';
  return direction.trim().isEmpty ? '-' : direction.trim();
}

String _tradeMetaLine(JournalOverviewTrade trade) {
  final parts = <String>[
    trade.time.trim(),
    if (trade.setup.trim().isNotEmpty) trade.setup.trim(),
    '${trade.lots.toStringAsFixed(2)} lot',
  ];
  return parts.join(' - ');
}

enum _JournalTradeFilter { all, wins, losses }

class _TradeTabs extends StatelessWidget {
  final _JournalTradeFilter selected;
  final ValueChanged<_JournalTradeFilter> onChanged;

  const _TradeTabs({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        _TabChip(
          strings.text('All'),
          selected: selected == _JournalTradeFilter.all,
          onPressed: () => onChanged(_JournalTradeFilter.all),
        ),
        SizedBox(width: 8),
        _TabChip(
          strings.text('Wins'),
          selected: selected == _JournalTradeFilter.wins,
          onPressed: () => onChanged(_JournalTradeFilter.wins),
        ),
        SizedBox(width: 8),
        _TabChip(
          strings.text('Losses'),
          selected: selected == _JournalTradeFilter.losses,
          onPressed: () => onChanged(_JournalTradeFilter.losses),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _TabChip(this.label, {required this.selected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _Weekday('Mon'),
        _Weekday('Tue'),
        _Weekday('Wed'),
        _Weekday('Thu'),
        _Weekday('Fri'),
        _Weekday('Sat'),
        _Weekday('Sun'),
      ],
    );
  }
}

class _Weekday extends StatelessWidget {
  final String label;

  const _Weekday(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final isPositive = value.startsWith('+');
    final isNegative = value.startsWith('-');

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isPositive
                  ? AppColors.success
                  : isNegative
                  ? AppColors.danger
                  : AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final String label;
  final Color color;

  const _Bar({required this.height, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

class _WeekColumn extends StatelessWidget {
  final String label;
  final double value;
  final String pnl;
  final int tradeCount;
  final double winRate;

  const _WeekColumn({
    required this.label,
    required this.value,
    required this.pnl,
    required this.tradeCount,
    required this.winRate,
  });

  @override
  Widget build(BuildContext context) {
    final color = pnl.startsWith('-') ? AppColors.danger : AppColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        SizedBox(height: 6),
        Container(
          height: 50,
          width: 10,
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
          ),
          child: FractionallySizedBox(
            heightFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        SizedBox(height: 6),
        Text(
          pnl,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 2),
        Text(
          '$tradeCount trades - ${winRate.toStringAsFixed(0)}% win',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5),
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconSquare extends StatelessWidget {
  final IconData icon;

  const _IconSquare(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, size: 14, color: AppColors.textSecondary),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _NavButton(this.icon, {this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PairDot extends StatelessWidget {
  const _PairDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 16,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: Color(0xFF2979FF),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1),
              ),
            ),
          ),
          Positioned(
            left: 10,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _money(double value) {
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  return '$sign\$${value.abs().toStringAsFixed(0)}';
}

String _r(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}R';
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

String _dayTitle(String dateKey) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  final date = DateTime.parse(dateKey);
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
}
