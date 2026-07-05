// ignore_for_file: unused_element

import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../guardrails/presentation/widgets/guardrails_dialog.dart';
import '../models/dashboard_mt5_snapshot.dart';

class RuleBreakPanel extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;
  final DashboardGuardrailStatus? guardrails;
  final VoidCallback? onGuardrailsChanged;

  const RuleBreakPanel({
    super.key,
    required this.snapshot,
    this.guardrails,
    this.onGuardrailsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final maxDailyLoss = guardrails?.maxDailyLoss ?? snapshot.maxDailyLoss;
    final maxLossReached =
        maxDailyLoss > 0 && snapshot.todayClosedPnl <= -maxDailyLoss;
    final triggeredCheck = guardrails?.firstTriggeredCheck;
    final triggeredMessage = _displayMessageFor(
      triggeredCheck,
      snapshot,
      guardrails,
    );

    return Container(
      height: 84,
      padding: EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(onGuardrailsChanged: onGuardrailsChanged),
          Spacer(),
          Text(
            triggeredMessage ??
                (maxLossReached
                    ? strings.text('Max daily loss is reached.')
                    : strings.text(
                        "A quick summary of today's trading rules and loss status.",
                      )),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: triggeredCheck != null || maxLossReached
                  ? AppColors.danger
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final VoidCallback? onGuardrailsChanged;

  const _PanelHeader({this.onGuardrailsChanged});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            strings.text("Today's rule breaks"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(width: 10),
        GestureDetector(
          onTap: () async {
            await showGuardrailsDialog(context);
            onGuardrailsChanged?.call();
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              strings.text('Modify guardrails'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String? _displayMessageFor(
  DashboardGuardrailCheck? check,
  DashboardMt5Snapshot snapshot,
  DashboardGuardrailStatus? guardrails,
) {
  if (check == null) return null;
  if (check.ruleCode != 'risk_too_high') return check.message;

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

  if (fixedRiskPercent > 0 && maxRiskPerTrade > 0) {
    return 'Risk per trade exceeded ${fixedRiskPercent.toStringAsFixed(1)}% (${dashboardMoney(maxRiskPerTrade)}).';
  }
  if (maxRiskPerTrade > 0) {
    return 'Risk per trade exceeded ${dashboardMoney(maxRiskPerTrade)}.';
  }
  return check.message;
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's rule breaks",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6),
        Text(
          "Quick summary of today's trading rules and loss status",
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TradesProgress extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;
  final int maxTrades;

  const _TradesProgress({required this.snapshot, required this.maxTrades});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Trades:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          '${snapshot.todayTradeCount} / $maxTrades',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(width: 6),
        ...List.generate(
          maxTrades.clamp(1, 12),
          (i) => Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(right: i == 4 ? 0 : 6),
            decoration: BoxDecoration(
              color: i < snapshot.todayTradeCount
                  ? AppColors.success
                  : AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ],
    );
  }
}

class _TradingWindowRow extends StatelessWidget {
  final DashboardGuardrailStatus? guardrails;

  const _TradingWindowRow({required this.guardrails});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(
          guardrails?.tradingWindowLabel ?? 'Trading Window not set',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        Text(
          _windowStateText(guardrails),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _windowStateColor(guardrails),
          ),
        ),
      ],
    );
  }
}

class _ClosedPnlSection extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;

  const _ClosedPnlSection({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Closed PnL",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  dashboardMoney(snapshot.todayClosedPnl),
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: snapshot.todayClosedPnl < 0
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
            Icon(FluentIcons.info, size: 15, color: AppColors.textSecondary),
          ],
        ),
      ],
    );
  }
}

class _LossProgressBar extends StatelessWidget {
  final double todayClosedPnl;
  final double maxDailyLoss;
  final bool maxLossReached;

  const _LossProgressBar({
    required this.todayClosedPnl,
    required this.maxDailyLoss,
    required this.maxLossReached,
  });

  @override
  Widget build(BuildContext context) {
    final lossUsed = todayClosedPnl < 0 && maxDailyLoss > 0
        ? (todayClosedPnl.abs() / maxDailyLoss).clamp(0.0, 1.0)
        : 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 10,
        color: AppColors.danger.withValues(alpha: 0.14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: lossUsed,
            child: ColoredBox(
              color: maxLossReached ? Color(0xFFFF7B7F) : AppColors.warning,
            ),
          ),
        ),
      ),
    );
  }
}

class _LimitLabels extends StatelessWidget {
  final double maxDailyLoss;
  final double dailyTarget;

  const _LimitLabels({required this.maxDailyLoss, required this.dailyTarget});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(
          'Max loss  ${dashboardMoney(maxDailyLoss)}',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'Daily Target  ${dashboardMoney(dailyTarget)}',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GuardrailAlert extends StatelessWidget {
  final DashboardGuardrailStatus? guardrails;
  final bool maxLossReached;

  const _GuardrailAlert({
    required this.guardrails,
    required this.maxLossReached,
  });

  @override
  Widget build(BuildContext context) {
    final triggeredCheck = guardrails?.firstTriggeredCheck;
    final isTriggered = triggeredCheck != null || maxLossReached;
    final severity = triggeredCheck?.severity ?? 'critical';
    final color = isTriggered
        ? (severity == 'warning' ? AppColors.warning : AppColors.danger)
        : AppColors.success;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isTriggered ? FluentIcons.error_badge : FluentIcons.check_mark,
            size: 14,
            color: color,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              triggeredCheck?.message ??
                  (maxLossReached
                      ? 'Max daily loss is reached.'
                      : 'Risk guardrails are within limits.'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _windowStateText(DashboardGuardrailStatus? guardrails) {
  final state = guardrails?.isTradingWindowOpen;
  if (state == null) return 'Not set';
  return state ? 'Open' : 'Closed';
}

Color _windowStateColor(DashboardGuardrailStatus? guardrails) {
  final state = guardrails?.isTradingWindowOpen;
  if (state == null) return AppColors.textSecondary;
  return state ? AppColors.primary : AppColors.danger;
}
