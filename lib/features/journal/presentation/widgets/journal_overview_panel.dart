import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_calendar_panel.dart';
import 'journal_day_trade_panel.dart';
import 'journal_overview_support.dart';
import 'journal_summary_panels.dart';

class JournalOverviewPanel extends StatelessWidget {
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

  const JournalOverviewPanel({
    super.key,
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
              const SizedBox(height: 14),
              JournalCalendarPanel(
                visibleMonth: visibleMonth,
                days: calendarDays,
                selectedDayIndex: selectedCalendarDayIndex,
                onDaySelected: onCalendarDaySelected,
                onPreviousMonth: onPreviousMonth,
                onNextMonth: onNextMonth,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: JournalMonthlySummaryPanel(
                      summary: monthSummary,
                      weeks: weekSummary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: JournalWeeklyBreakdownPanel(weeks: weekSummary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 340,
          child: JournalDayTradePanel(
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
        const SizedBox(width: 12),
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
        JournalToolbarButton(
          icon: FluentIcons.calendar,
          label: strings.text('Calendar'),
          selected: true,
        ),
        const SizedBox(width: 8),
        const JournalIconSquare(FluentIcons.refresh),
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
