import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_overview_support.dart';

class JournalCalendarDayTile extends StatelessWidget {
  final JournalCalendarDay day;
  final bool selected;
  final VoidCallback onPressed;

  const JournalCalendarDayTile({
    super.key,
    required this.day,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrades = day.tradeCount > 0;
    final pnlColor = day.pnl >= 0 ? AppColors.success : AppColors.danger;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySoft
              : day.isMuted
              ? AppColors.surfaceAlt
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: day.isMuted
                      ? AppColors.textSecondary.withValues(alpha: 0.55)
                      : AppColors.textPrimary,
                ),
              ),
            ),
            if (day.hasReview)
              Align(
                alignment: Alignment.topLeft,
                child: Icon(
                  FluentIcons.edit_note,
                  size: 13,
                  color: AppColors.warning,
                ),
              ),
            if (hasTrades)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 96,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: pnlColor.withValues(alpha: 0.42)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        moneyValue(day.pnl),
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${day.tradeCount} trade${day.tradeCount == 1 ? '' : 's'}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
