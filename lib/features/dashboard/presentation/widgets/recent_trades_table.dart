import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../models/dashboard_mt5_snapshot.dart';

class RecentTradesTable extends StatelessWidget {
  final List<DashboardRecentTrade> trades;
  final VoidCallback? onAllTradesPressed;

  const RecentTradesTable({
    super.key,
    this.trades = const [],
    this.onAllTradesPressed,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final visibleTrades = trades.take(7).toList();

    return Container(
      height: 292,
      padding: EdgeInsets.all(16),
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
              Text(
                strings.text('Recent Trades'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              GestureDetector(
                onTap: onAllTradesPressed,
                child: Row(
                  children: [
                    Text(
                      strings.text('All trades'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      FluentIcons.forward,
                      size: 10,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: _Header(strings.text('Instrument'))),
                Expanded(child: _Header(strings.text('Direction'))),
                Expanded(child: _Header(strings.text('P/L'))),
                Expanded(child: _Header(strings.text('Outcome'))),
                Expanded(flex: 2, child: _Header(strings.text('Closed At'))),
              ],
            ),
          ),
          SizedBox(height: 6),
          if (visibleTrades.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  strings.text('No normalized trades yet'),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ClipRect(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleTrades.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 0),
                  itemBuilder: (context, index) {
                    final trade = visibleTrades[index];
                    return _TradeRow(
                      trade.instrument,
                      trade.direction,
                      dashboardMoney(trade.pnl),
                      trade.outcome,
                      _formatClosedAt(trade.closedAt),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;

  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 9,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  final String instrument;
  final String direction;
  final String pnl;
  final String outcome;
  final String closedAt;

  const _TradeRow(
    this.instrument,
    this.direction,
    this.pnl,
    this.outcome,
    this.closedAt,
  );

  @override
  Widget build(BuildContext context) {
    final isBuy = direction == 'Buy';
    final isLoss = outcome == 'Loss';
    final isWin = outcome == 'Win';

    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  instrument,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              direction,
              style: TextStyle(
                fontSize: 12,
                color: isBuy ? AppColors.success : AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              pnl,
              style: TextStyle(
                fontSize: 12,
                color: pnl.startsWith('-')
                    ? AppColors.danger
                    : pnl == r'$0.00'
                    ? AppColors.textPrimary
                    : AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isWin
                      ? Color(0xFFEAF8F1)
                      : isLoss
                      ? AppColors.danger.withValues(alpha: 0.14)
                      : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  outcome,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isWin
                        ? AppColors.success
                        : isLoss
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              closedAt,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatClosedAt(DateTime? value) {
  if (value == null) return '-';
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}
