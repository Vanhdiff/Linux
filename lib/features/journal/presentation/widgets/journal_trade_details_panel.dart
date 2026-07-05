import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../data/journal_sample_data.dart';

class JournalTradeDetailsPanel extends StatelessWidget {
  final JournalOverviewTrade? trade;
  final double dayStartBalance;

  const JournalTradeDetailsPanel({
    super.key,
    required this.trade,
    required this.dayStartBalance,
  });

  @override
  Widget build(BuildContext context) {
    final currentTrade = trade;
    final pnl = currentTrade?.pnl ?? 0;
    final pnlColor = pnl < 0 ? AppColors.danger : AppColors.success;

    return AppPanel(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trade details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 26),
          Text(
            _money(pnl),
            style: TextStyle(
              color: pnlColor,
              fontSize: 31,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'NET PNL',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _TradeMetric(currentTrade?.symbol ?? '-', 'INSTRUMENT'),
              ),
              Expanded(
                child: _TradeMetric(
                  _directionLabel(currentTrade?.direction),
                  'DIRECTION',
                ),
              ),
              Expanded(
                child: _TradeMetric(
                  currentTrade == null
                      ? '0.00'
                      : _formatNumber(currentTrade.lots),
                  'LOT SIZE',
                ),
              ),
            ],
          ),
          SizedBox(height: 22),
          _BrokerCallout(),
          SizedBox(height: 16),
          _DetailsSection('Context', [
            _DetailRow('Session', currentTrade?.session ?? '-'),
            _DetailRow(
              'Duration',
              _duration(currentTrade?.openedAt, currentTrade?.closedAt),
            ),
          ]),
          SizedBox(height: 14),
          _DetailsSection('Execution', [
            _DetailRow(
              'Entry / Exit Price',
              '${_price(currentTrade?.entryPrice)} / ${_price(currentTrade?.exitPrice)}',
            ),
            _DetailRow('Stop Loss', _price(currentTrade?.stopLoss)),
            _DetailRow('Take Profit', _price(currentTrade?.takeProfit)),
          ]),
          SizedBox(height: 14),
          _DetailsSection('Performance', [
            _DetailRow(
              'Risk',
              _riskPercentLabel(currentTrade?.riskAmount, dayStartBalance),
            ),
            _DetailRow('Return (R)', _r(currentTrade?.rMultiple ?? 0)),
          ]),
          SizedBox(height: 14),
          _DetailsSection('Costs', [
            _DetailRow('Fees', _money(currentTrade?.commission ?? 0)),
            _DetailRow(
              'Swap',
              _money(currentTrade?.swap ?? 0),
              valueColor: AppColors.textSecondary,
            ),
          ]),
        ],
      ),
    );
  }
}

String _directionLabel(String? direction) {
  if (direction == null || direction == '-') return '-';
  final lower = direction.toLowerCase();
  if (lower.contains('buy')) return 'Buy';
  if (lower.contains('sell')) return 'Sell';
  return direction.trim().isEmpty ? '-' : direction.trim();
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(0)}';
}

String _formatNumber(double value) {
  final rounded = value.roundToDouble();
  return value == rounded ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

String _price(double? value) {
  if (value == null || value == 0) return '-';
  return value.toStringAsFixed(value.abs() >= 100 ? 2 : 5);
}

String _r(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}R';
}

String _riskPercentLabel(double? riskAmount, double dayStartBalance) {
  if (riskAmount == null || riskAmount <= 0 || dayStartBalance <= 0) return '-';
  final percent = riskAmount / dayStartBalance * 100;
  return '${percent.toStringAsFixed(percent >= 10 ? 1 : 2)}%';
}

String _duration(DateTime? openedAt, DateTime? closedAt) {
  if (openedAt == null || closedAt == null) return '-';
  final duration = closedAt.difference(openedAt).abs();
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '$hours hr ${minutes.toString().padLeft(2, '0')} min';
}

class _BrokerCallout extends StatelessWidget {
  const _BrokerCallout();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Trades auto-import from your broker',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TradeMetric extends StatelessWidget {
  final String value;
  final String label;

  const _TradeMetric(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DetailsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailsSection(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
