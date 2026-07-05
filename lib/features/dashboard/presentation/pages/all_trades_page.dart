import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/dashboard_remote_datasource.dart';
import '../models/dashboard_mt5_snapshot.dart';

class AllTradesPage extends StatefulWidget {
  const AllTradesPage({super.key});

  @override
  State<AllTradesPage> createState() => _AllTradesPageState();
}

class _AllTradesPageState extends State<AllTradesPage> {
  late final DashboardRemoteDataSource _dataSource;
  List<DashboardRecentTrade> _trades = const [];
  _TradeOutcomeFilter _filter = _TradeOutcomeFilter.all;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _dataSource = DashboardRemoteDataSource();
    _loadTrades();
  }

  @override
  void dispose() {
    _dataSource.close();
    super.dispose();
  }

  Future<void> _loadTrades() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final trades = await _dataSource.getAllTrades();
      if (!mounted) return;
      setState(() {
        _trades = trades;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Backend unavailable: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final filteredTrades = _filteredTrades;
    final totalPnl = filteredTrades.fold<double>(
      0,
      (total, trade) => total + trade.pnl,
    );
    final tradeCountLabel = _filter == _TradeOutcomeFilter.all
        ? '${_trades.length} ${strings.text('Trades').toLowerCase()}'
        : '${filteredTrades.length} / ${_trades.length} ${strings.text('Trades').toLowerCase()}';

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(FluentIcons.back, size: 16),
                  onPressed: () => Navigator.pop(context),
                ),
                SizedBox(width: 10),
                Text(
                  strings.text('All trades'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  tradeCountLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Spacer(),
                _SummaryPill(
                  label: strings.text('Net PnL'),
                  value: dashboardMoney(totalPnl),
                  valueColor: totalPnl < 0
                      ? AppColors.danger
                      : AppColors.success,
                ),
                SizedBox(width: 10),
                IconButton(
                  icon: _isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      : Icon(FluentIcons.refresh, size: 14),
                  onPressed: _isLoading ? null : _loadTrades,
                ),
              ],
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OutcomeFilterBar(
                    selected: _filter,
                    onChanged: (filter) {
                      setState(() {
                        _filter = filter;
                      });
                    },
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: _TradesHistoryTable(
                      trades: filteredTrades,
                      isLoading: _isLoading,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DashboardRecentTrade> get _filteredTrades {
    return switch (_filter) {
      _TradeOutcomeFilter.all => _trades,
      _TradeOutcomeFilter.wins =>
        _trades.where((trade) => trade.pnl > 0).toList(growable: false),
      _TradeOutcomeFilter.losses =>
        _trades.where((trade) => trade.pnl < 0).toList(growable: false),
    };
  }
}

enum _TradeOutcomeFilter { all, wins, losses }

class _OutcomeFilterBar extends StatelessWidget {
  final _TradeOutcomeFilter selected;
  final ValueChanged<_TradeOutcomeFilter> onChanged;

  const _OutcomeFilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        _OutcomeFilterButton(
          label: strings.text('All'),
          selected: selected == _TradeOutcomeFilter.all,
          onPressed: () => onChanged(_TradeOutcomeFilter.all),
        ),
        SizedBox(width: 8),
        _OutcomeFilterButton(
          label: strings.text('Wins'),
          selected: selected == _TradeOutcomeFilter.wins,
          onPressed: () => onChanged(_TradeOutcomeFilter.wins),
        ),
        SizedBox(width: 8),
        _OutcomeFilterButton(
          label: strings.text('Losses'),
          selected: selected == _TradeOutcomeFilter.losses,
          onPressed: () => onChanged(_TradeOutcomeFilter.losses),
        ),
      ],
    );
  }
}

class _OutcomeFilterButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _OutcomeFilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradesHistoryTable extends StatelessWidget {
  final List<DashboardRecentTrade> trades;
  final bool isLoading;

  const _TradesHistoryTable({required this.trades, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: isLoading
            ? Center(child: ProgressRing())
            : trades.isEmpty
            ? Center(
                child: Text(
                  strings.text('No normalized trades yet'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            : Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 1180,
                    child: Column(
                      children: [
                        _HistoryHeader(),
                        Expanded(
                          child: ListView.separated(
                            itemCount: trades.length,
                            separatorBuilder: (_, _) => Container(
                              height: 1,
                              color: AppColors.border.withValues(alpha: 0.65),
                            ),
                            itemBuilder: (context, index) {
                              return _HistoryRow(trade: trades[index]);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      height: 42,
      padding: EdgeInsets.symmetric(horizontal: 14),
      color: AppColors.surfaceAlt,
      child: Row(
        children: [
          _Cell(strings.text('Ticket'), flex: 1),
          _Cell(strings.text('Instrument'), flex: 2),
          _Cell(strings.text('Direction'), flex: 1),
          _Cell(strings.text('Volume'), flex: 1),
          _Cell(strings.text('Entry'), flex: 1),
          _Cell(strings.text('Exit'), flex: 1),
          _Cell(strings.text('P/L'), flex: 1),
          _Cell('R', flex: 1),
          _Cell(strings.text('Status'), flex: 1),
          _Cell(strings.text('Opened'), flex: 2),
          _Cell(strings.text('Closed'), flex: 2),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final DashboardRecentTrade trade;

  const _HistoryRow({required this.trade});

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.direction == 'Buy';
    final pnlColor = trade.pnl < 0
        ? AppColors.danger
        : trade.pnl > 0
        ? AppColors.success
        : AppColors.textPrimary;

    return Container(
      height: 38,
      padding: EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _Cell('${trade.id}', flex: 1),
          _Cell(trade.instrument, flex: 2, strong: true),
          _Cell(
            trade.direction,
            flex: 1,
            color: isBuy ? AppColors.success : AppColors.danger,
            strong: true,
          ),
          _Cell(_formatNumber(trade.volume), flex: 1),
          _Cell(_formatPrice(trade.entryPrice), flex: 1),
          _Cell(_formatPrice(trade.exitPrice), flex: 1),
          _Cell(
            dashboardMoney(trade.pnl),
            flex: 1,
            color: pnlColor,
            strong: true,
          ),
          _Cell(_formatR(trade.rMultiple), flex: 1),
          _Cell(trade.status, flex: 1),
          _Cell(_formatDateTime(trade.openedAt), flex: 2),
          _Cell(_formatDateTime(trade.closedAt), flex: 2),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final int flex;
  final Color? color;
  final bool strong;

  const _Cell(this.text, {required this.flex, this.color, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          color: color ?? AppColors.textSecondary,
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day/$month/${value.year} $hour:$minute';
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _formatPrice(double? value) {
  if (value == null) return '-';
  return value.toStringAsFixed(value.abs() >= 100 ? 2 : 5);
}

String _formatR(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}R';
}
