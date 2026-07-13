import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_overview_support.dart';
import 'journal_summary_support.dart';

class JournalMonthlySummaryPanel extends StatelessWidget {
  final JournalMonthSummary summary;
  final List<JournalWeekSummary> weeks;

  const JournalMonthlySummaryPanel({
    super.key,
    required this.summary,
    required this.weeks,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final weekBars = journalMonthlyWeekBars(summary: summary, weeks: weeks);

    return AppPanel(
      height: 270,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('Monthly Summary'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: weekBars.isEmpty
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
                          children: _bars(weekBars),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 138,
            child: Column(
              children: [
                JournalSummaryRow(
                  strings.text('Expectancy'),
                  rValue(summary.expectancy),
                ),
                JournalSummaryRow(
                  strings.text('Win rate'),
                  '${summary.winRate.toStringAsFixed(0)}%',
                ),
                JournalSummaryRow(
                  strings.text('Avg win'),
                  moneyValue(summary.avgWin),
                ),
                JournalSummaryRow(
                  strings.text('Avg loss'),
                  moneyValue(summary.avgLoss),
                ),
                JournalSummaryRow(
                  strings.text('Net PnL'),
                  moneyValue(summary.netPnl),
                ),
                JournalSummaryRow(
                  strings.text('Mistakes'),
                  '${summary.mistakes}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _bars(List<JournalWeekBarData> bars) {
    final visibleBars = bars.take(6).toList(growable: false);
    final maxAbs = journalMaxAbsoluteWeekPnl(
      visibleBars.map((bar) => bar.pnl.abs()),
    );

    return [
      for (var index = 0; index < visibleBars.length; index++) ...[
        JournalBar(
          height: 40 + (visibleBars[index].pnl.abs() / maxAbs) * 112,
          label: visibleBars[index].label,
          color: visibleBars[index].pnl >= 0
              ? AppColors.success
              : AppColors.danger,
        ),
        if (index != visibleBars.length - 1) const SizedBox(width: 10),
      ],
    ];
  }
}

class JournalWeeklyBreakdownPanel extends StatelessWidget {
  final List<JournalWeekSummary> weeks;

  const JournalWeeklyBreakdownPanel({super.key, required this.weeks});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final activeWeeks = journalActiveWeeks(weeks);
    final maxAbs = activeWeeks.isEmpty
        ? 1.0
        : journalMaxAbsoluteWeekPnl(activeWeeks.map((week) => week.pnl.abs()));

    return AppPanel(
      height: 270,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('Weekly Breakdown'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: activeWeeks.isEmpty
                ? Center(
                    child: Text(
                      strings.text('No weekly trade stats yet'),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (
                              var index = 0;
                              index < activeWeeks.length;
                              index++
                            ) ...[
                              Expanded(
                                child: JournalWeekColumn(
                                  label: 'W${activeWeeks[index].week}',
                                  value: (activeWeeks[index].pnl.abs() / maxAbs)
                                      .clamp(0.0, 1.0),
                                  pnl: moneyValue(activeWeeks[index].pnl),
                                  tradeCount: activeWeeks[index].tradeCount,
                                  winRate: activeWeeks[index].winRate,
                                ),
                              ),
                              if (index != activeWeeks.length - 1)
                                const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        journalWeeklyInsightText(activeWeeks),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
