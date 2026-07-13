import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_overview_support.dart';

enum JournalTradeFilter { all, wins, losses }

class JournalEmptyTradesNotice extends StatelessWidget {
  const JournalEmptyTradesNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        strings.text('No trades synced for this day.'),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class JournalTradeListItem extends StatelessWidget {
  final JournalOverviewTrade trade;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onDoublePressed;

  const JournalTradeListItem({
    super.key,
    required this.trade,
    required this.selected,
    required this.onPressed,
    required this.onDoublePressed,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = isBuyDirection(trade.direction);
    final directionText = tradeDirectionText(trade.direction);
    final pnlColor = trade.pnl >= 0 ? AppColors.success : AppColors.danger;

    return GestureDetector(
      onTap: onPressed,
      onDoubleTap: onDoublePressed,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            const JournalPairDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        trade.symbol,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isBuy ? FluentIcons.up : FluentIcons.down,
                        size: 10,
                        color: isBuy ? AppColors.success : AppColors.danger,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        directionText,
                        style: TextStyle(
                          color: isBuy ? AppColors.success : AppColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tradeMetaLine(trade),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  moneyValue(trade.pnl),
                  style: TextStyle(
                    color: pnlColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${trade.rMultiple > 0 ? '+' : ''}${trade.rMultiple.toStringAsFixed(2)}R',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class JournalDayMetric extends StatelessWidget {
  final String value;
  final String label;

  const JournalDayMetric(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class JournalRiskLine extends StatelessWidget {
  final String label;
  final double value;
  final bool highIsGood;

  const JournalRiskLine({
    super.key,
    required this.label,
    required this.value,
    this.highIsGood = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedValue = value > 1 ? value / 100 : value;
    final progress = normalizedValue.clamp(0.0, 1.0);
    final percentLabel = value > 1 ? value.round() : (value * 100).round();
    final color = _barColor(progress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
            Text(
              '$percentLabel%',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: progress),
              builder: (context, progress, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Color _barColor(double value) {
    if (highIsGood) {
      return value >= 0.65 ? AppColors.success : AppColors.warning;
    }
    if (value >= 0.85) return AppColors.danger;
    if (value >= 0.5) return AppColors.warning;
    return AppColors.success;
  }
}

class JournalTradeTabs extends StatelessWidget {
  final JournalTradeFilter selected;
  final ValueChanged<JournalTradeFilter> onChanged;

  const JournalTradeTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        JournalTabChip(
          strings.text('All'),
          selected: selected == JournalTradeFilter.all,
          onPressed: () => onChanged(JournalTradeFilter.all),
        ),
        const SizedBox(width: 8),
        JournalTabChip(
          strings.text('Wins'),
          selected: selected == JournalTradeFilter.wins,
          onPressed: () => onChanged(JournalTradeFilter.wins),
        ),
        const SizedBox(width: 8),
        JournalTabChip(
          strings.text('Losses'),
          selected: selected == JournalTradeFilter.losses,
          onPressed: () => onChanged(JournalTradeFilter.losses),
        ),
      ],
    );
  }
}

class JournalTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const JournalTabChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
