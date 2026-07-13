abstract final class JournalDefaults {
  static const title = 'No trade selected';
  static const instrument = '-';
  static const direction = '-';
  static const lotSize = '0.00';
  static const netPnl = '\$0.00';
  static const initialReflection = '';

  static const confluences = [
    'Breakout + Pullback',
    'Mean reversion',
    'Trailing Stop Loss',
  ];

  static const plans = ['A+ setup', 'London session', 'NY session'];

  static const emotions = ['Calm', 'Confident', 'Disappointed', 'Rushed'];

  static const overviewTrades = <JournalOverviewTrade>[];
  static const calendarDays = <JournalCalendarDay>[];
}

class JournalCalendarDay {
  final int day;
  final String? dateKey;
  final double pnl;
  final int tradeCount;
  final bool isMuted;
  final bool hasReview;

  const JournalCalendarDay({
    required this.day,
    this.dateKey,
    this.pnl = 0,
    this.tradeCount = 0,
    this.isMuted = false,
    this.hasReview = false,
  });
}

class JournalMonthSummary {
  final double expectancy;
  final double winRate;
  final double avgWin;
  final double avgLoss;
  final double netPnl;
  final int mistakes;
  final List<double> weeklyPnl;

  const JournalMonthSummary({
    required this.expectancy,
    required this.winRate,
    required this.avgWin,
    required this.avgLoss,
    required this.netPnl,
    required this.mistakes,
    required this.weeklyPnl,
  });

  factory JournalMonthSummary.empty() {
    return const JournalMonthSummary(
      expectancy: 0,
      winRate: 0,
      avgWin: 0,
      avgLoss: 0,
      netPnl: 0,
      mistakes: 0,
      weeklyPnl: [],
    );
  }

  factory JournalMonthSummary.baseline() => JournalMonthSummary.empty();
}

class JournalWeekSummary {
  final int week;
  final double pnl;
  final int tradeCount;
  final double winRate;

  const JournalWeekSummary({
    required this.week,
    required this.pnl,
    required this.tradeCount,
    required this.winRate,
  });

  factory JournalWeekSummary.empty(int week) {
    return JournalWeekSummary(week: week, pnl: 0, tradeCount: 0, winRate: 0);
  }
}

class JournalDaySummary {
  final String dateKey;
  final double netPnl;
  final double returnPercent;
  final double dayStartBalance;
  final double expectancy;
  final int tradeCount;
  final int ruleBreakCount;
  final double maxDailyLossUsed;
  final double disciplineScore;
  final List<JournalOverviewTrade> trades;

  const JournalDaySummary({
    required this.dateKey,
    required this.netPnl,
    required this.returnPercent,
    required this.dayStartBalance,
    required this.expectancy,
    required this.tradeCount,
    required this.ruleBreakCount,
    required this.maxDailyLossUsed,
    required this.disciplineScore,
    required this.trades,
  });

  factory JournalDaySummary.empty([String dateKey = '']) {
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

  factory JournalDaySummary.baseline() => JournalDaySummary.empty();
}

class JournalOverviewTrade {
  final int? id;
  final String symbol;
  final String direction;
  final double pnl;
  final double rMultiple;
  final double lots;
  final String time;
  final String setup;
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double? entryPrice;
  final double? exitPrice;
  final double? stopLoss;
  final double? takeProfit;
  final double commission;
  final double swap;
  final String? session;
  final double? riskAmount;
  final JournalTradeReview? journal;

  const JournalOverviewTrade({
    this.id,
    required this.symbol,
    required this.direction,
    required this.pnl,
    required this.rMultiple,
    required this.lots,
    required this.time,
    required this.setup,
    required this.status,
    this.openedAt,
    this.closedAt,
    this.entryPrice,
    this.exitPrice,
    this.stopLoss,
    this.takeProfit,
    this.commission = 0,
    this.swap = 0,
    this.session,
    this.riskAmount,
    this.journal,
  });
}

class JournalTradeReview {
  final int? id;
  final String? setup;
  final List<String> mistakes;
  final String? emotionBefore;
  final String? emotionAfter;
  final bool? followedPlan;
  final String notes;
  final List<String> screenshotRefs;
  final String reviewStatus;

  const JournalTradeReview({
    this.id,
    this.setup,
    this.mistakes = const [],
    this.emotionBefore,
    this.emotionAfter,
    this.followedPlan,
    this.notes = '',
    this.screenshotRefs = const [],
    this.reviewStatus = 'pending',
  });

  factory JournalTradeReview.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const JournalTradeReview();
    return JournalTradeReview(
      id: json['id'] as int?,
      setup: json['setup'] as String?,
      mistakes: (json['mistakes'] as List<dynamic>? ?? const [])
          .map((item) => '$item')
          .toList(),
      emotionBefore: json['emotion_before'] as String?,
      emotionAfter: json['emotion_after'] as String?,
      followedPlan: json['followed_plan'] as bool?,
      notes: json['notes'] as String? ?? '',
      screenshotRefs: (json['screenshot_refs'] as List<dynamic>? ?? const [])
          .map((item) => '$item')
          .toList(),
      reviewStatus: json['review_status'] as String? ?? 'pending',
    );
  }
}
