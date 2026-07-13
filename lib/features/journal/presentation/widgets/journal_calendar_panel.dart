import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../../data/defaults/journal_defaults.dart';
import 'journal_calendar_day_tile.dart';
import 'journal_overview_support.dart';

class JournalCalendarPanel extends StatelessWidget {
  final DateTime visibleMonth;
  final List<JournalCalendarDay> days;
  final int? selectedDayIndex;
  final ValueChanged<int> onDaySelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  const JournalCalendarPanel({
    super.key,
    required this.visibleMonth,
    required this.days,
    required this.selectedDayIndex,
    required this.onDaySelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              JournalNavButton(
                FluentIcons.chevron_left,
                onPressed: onPreviousMonth,
              ),
              const SizedBox(width: 6),
              JournalNavButton(
                FluentIcons.chevron_right,
                onPressed: onNextMonth,
              ),
              const SizedBox(width: 12),
              Text(
                monthTitle(visibleMonth),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                strings.text('Syncing trades from MT5'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              JournalLegendDot(AppColors.success, strings.text('Profit')),
              const SizedBox(width: 12),
              JournalLegendDot(AppColors.danger, strings.text('Loss')),
              const SizedBox(width: 12),
              JournalLegendDot(AppColors.warning, strings.text('Reviewed')),
            ],
          ),
          const SizedBox(height: 16),
          const JournalWeekdayHeader(),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.24,
            ),
            itemBuilder: (context, index) {
              return JournalCalendarDayTile(
                day: days[index],
                selected: selectedDayIndex == index,
                onPressed: () => onDaySelected(index),
              );
            },
          ),
        ],
      ),
    );
  }
}
