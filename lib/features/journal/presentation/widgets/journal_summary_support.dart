import '../../data/defaults/journal_defaults.dart';
import 'journal_overview_support.dart';

class JournalWeekBarData {
  final String label;
  final double pnl;
  final int tradeCount;
  final double winRate;

  const JournalWeekBarData({
    required this.label,
    required this.pnl,
    required this.tradeCount,
    required this.winRate,
  });
}

List<JournalWeekBarData> journalMonthlyWeekBars({
  required JournalMonthSummary summary,
  required List<JournalWeekSummary> weeks,
}) {
  if (weeks.isNotEmpty) {
    return weeks
        .where((week) => week.tradeCount > 0 || week.pnl != 0)
        .map(
          (week) => JournalWeekBarData(
            label: 'W${week.week}',
            pnl: week.pnl,
            tradeCount: week.tradeCount,
            winRate: week.winRate,
          ),
        )
        .toList(growable: false);
  }

  return [
    for (final entry in summary.weeklyPnl.asMap().entries)
      if (entry.value != 0)
        JournalWeekBarData(
          label: 'W${entry.key + 1}',
          pnl: entry.value,
          tradeCount: 0,
          winRate: 0,
        ),
  ];
}

double journalMaxAbsoluteWeekPnl(Iterable<double> values) {
  return values.fold<double>(1, (max, value) => value > max ? value : max);
}

List<JournalWeekSummary> journalActiveWeeks(List<JournalWeekSummary> weeks) {
  return weeks
      .where((week) => week.tradeCount > 0 || week.pnl != 0)
      .toList(growable: false);
}

String journalWeeklyInsightText(List<JournalWeekSummary> activeWeeks) {
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
    return 'All active weeks are negative. Worst week ${worst.week} closed at ${moneyValue(worst.pnl)} across ${worst.tradeCount} trades. Month win rate is ${weightedWinRate.toStringAsFixed(0)}%.';
  }
  if (worst.pnl < 0) {
    return '$negativeWeeks/${activeWeeks.length} active weeks are negative. Net month PnL is ${moneyValue(netPnl)} across $totalTrades trades. Best week ${best.week}: ${moneyValue(best.pnl)}.';
  }
  return 'All active weeks are profitable. Best week ${best.week} made ${moneyValue(best.pnl)} with ${best.winRate.toStringAsFixed(0)}% win rate across ${best.tradeCount} trades.';
}
