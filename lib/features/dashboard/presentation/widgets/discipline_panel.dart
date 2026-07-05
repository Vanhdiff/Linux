import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../models/dashboard_mt5_snapshot.dart';

class DisciplinePanel extends StatefulWidget {
  final DashboardMt5Snapshot snapshot;
  final DashboardGuardrailStatus? guardrails;

  const DisciplinePanel({super.key, required this.snapshot, this.guardrails});

  @override
  State<DisciplinePanel> createState() => _DisciplinePanelState();
}

class _DisciplinePanelState extends State<DisciplinePanel> {
  bool _performanceExpanded = true;
  bool _disciplineExpanded = true;
  bool _consistencyExpanded = true;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final score = _DashboardScorecardView.from(widget.snapshot, widget.guardrails);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.text('Discipline breakdown'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                FluentIcons.info,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              _StatusBadge(score: score.totalScore),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ScoreRing(score: score.totalScore),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  _TraderLevel.fromScore(
                    score.totalScore,
                  ).caption(score.totalScore),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ScoreSection(
            label: strings.text(score.performance.label),
            score: score.performance.scoreLabel,
            value: score.performance.progress,
            color: AppColors.success,
            expanded: _performanceExpanded,
            onToggle: () {
              setState(() {
                _performanceExpanded = !_performanceExpanded;
              });
            },
            children: score.performance.rows
                .map(
                  (row) => _CheckRow(
                    strings.text(row.label),
                    row.valueLabel,
                    row.passed,
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 9),
          _ScoreSection(
            label: strings.text(score.discipline.label),
            score: score.discipline.scoreLabel,
            value: score.discipline.progress,
            color: AppColors.primary,
            expanded: _disciplineExpanded,
            onToggle: () {
              setState(() {
                _disciplineExpanded = !_disciplineExpanded;
              });
            },
            subtitle: score.discipline.reason,
            children: score.discipline.rows
                .map(
                  (row) => _CheckRow(
                    strings.text(row.label),
                    row.valueLabel,
                    row.passed,
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 9),
          _ScoreSection(
            label: strings.text(score.consistency.label),
            score: score.consistency.scoreLabel,
            value: score.consistency.progress,
            color: AppColors.primary,
            expanded: _consistencyExpanded,
            onToggle: () {
              setState(() {
                _consistencyExpanded = !_consistencyExpanded;
              });
            },
            children: score.consistency.rows
                .map(
                  (row) => _CheckRow(
                    strings.text(row.label),
                    row.valueLabel,
                    row.passed,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final int score;

  const _StatusBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _badgeText(score),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ScoreSection extends StatelessWidget {
  final String label;
  final String score;
  final double value;
  final Color color;
  final bool expanded;
  final VoidCallback onToggle;
  final String? subtitle;
  final List<Widget> children;

  const _ScoreSection({
    required this.label,
    required this.score,
    required this.value,
    required this.color,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                score,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                expanded
                    ? FluentIcons.chevron_down_small
                    : FluentIcons.chevron_right_small,
                size: 12,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
        if (expanded) ...[
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              subtitle!,
               style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ],
          const SizedBox(height: 7),
          ...children,
        ],
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final String value;
  final bool passed;

  const _CheckRow(this.label, this.value, this.passed);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 132, maxWidth: 168),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 18,
            height: 18,
            child: Container(
              decoration: BoxDecoration(
                color:
                    (passed ? AppColors.success : AppColors.danger).withValues(
                      alpha: 0.12,
                    ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                passed ? FluentIcons.check_mark : FluentIcons.chrome_close,
                size: 10,
                color: passed ? AppColors.success : AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;

  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          score / 100,
          _TraderLevel.fromScore(score).color,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '/100',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScoreRingPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final bgPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke;

    final fgPaint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, bgPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _DashboardScorecardView {
  final int totalScore;
  final _DashboardScoreCategory performance;
  final _DashboardScoreCategory discipline;
  final _DashboardScoreCategory consistency;

  const _DashboardScorecardView({
    required this.totalScore,
    required this.performance,
    required this.discipline,
    required this.consistency,
  });

  factory _DashboardScorecardView.from(
    DashboardMt5Snapshot snapshot,
    DashboardGuardrailStatus? guardrails,
  ) {
    final scorecard = guardrails?.scorecard;
    if (scorecard == null || scorecard.categories.isEmpty) {
      return _DashboardScorecardView._fallback(snapshot, guardrails);
    }

    return _DashboardScorecardView(
      totalScore: scorecard.totalPoints.round().clamp(0, 100),
      performance: _DashboardScoreCategory.fromBackend(
        scorecard.categoryByCode('performance'),
        preferredRowCodes: const [
          'profit_factor',
          'win_rate',
          'expectancy_r',
        ],
        fallbackLabel: 'Performance',
      ),
      discipline: _DashboardScoreCategory.fromBackend(
        scorecard.categoryByCode('discipline'),
        preferredRowCodes: const [
          'daily_loss',
          'max_trades',
          'risk_per_trade',
          'revenge_trade',
        ],
        fallbackLabel: 'Discipline',
      ),
      consistency: _DashboardScoreCategory.fromBackend(
        scorecard.categoryByCode('consistency'),
        preferredRowCodes: const [
          'max_drawdown',
          'trading_time_consistency',
          'position_size_consistency',
        ],
        fallbackLabel: 'Consistency',
      ),
    );
  }

  factory _DashboardScorecardView._fallback(
    DashboardMt5Snapshot snapshot,
    DashboardGuardrailStatus? guardrails,
  ) {
    final maxTrades = guardrails?.maxTradesPerDay ?? snapshot.maxTradesPerDay;
    final maxDailyLoss = guardrails?.maxDailyLoss ?? snapshot.maxDailyLoss;
    final fixedRiskPercent = guardrails?.fixedRiskPercent ?? 0;
    final accountValue = snapshot.equity > 0
        ? snapshot.equity
        : snapshot.accountBalance;
    final apiRiskPerTrade = guardrails == null
        ? 0.0
        : (guardrails.effectiveMaxRiskPerTrade > 0
              ? guardrails.effectiveMaxRiskPerTrade
              : guardrails.maxRiskPerTrade);
    final maxRiskPerTrade = apiRiskPerTrade > 0
        ? apiRiskPerTrade
        : (fixedRiskPercent > 0 && accountValue > 0
              ? accountValue * fixedRiskPercent / 100
              : 0.0);

    final performanceRows = [
      _DashboardScoreRow(
        label: 'Profit factor',
        valueLabel: '${snapshot.profitFactor.toStringAsFixed(2)} / 1.80',
        passed: snapshot.profitFactor >= 1.8,
      ),
      _DashboardScoreRow(
        label: 'Win rate',
        valueLabel: '${snapshot.winRate.toStringAsFixed(1)}% / 45%',
        passed: snapshot.winRate >= 45,
      ),
      _DashboardScoreRow(
        label: 'Expectancy',
        valueLabel: '${snapshot.expectancyR.toStringAsFixed(2)}R / 0.40R',
        passed: snapshot.expectancyR >= 0.4,
      ),
    ];

    final disciplineRows = [
      _DashboardScoreRow(
        label: 'Daily loss',
        valueLabel: maxDailyLoss > 0
            ? '${dashboardMoney(snapshot.todayClosedPnl)} / ${dashboardMoney(maxDailyLoss)}'
            : dashboardMoney(snapshot.todayClosedPnl),
        passed:
            !(guardrails?.isRuleTriggered('max_daily_loss_reached') ??
                (maxDailyLoss > 0 && snapshot.todayClosedPnl <= -maxDailyLoss)),
      ),
      _DashboardScoreRow(
        label: 'Max trades',
        valueLabel: maxTrades > 0
            ? '${snapshot.todayTradeCount} / $maxTrades'
            : '${snapshot.todayTradeCount}',
        passed:
            !(guardrails?.isRuleTriggered('too_many_trades_today') ??
                (maxTrades > 0 && snapshot.todayTradeCount >= maxTrades)),
      ),
      _DashboardScoreRow(
        label: 'Risk per trade',
        valueLabel: fixedRiskPercent > 0
            ? '${fixedRiskPercent.toStringAsFixed(1)}% / ${dashboardMoney(maxRiskPerTrade)}'
            : dashboardMoney(maxRiskPerTrade),
        passed: !(guardrails?.isRuleTriggered('risk_too_high') ?? false),
      ),
      _DashboardScoreRow(
        label: 'Revenge trade',
        valueLabel: (guardrails?.isRuleTriggered('revenge_trading_pattern') ?? false)
            ? '1+'
            : '0',
        passed: !(guardrails?.isRuleTriggered('revenge_trading_pattern') ?? false),
      ),
    ];

    final consistencyRows = [
      _DashboardScoreRow(
        label: 'Max drawdown',
        valueLabel: '${snapshot.maxDrawdownPercent.toStringAsFixed(1)}% / 8%',
        passed: snapshot.maxDrawdownPercent < 8,
      ),
      _DashboardScoreRow(
        label: 'Trading time',
        valueLabel:
            guardrails?.tradingWindowStart != null &&
                guardrails?.tradingWindowEnd != null
            ? 'Window set'
            : 'Not set',
        passed:
            guardrails?.tradingWindowStart != null &&
            guardrails?.tradingWindowEnd != null,
      ),
    ];

    final performance = _DashboardScoreCategory(
      label: 'Performance',
      earnedPoints: performanceRows.where((row) => row.passed).length * 10,
      maxPoints: 40,
      rows: performanceRows,
    );
    final discipline = _DashboardScoreCategory(
      label: 'Discipline',
      earnedPoints: disciplineRows.where((row) => row.passed).length * 10,
      maxPoints: 40,
      rows: disciplineRows,
    );
    final consistency = _DashboardScoreCategory(
      label: 'Consistency',
      earnedPoints: consistencyRows.where((row) => row.passed).length * 10,
      maxPoints: 20,
      rows: consistencyRows,
    );

    return _DashboardScorecardView(
      totalScore:
          (performance.earnedPoints + discipline.earnedPoints + consistency.earnedPoints)
              .round()
              .clamp(0, 100),
      performance: performance,
      discipline: discipline,
      consistency: consistency,
    );
  }
}

class _DashboardScoreCategory {
  final String label;
  final double earnedPoints;
  final double maxPoints;
  final String? reason;
  final List<_DashboardScoreRow> rows;

  const _DashboardScoreCategory({
    required this.label,
    required this.earnedPoints,
    required this.maxPoints,
    required this.rows,
    this.reason,
  });

  factory _DashboardScoreCategory.fromBackend(
    DashboardGuardrailScoreCategory? category, {
    required List<String> preferredRowCodes,
    required String fallbackLabel,
  }) {
    if (category == null) {
      return _DashboardScoreCategory(
        label: fallbackLabel,
        earnedPoints: 0,
        maxPoints: 0,
        rows: const [],
      );
    }

    final rows = <_DashboardScoreRow>[];
    for (final code in preferredRowCodes) {
      final row = category.rowByCode(code);
      if (row == null) continue;
      rows.add(
        _DashboardScoreRow(
          label: row.label,
          valueLabel:
              '${_guardrailValue(row.value, row.unit)} / ${_guardrailValue(row.target, row.unit)}',
          passed: row.passed,
        ),
      );
    }

    return _DashboardScoreCategory(
      label: category.label,
      earnedPoints: category.earnedPoints,
      maxPoints: category.maxPoints,
      reason: category.forcedZero ? category.reason : null,
      rows: rows,
    );
  }

  String get scoreLabel =>
      '${_scoreNumber(earnedPoints)}/${_scoreNumber(maxPoints)}';

  double get progress => maxPoints <= 0 ? 0 : (earnedPoints / maxPoints);
}

class _DashboardScoreRow {
  final String label;
  final String valueLabel;
  final bool passed;

  const _DashboardScoreRow({
    required this.label,
    required this.valueLabel,
    required this.passed,
  });
}

String _guardrailValue(Object? value, String? unit) {
  final number = _double(value);
  if (unit == r'$') {
    return '${number < 0 ? '-' : ''}\$${number.abs().toStringAsFixed(2)}';
  }
  if (unit == '%') {
    return '${number.toStringAsFixed(2)}%';
  }
  if (unit == 'R') {
    return '${number.toStringAsFixed(2)}R';
  }
  if (unit == 'trades' || unit == 'losses') {
    return _int(value).toString();
  }
  if (value is num) {
    return number.toStringAsFixed(number == number.roundToDouble() ? 0 : 2);
  }
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? '-' : text;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _scoreNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

Color _badgeColor(int score) {
  return _TraderLevel.fromScore(score).color;
}

String _badgeText(int score) {
  return _TraderLevel.fromScore(score).label;
}

class _TraderLevel {
  final String label;
  final int? nextThreshold;
  final String? nextLabel;
  final Color color;

  const _TraderLevel({
    required this.label,
    required this.nextThreshold,
    required this.nextLabel,
    required this.color,
  });

  factory _TraderLevel.fromScore(int score) {
    if (score <= 30) {
      return _TraderLevel(
        label: 'Beginner',
        nextThreshold: 31,
        nextLabel: 'Developing',
        color: AppColors.danger,
      );
    }
    if (score <= 50) {
      return _TraderLevel(
        label: 'Developing',
        nextThreshold: 51,
        nextLabel: 'Disciplined',
        color: AppColors.warning,
      );
    }
    if (score <= 70) {
      return _TraderLevel(
        label: 'Disciplined',
        nextThreshold: 71,
        nextLabel: 'Consistent Trader',
        color: AppColors.primary,
      );
    }
    if (score <= 85) {
      return _TraderLevel(
        label: 'Consistent Trader',
        nextThreshold: 86,
        nextLabel: 'Professional',
        color: AppColors.primary,
      );
    }
    if (score <= 95) {
      return _TraderLevel(
        label: 'Professional',
        nextThreshold: 96,
        nextLabel: 'Elite Trader',
        color: AppColors.success,
      );
    }
    return _TraderLevel(
      label: 'Elite Trader',
      nextThreshold: null,
      nextLabel: null,
      color: AppColors.success,
    );
  }

  String caption(int score) {
    if (nextThreshold == null || nextLabel == null) {
      return 'Elite Trader level active';
    }
    return '${nextThreshold! - score} points to $nextLabel';
  }
}
