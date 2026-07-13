import 'package:fluent_ui/fluent_ui.dart';
import 'dart:convert';

import '../../data/datasources/journal_remote_datasource.dart';
import '../../data/defaults/journal_defaults.dart';
import '../widgets/journal_charts_panel.dart';
import '../widgets/journal_header.dart';
import '../widgets/journal_overview_panel.dart';
import '../widgets/journal_review_panel.dart';
import '../widgets/journal_trade_details_panel.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  final TextEditingController _reflectionController = TextEditingController(
    text: JournalDefaults.initialReflection,
  );

  String _entryConfluence = JournalDefaults.confluences.first;
  String _entryPlan = JournalDefaults.plans.first;
  String _entryEmotion = JournalDefaults.emotions.first;
  String _exitEmotion = 'Disappointed';
  List<String> _planOptionsState = List<String>.from(JournalDefaults.plans);
  List<String> _confluenceOptionsState = List<String>.from(
    JournalDefaults.confluences,
  );
  List<String> _emotionOptionsState = List<String>.from(
    JournalDefaults.emotions,
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
    _journalRemoteDataSource.close();
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
                      : JournalOverviewPanel(
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
    if (trade == null) return JournalDefaults.title;
    final parts = [
      trade.symbol,
      _directionLabel(trade.direction),
      trade.setup.trim(),
    ].where((part) => part.isNotEmpty && part != '-');
    return parts.join(' - ');
  }

  String _directionLabel(String direction) {
    final lower = direction.toLowerCase();
    if (lower.contains('buy')) return 'Buy';
    if (lower.contains('sell')) return 'Sell';
    return direction.trim().isEmpty ? '-' : direction.trim();
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
        _reviewNotice =
            'Could not save review yet. Refresh once the trading service is ready.';
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
        _overviewError =
            'Trading service is starting. Refresh if journal data does not appear shortly.';
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
