import 'package:fluent_ui/fluent_ui.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/metric_card.dart';
import '../controllers/dashboard_state.dart';

class DashboardMetricsRow extends StatelessWidget {
  final DashboardState state;

  const DashboardMetricsRow({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final summary = state.summary;

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            title: 'Account Balance',
            value: '\$${summary.accountBalance.toStringAsFixed(2)}',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            title: 'Closed PnL',
            value: '-\$${summary.closedPnl.abs().toStringAsFixed(2)}',
            valueColor: AppColors.danger,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            title: 'Win Rate',
            value: '${summary.winRate.toStringAsFixed(2)}%',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            title: 'Profit Factor',
            value: summary.profitFactor.toStringAsFixed(2),
            subtitle: 'Avg R: +${summary.avgR.toStringAsFixed(2)}R',
          ),
        ),
      ],
    );
  }
}
