import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_day_trade_widgets.dart';
import 'journal_overview_support.dart';

class JournalDayTradePanel extends StatefulWidget {
  final List<JournalOverviewTrade> trades;
  final JournalDaySummary summary;
  final int? selectedTradeIndex;
  final ValueChanged<int> onTradeClicked;
  final ValueChanged<int> onTradeSelected;

  const JournalDayTradePanel({
    super.key,
    required this.trades,
    required this.summary,
    required this.selectedTradeIndex,
    required this.onTradeClicked,
    required this.onTradeSelected,
  });

  @override
  State<JournalDayTradePanel> createState() => _JournalDayTradePanelState();
}

class _JournalDayTradePanelState extends State<JournalDayTradePanel> {
  JournalTradeFilter _filter = JournalTradeFilter.all;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final visibleTrades = _filteredEntries;

    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dayTitle(widget.summary.dateKey),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.summary.tradeCount} ${strings.text('Trades').toLowerCase()} imported from MT5',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 18),
          Text(
            moneyValue(widget.summary.netPnl),
            style: TextStyle(
              color: widget.summary.netPnl >= 0
                  ? AppColors.success
                  : AppColors.danger,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            strings.text('Net PnL').toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: JournalDayMetric(
                  '${widget.summary.returnPercent.toStringAsFixed(2)}%',
                  strings.text('Return'),
                ),
              ),
              Expanded(
                child: JournalDayMetric(
                  rValue(widget.summary.expectancy),
                  strings.text('Expectancy'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: JournalDayMetric(
                  '${widget.summary.tradeCount}',
                  strings.text('Trades'),
                ),
              ),
              Expanded(
                child: JournalDayMetric(
                  '${widget.summary.ruleBreakCount}',
                  strings.text('Rule break'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          JournalRiskLine(
            label: strings.text('Max daily loss'),
            value: widget.summary.maxDailyLossUsed,
            highIsGood: false,
          ),
          const SizedBox(height: 10),
          JournalRiskLine(
            label: strings.text('Discipline'),
            value: widget.summary.disciplineScore,
          ),
          const SizedBox(height: 18),
          JournalTradeTabs(
            selected: _filter,
            onChanged: (filter) {
              setState(() {
                _filter = filter;
              });
            },
          ),
          const SizedBox(height: 12),
          if (visibleTrades.isEmpty)
            const JournalEmptyTradesNotice()
          else
            ...visibleTrades.map((entry) {
              return JournalTradeListItem(
                trade: entry.value,
                selected: widget.selectedTradeIndex == entry.key,
                onPressed: () => widget.onTradeClicked(entry.key),
                onDoublePressed: () => widget.onTradeSelected(entry.key),
              );
            }),
        ],
      ),
    );
  }

  List<MapEntry<int, JournalOverviewTrade>> get _filteredEntries {
    return widget.trades
        .asMap()
        .entries
        .where((entry) {
          return switch (_filter) {
            JournalTradeFilter.all => true,
            JournalTradeFilter.wins => entry.value.pnl > 0,
            JournalTradeFilter.losses => entry.value.pnl < 0,
          };
        })
        .toList(growable: false);
  }
}
