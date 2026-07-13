import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_trade_detail_widgets.dart';
import 'journal_trade_details_support.dart';

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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trade details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 26),
          Text(
            journalTradeMoney(pnl),
            style: TextStyle(
              color: pnlColor,
              fontSize: 31,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'NET PNL',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: JournalTradeMetric(
                  currentTrade?.symbol ?? '-',
                  'INSTRUMENT',
                ),
              ),
              Expanded(
                child: JournalTradeMetric(
                  journalTradeDirectionLabel(currentTrade?.direction),
                  'DIRECTION',
                ),
              ),
              Expanded(
                child: JournalTradeMetric(
                  currentTrade == null
                      ? '0.00'
                      : journalTradeNumber(currentTrade.lots),
                  'LOT SIZE',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const JournalTradeBrokerCallout(),
          const SizedBox(height: 16),
          JournalTradeDetailsSection('Context', [
            JournalTradeDetailRow('Session', currentTrade?.session ?? '-'),
            JournalTradeDetailRow(
              'Duration',
              journalTradeDuration(
                currentTrade?.openedAt,
                currentTrade?.closedAt,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          JournalTradeDetailsSection('Execution', [
            JournalTradeDetailRow(
              'Entry / Exit Price',
              '${journalTradePrice(currentTrade?.entryPrice)} / ${journalTradePrice(currentTrade?.exitPrice)}',
            ),
            JournalTradeDetailRow(
              'Stop Loss',
              journalTradePrice(currentTrade?.stopLoss),
            ),
            JournalTradeDetailRow(
              'Take Profit',
              journalTradePrice(currentTrade?.takeProfit),
            ),
          ]),
          const SizedBox(height: 14),
          JournalTradeDetailsSection('Performance', [
            JournalTradeDetailRow(
              'Risk',
              journalTradeRiskPercentLabel(
                currentTrade?.riskAmount,
                dayStartBalance,
              ),
            ),
            JournalTradeDetailRow(
              'Return (R)',
              journalTradeR(currentTrade?.rMultiple ?? 0),
            ),
          ]),
          const SizedBox(height: 14),
          JournalTradeDetailsSection('Costs', [
            JournalTradeDetailRow(
              'Fees',
              journalTradeMoney(currentTrade?.commission ?? 0),
            ),
            JournalTradeDetailRow(
              'Swap',
              journalTradeMoney(currentTrade?.swap ?? 0),
              valueColor: AppColors.textSecondary,
            ),
          ]),
        ],
      ),
    );
  }
}
