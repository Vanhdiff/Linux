import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/defaults/news_fallback_data.dart';

class NewsCalendarPanel extends StatelessWidget {
  final List<CalendarDayData> days;
  final DateTime visibleMonth;
  final ValueChanged<CalendarDayData>? onDaySelected;
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  const NewsCalendarPanel({
    super.key,
    required this.days,
    required this.visibleMonth,
    this.onDaySelected,
    this.onPreviousMonth,
    this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CalendarHeader(
            visibleMonth: visibleMonth,
            onPreviousMonth: onPreviousMonth,
            onNextMonth: onNextMonth,
          ),
          SizedBox(height: 14),
          _WeekdayHeader(),
          SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;

              return GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: days.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: compact ? 0.98 : 1.28,
                ),
                itemBuilder: (context, index) => _CalendarDayTile(
                  days[index],
                  onPressed: onDaySelected == null
                      ? null
                      : () => onDaySelected!(days[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  final DateTime visibleMonth;
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  const _CalendarHeader({
    required this.visibleMonth,
    this.onPreviousMonth,
    this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        _NavButton(FluentIcons.chevron_left, onPressed: onPreviousMonth),
        SizedBox(width: 6),
        _NavButton(FluentIcons.chevron_right, onPressed: onNextMonth),
        SizedBox(width: 12),
        Text(
          _monthTitle(visibleMonth, strings.isVietnamese),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Spacer(),
        _LegendDot(AppColors.danger, strings.text('High')),
        SizedBox(width: 10),
        _LegendDot(AppColors.warning, strings.text('Medium')),
        SizedBox(width: 10),
        _LegendDot(AppColors.textSecondary, strings.text('Low')),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final labels = strings.isVietnamese
        ? const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(children: [for (final label in labels) _Weekday(label)]);
  }
}

class _Weekday extends StatelessWidget {
  final String label;

  const _Weekday(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  final CalendarDayData day;
  final VoidCallback? onPressed;

  const _CalendarDayTile(this.day, {this.onPressed});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final borderColor = day.isSelected ? AppColors.primary : AppColors.border;
    final backgroundColor = day.isSelected
        ? AppColors.primarySoft
        : day.isMuted
        ? AppColors.surfaceAlt
        : AppColors.surface;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: borderColor,
            width: day.isSelected ? 1.4 : 1,
          ),
          boxShadow: day.isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: day.isMuted
                      ? Color(0xFFB7B0C4)
                      : day.isSelected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            if (day.isToday || day.isBlocked)
              Align(
                alignment: Alignment.topLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (day.isToday)
                      _DayBadge(strings.text('Today'), AppColors.primary),
                    if (day.isToday && day.isBlocked) SizedBox(height: 4),
                    if (day.isBlocked)
                      _DayBadge(strings.text('High'), AppColors.danger),
                  ],
                ),
              ),
            Align(alignment: Alignment.bottomLeft, child: _ImpactCounts(day)),
          ],
        ),
      ),
    );
  }
}

class _DayBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _DayBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ImpactCounts extends StatelessWidget {
  final CalendarDayData day;

  const _ImpactCounts(this.day);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (day.highImpact > 0) _ImpactCount(AppColors.danger, day.highImpact),
        if (day.mediumImpact > 0)
          _ImpactCount(AppColors.warning, day.mediumImpact),
        if (day.lowImpact > 0)
          _ImpactCount(AppColors.textSecondary, day.lowImpact),
      ],
    );
  }
}

class _ImpactCount extends StatelessWidget {
  final Color color;
  final int count;

  const _ImpactCount(this.color, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _NavButton(this.icon, {this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.shellBg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: AppColors.surface.withValues(alpha: 0.96),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: Offset(0, 10),
      ),
    ],
  );
}

String _monthTitle(DateTime value, bool vietnamese) {
  const enMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const viMonths = [
    'Tháng 1',
    'Tháng 2',
    'Tháng 3',
    'Tháng 4',
    'Tháng 5',
    'Tháng 6',
    'Tháng 7',
    'Tháng 8',
    'Tháng 9',
    'Tháng 10',
    'Tháng 11',
    'Tháng 12',
  ];
  final month = vietnamese
      ? viMonths[value.month - 1]
      : enMonths[value.month - 1];
  return '$month ${value.year}';
}
