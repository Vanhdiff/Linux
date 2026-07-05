import 'package:fluent_ui/fluent_ui.dart';
import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../models/dashboard_mt5_snapshot.dart';

class DashboardTopMetrics extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;

  const DashboardTopMetrics({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        Expanded(
          child: _SummaryMetricCard(
            title: strings.text('BALANCE'),
            value: dashboardMoney(snapshot.accountBalance),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _SummaryMetricCard(
            title: strings.text('CLOSED P&L'),
            value: dashboardMoney(snapshot.totalClosedPnl),
            valueColor: snapshot.totalClosedPnl < 0
                ? AppColors.danger
                : AppColors.success,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _SummaryMetricCard(
            title: strings.text('WIN RATE'),
            value: '${snapshot.winRate.toStringAsFixed(2)}%',
            trailing: Icon(
              snapshot.winRate >= 50 ? FluentIcons.up : FluentIcons.down,
              size: 12,
              color: snapshot.winRate >= 50
                  ? AppColors.success
                  : AppColors.danger,
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(child: _AvgRMetricCard(snapshot: snapshot)),
        SizedBox(width: 12),
        Expanded(child: _ProfitFactorCard(snapshot: snapshot)),
      ],
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  const _SummaryMetricCard({
    required this.title,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          Spacer(),
          Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) ...[SizedBox(width: 4), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

class _AvgRMetricCard extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;

  const _AvgRMetricCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('AVG R / TRADE'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text(
                  _r(snapshot.avgRPerTrade),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  _r(snapshot.bestR),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  _r(snapshot.worstR),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfitFactorCard extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;

  const _ProfitFactorCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('PROFIT FACTOR'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                Spacer(),
                Row(
                  children: [
                    Text(
                      _formatProfitFactor(snapshot.profitFactor),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(FluentIcons.info, size: 10, color: AppColors.warning),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _r(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}R';
}

String _formatProfitFactor(double value) {
  if (value >= 999) return '∞';
  if (value > 0 && value < 0.01) return '<0.01';
  return value.toStringAsFixed(2);
}
